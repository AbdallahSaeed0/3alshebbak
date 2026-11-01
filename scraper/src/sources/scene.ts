// Scene Cinemas: one site per venue (cfc.scenecinemas.com, district5.…).
// Plain HTML, no bot protection. Each movie has a page whose showtimes for
// other days load from `?business_day=<dd-mm-yyyy>&ajax=1` — a small fragment
// with the same markup as the page's own showtimes block.

import * as cheerio from 'cheerio';
import { clean, errorMessage, fetchText, pool, slugOf } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { fromDmy, showStart, toDmy } from '../time.js';

const SITES = ['https://cfc.scenecinemas.com', 'https://district5.scenecinemas.com'];
const PARALLEL = 3;

interface MoviePage {
  site: string;
  url: string;
  filmId: string;
  days: string[];
}

/** `.program_item` blocks: a branch line, then format headings each followed by time links. */
function parseShowtimes(out: ResultBuilder, $: cheerio.CheerioAPI, page: MoviePage, businessDate: string) {
  $('.program_item').each((_, item) => {
    const block = $(item);
    const branch = clean(block.find('.branch').first().text());
    const cinemaId = out.cinema({
      slug: new URL(page.site).hostname.split('.')[0],
      chain: 'Scene',
      name: branch.replace(/^Scene Cinema\s*-\s*/i, '') || new URL(page.site).hostname,
      url: page.site,
    });
    // One block per experience, classed by it: `ex_imax_content` + `<span class="ex_imax">`,
    // `ex_stand_content` + `ex_stand`, …
    block.find('[class*="ex_"][class*="_content"]').each((_, fmt) => {
      const format = clean($(fmt).find('span[class^="ex_"]').first().text()) || 'Standard';
      $(fmt)
        .find('a[href*="/showtime-"]')
        .each((_, a) => {
          const start = showStart(businessDate, $(a).text());
          if (!start) return;
          out.showtime({ cinemaId, filmId: page.filmId, businessDate, start, format, bookingUrl: $(a).attr('href') });
        });
    });
  });
}

async function moviePages(out: ResultBuilder, site: string): Promise<string[]> {
  const $ = cheerio.load(await fetchText(`${site}/`));
  const urls = new Set<string>();
  $('a[href*="/movie-details/"]').each((_, a) => {
    urls.add(new URL($(a).attr('href')!, site).href.split('?')[0]);
  });
  if (!urls.size) out.warn(`${site}: no movie links on the home page (layout changed?)`);
  return [...urls];
}

export const scene: Source = {
  id: 'scene',
  async scrape() {
    const out = new ResultBuilder('scene');

    const movieUrls: { site: string; url: string }[] = [];
    for (const site of SITES) {
      try {
        for (const url of await moviePages(out, site)) movieUrls.push({ site, url });
      } catch (e) {
        out.warn(errorMessage(e));
      }
    }

    // Movie pages: the film itself, today's showtimes, and which days exist.
    const pages: MoviePage[] = [];
    await pool(movieUrls, PARALLEL, async ({ site, url }) => {
      try {
        const $ = cheerio.load(await fetchText(url));
        const filmId = out.film({
          slug: slugOf(url),
          title: clean($('title').first().text()),
          genres: clean($('h2').first().text()) || undefined,
          url,
        });
        const days = $('.calanderdays')
          .map((_, li) => fromDmy(($(li).attr('id') ?? '').replace(/^data-/, '')))
          .get()
          .filter((d): d is string => !!d);
        const page = { site, url, filmId, days };
        const today = $('.calanderdays.active').attr('id')?.replace(/^data-/, '');
        const todayIso = today ? fromDmy(today) : null;
        if (todayIso) parseShowtimes(out, $, page, todayIso);
        pages.push({ ...page, days: days.filter((d) => d !== todayIso) });
      } catch (e) {
        out.warn(errorMessage(e));
      }
    });

    // Every other day, from the page's own ajax endpoint.
    const dayJobs = pages.flatMap((page) => page.days.map((date) => ({ page, date })));
    await pool(dayJobs, PARALLEL, async ({ page, date }) => {
      try {
        const html = await fetchText(`${page.url}?business_day=${toDmy(date)}&ajax=1`);
        parseShowtimes(out, cheerio.load(html), page, date);
      } catch (e) {
        out.warn(errorMessage(e));
      }
    });

    const result = out.build();
    if (!result.showtimes.length) throw new Error('Site layout changed: Scene pages loaded but no showtimes were read');
    return result;
  },
};
