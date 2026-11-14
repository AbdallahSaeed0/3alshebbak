// Renaissance Cinemas (rnscinemas.com). Plain server-rendered HTML:
// one page per branch per day, `/en/cinemas/<branch>/<dd-mm-yyyy>`.
// CI uses the private Supabase transport because GitHub IPs are unreliable.
// Every showtime link carries its own data-* attributes (branch, day, time,
// after-midnight flag, booking URL), so parsing doesn't depend on layout classes
// beyond the per-movie block.
//
// Branch pages link only the next ten days. Presales further out (a big
// release on sale weeks ahead) show up on the film's own page, `/en/movie/<slug>`,
// so those days are read from film pages and then fetched per branch like the rest.

import * as cheerio from 'cheerio';
import { clean, errorMessage, fetchText, pool, slugOf } from '../http.js';
import { ResultBuilder, type Showtime, type Source } from '../model.js';
import { supabaseFromEnv } from '../supabase.js';
import { cairoToday, dayFromLabel, fromDmy, showStart, toDmy } from '../time.js';

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

/**
 * Each show's hall, for the app's seat view (data/halls.json, rnsScreenId).
 * Renaissance names no hall where shows are listed; the data its booking page
 * loads (`/en/start_booking/<show id>`, the request any visitor's booking page
 * makes: no seat is held) carries the hall's screen id. Shows are created in
 * batches, one per film schedule, whose ids share their first eight hex
 * digits (the id's creation time), and a batch plays in one hall — checked
 * across all 192 batches of a week on 2026-11-14 — so one lookup tags a batch.
 *
 * That data is ~220 KB a show and, on CI, comes through the Supabase relay,
 * so a batch is looked up once: the halls of batches already stored with a
 * hall are read back from the database (a few KB) and only new batches —
 * a handful a run, once the week's schedule is in — are fetched.
 */
async function tagHalls(showtimes: Showtime[], warn: (message: string) => void) {
  const batches = new Map<string, { id: string; shows: Showtime[] }>();
  for (const s of showtimes) {
    const id = showId(s.bookingUrl);
    if (!id) continue;
    const key = batchKey(s.cinemaId, id);
    const batch = batches.get(key) ?? { id, shows: [] };
    batch.shows.push(s);
    batches.set(key, batch);
  }
  const known = await storedBatchHalls(warn);
  const todo: { id: string; shows: Showtime[] }[] = [];
  for (const [key, batch] of batches) {
    const hall = known.get(key);
    if (hall) for (const s of batch.shows) s.hall = hall;
    else todo.push(batch);
  }
  await pool(todo, PARALLEL, async ({ id, shows }) => {
    try {
      const html = await fetchText(`${ORIGIN}/en/start_booking/${id}`);
      const screen = /screen_id\s*=\s*["']?([0-9a-f]{24})/.exec(html)?.[1];
      if (!screen) return warn(`Renaissance ${id}: no screen id in its booking data (layout changed?)`);
      for (const s of shows) s.hall = rnsHall(screen);
    } catch (e) {
      warn(`Renaissance hall lookup ${id}: ${errorMessage(e)}`);
    }
  });
  console.log(`  renaissance halls: ${batches.size - todo.length} batches known, ${todo.length} looked up`);
}

/**
 * A Renaissance hall as stored on a show: its screen id's last six hex digits
 * ("rns:7fdc72"), kept short because every show in the app's catalog file
 * carries it; unique among the halls of a branch (data/halls.json, rnsScreenId).
 */
const rnsHall = (screenId: string) => `rns:${screenId.slice(-6)}`;

const showId = (bookingUrl?: string | null) => /\/booking\/([0-9a-f]{24})$/.exec(bookingUrl ?? '')?.[1];
const batchKey = (cinemaId: string, showId: string) => `${cinemaId}|${showId.slice(0, 8)}`;

/** Batch → hall, from the shows already stored with a hall (none without a database). */
async function storedBatchHalls(warn: (message: string) => void): Promise<Map<string, string>> {
  const known = new Map<string, string>();
  const db = supabaseFromEnv();
  if (!db) return known;
  const since = new Date(Date.now() - 86_400_000).toISOString();
  try {
    for (let from = 0; ; from += 1000) {
      const { data, error } = await db
        .from('showtimes')
        .select('cinema_id,booking_url,hall')
        .eq('source', 'renaissance')
        .like('hall', 'rns:%')
        .gte('starts_at', since)
        .range(from, from + 999);
      if (error) throw new Error(error.message);
      for (const r of data ?? []) {
        const id = showId(r.booking_url as string | null);
        if (id) known.set(batchKey(r.cinema_id as string, id), r.hall as string);
      }
      if (!data || data.length < 1000) break;
    }
  } catch (e) {
    // e.g. no hall column yet: every batch is looked up this time
    warn(`Renaissance stored halls: ${errorMessage(e)}`);
  }
  return known;
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
    await tagHalls(result.showtimes, (m) => result.warnings.push(m));
    return result;
  },
};
