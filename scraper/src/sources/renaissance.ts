// Renaissance Cinemas (rnscinemas.com). Plain server-rendered HTML, no bot
// protection: one page per branch per day, `/en/cinemas/<branch>/<dd-mm-yyyy>`.
// Every showtime link carries its own data-* attributes (branch, day, time,
// after-midnight flag, booking URL), so parsing doesn't depend on layout classes
// beyond the per-movie block.
//
// Branch pages link only the next ten days. Presales further out (a big
// release on sale weeks ahead) show up on the film's own page, `/en/movie/<slug>`,
// so those days are read from film pages and then fetched per branch like the rest.

import * as cheerio from 'cheerio';
import { clean, errorMessage, fetchText, pool, slugOf } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { addDays, cairoToday, fromDmy, showStart, toDmy } from '../time.js';

const ORIGIN = 'https://rnscinemas.com';
const PARALLEL = 3;

async function branchUrls(): Promise<string[]> {
  const $ = cheerio.load(await fetchText(`${ORIGIN}/en/cinemas`));
  const urls = new Set<string>();
  $('a[href*="/en/cinemas/"]').each((_, a) => {
    const href = new URL($(a).attr('href')!, ORIGIN).href.replace(/\/+$/, '');
    // Branch pages are exactly one segment under /en/cinemas.
    if (/\/en\/cinemas\/[^/]+$/.test(new URL(href).pathname)) urls.add(href);
  });
  if (!urls.size) throw new Error('Site layout changed: no branch links on /en/cinemas');
  return [...urls];
}

/** Day pages linked from a branch page: `.../<branch>/<dd-mm-yyyy>`. */
function dayUrls($: cheerio.CheerioAPI, branchUrl: string): string[] {
  const urls = new Set<string>();
  $(`a[href^="${branchUrl}/"]`).each((_, a) => {
    const href = $(a).attr('href')!.trim();
    if (fromDmy(href.slice(href.lastIndexOf('/') + 1))) urls.add(href);
  });
  return [...urls];
}

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** "Wednesday 16 Dec" → the next such date on or after `today` (yyyy-mm-dd); the site gives no year. */
export function dayFromLabel(label: string, today: string): string | null {
  const m = /(\d{1,2})\s+([A-Za-z]{3})/.exec(label);
  const month = m ? MONTHS.indexOf(m[2].toLowerCase()) : -1;
  if (!m || month < 0) return null;
  const year = Number(today.slice(0, 4));
  const iso = (y: number) => `${y}-${String(month + 1).padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  // A day a little in the past is still this year (yesterday's late show); far back means next year.
  return iso(year) >= addDays(today, -7) ? iso(year) : iso(year + 1);
}

/** Days any film is on sale, read off the film pages linked from the home page. */
async function filmPageDays(out: ResultBuilder): Promise<Set<string>> {
  const $home = cheerio.load(await fetchText(`${ORIGIN}/en`));
  const films = new Set<string>();
  $home('a[href*="/en/movie/"]').each((_, a) => {
    films.add(new URL($home(a).attr('href')!, ORIGIN).href.split(/[?#]/)[0].replace(/\/+$/, ''));
  });

  const today = cairoToday();
  const days = new Set<string>();
  await pool([...films], PARALLEL, async (url) => {
    try {
      const $ = cheerio.load(await fetchText(url));
      $('a.js-booking-confirm-link').each((_, a) => {
        // An after-midnight show is labelled with the next calendar day.
        if ($(a).attr('data-after-midnight') === '1') return;
        const day = dayFromLabel($(a).attr('data-event-day-en') ?? '', today);
        if (day) days.add(day);
      });
    } catch (e) {
      out.warn(errorMessage(e));
    }
  });
  return days;
}

function parseDay(out: ResultBuilder, $: cheerio.CheerioAPI, branchUrl: string, businessDate: string) {
  const branchSlug = slugOf(branchUrl);
  let cinemaId: string | null = null;

  $('.veneu_item').each((_, item) => {
    const block = $(item);
    const movieHref = block.find('a[href*="/en/movie/"]').first().attr('href');
    if (!movieHref) return;
    const filmId = out.film({
      slug: slugOf(movieHref),
      title: clean(block.find('.venuename').first().text()),
      url: movieHref,
      posterUrl: block.find('img').first().attr('src'),
      genres: clean(block.find('.venuelocation').first().text()).replace(/ - /g, ', ') || undefined,
    });
    // The hall type ("Regular", "Premium", "DBOX", "VIP") heads each block.
    const hall = clean(block.find('.bullitsdivitem').first().text()) || 'Regular';

    block.find('a.js-booking-confirm-link').each((_, a) => {
      const link = $(a);
      if (!cinemaId) {
        cinemaId = out.cinema({
          slug: branchSlug,
          chain: 'Renaissance',
          name: clean(link.attr('data-cinema-name-en')) || branchSlug,
          nameAr: clean(link.attr('data-cinema-name-ar')) || undefined,
          address: clean(link.attr('data-cinema-address-en')) || undefined,
          url: branchUrl,
        });
      }
      const start = showStart(businessDate, link.attr('data-event-time') ?? '', link.attr('data-after-midnight') === '1');
      if (!start) return;
      const experience = clean(link.find('.watch_exprince').text()).replace(/[()]/g, '');
      out.showtime({
        cinemaId,
        filmId,
        businessDate,
        start,
        format: experience && experience !== '2D' ? `${hall} · ${experience}` : hall,
        bookingUrl: clean(link.attr('data-booking-url')) || undefined,
      });
    });
  });
}

export const renaissance: Source = {
  id: 'renaissance',
  async scrape() {
    const out = new ResultBuilder('renaissance');
    const branches = await branchUrls();

    // Each branch page lists its own bookable days; collect them all first.
    const pages: { url: string; date: string }[] = [];
    await pool(branches, PARALLEL, async (branchUrl) => {
      try {
        const $ = cheerio.load(await fetchText(branchUrl));
        const days = dayUrls($, branchUrl);
        if (!days.length) out.warn(`${branchUrl}: no day links (closed, or layout changed)`);
        for (const url of days) pages.push({ url, date: fromDmy(url.slice(url.lastIndexOf('/') + 1))! });
      } catch (e) {
        out.warn(errorMessage(e));
      }
    });

    // Presale days past what the branch pages link, for every branch: a page
    // with nothing on that day just reads as empty.
    const linked = new Set(pages.map((p) => p.date));
    try {
      for (const date of await filmPageDays(out)) {
        if (linked.has(date)) continue;
        for (const branchUrl of branches) pages.push({ url: `${branchUrl}/${toDmy(date)}`, date });
      }
    } catch (e) {
      out.warn(`presale days: ${errorMessage(e)}`);
    }

    await pool(pages, PARALLEL, async ({ url, date }) => {
      try {
        const branchUrl = url.slice(0, url.lastIndexOf('/'));
        parseDay(out, cheerio.load(await fetchText(url)), branchUrl, date);
      } catch (e) {
        out.warn(errorMessage(e));
      }
    });

    const result = out.build();
    if (!result.showtimes.length) throw new Error('Site layout changed: Renaissance pages loaded but no showtimes were read');
    return result;
  },
};
