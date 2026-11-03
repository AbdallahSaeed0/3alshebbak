// Only the public date/time dropdowns are read; no seats or orders are created.
import * as cheerio from 'cheerio';
import { clean, USER_AGENT, sleep, errorMessage } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { cairoToday, showStart } from '../time.js';
import { THEATERS, elcinemaCinemaId } from './elcinema.js';

/** Hall plus the booking's category, as elCinema's theater pages name them: "2d" is the plain hall. */
export function bookingFormat(hall: string | undefined, category: string | undefined): string {
  const parts = [clean(hall), clean(category)].filter((p) => p && !/^2d$/i.test(p));
  const distinct = parts.filter((p, i) => parts.findIndex((q) => q.toLowerCase() === p.toLowerCase()) === i);
  return distinct.join(' · ') || 'Standard';
}

export function bookingPairs(html: string) {
  const $ = cheerio.load(html);
  const pairs = new Map<string, { work: string; theater: string; title: string }>();
  $('a[href]').each((_, a) => {
    const match = /^\/(?:en\/)?booking\/(\d+)\/(\d+)\/$/.exec($(a).attr('href') ?? '');
    if (!match) return;
    const title = clean($(a).closest('ul').find('h3 a').text());
    if (title) pairs.set(`${match[1]}|${match[2]}`, { work: match[1], theater: match[2], title });
  });
  return [...pairs.values()];
}

export async function scrapePresales(workIds?: string[]) {
  const out = new ResultBuilder('elcinema-presales');
  const index = await fetch('https://elcinema.com/en/booking/', { headers: { 'User-Agent': USER_AGENT }, signal: AbortSignal.timeout(20_000) });
  if (!index.ok) throw new Error(`Booking index HTTP ${index.status}`);
  const html = await index.text();
  const $ = cheerio.load(html);
  const csrf = $('meta[name="csrf-token"]').attr('content');
  const cookie = index.headers.getSetCookie().map(s => s.split(';')[0]).join('; ');
  if (!csrf) throw new Error('Booking index has no CSRF token');
  const pairs = bookingPairs(html).filter(p => THEATERS.some(t => t.id === p.theater && t.chain === 'Premiere') && (!workIds || workIds.includes(p.work)));
  if (!pairs.length) throw new Error('No Premiere booking links found');
  const request = async (work: string, theater: string, type: string, date: string) => {
    await sleep(1500);
    const body = new URLSearchParams();
    for (const [key, value] of Object.entries({ work_id: work, theater_id: theater, type, date, time: '0', screen_id: '0', category: '2d', source: '2', ss_id: '' })) body.set(`data[${key}]`, value);
    const response = await fetch('https://elcinema.com/en/booking/ajax_dropdowns', {
      method: 'POST', headers: { 'User-Agent': USER_AGENT, 'Content-Type': 'application/x-www-form-urlencoded', 'X-CSRF-Token': csrf, Cookie: cookie }, body,
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) throw new Error(`Booking dropdown HTTP ${response.status}`);
    const rows = await response.json();
    if (!Array.isArray(rows)) throw new Error('Invalid booking dropdown response');
    return rows;
  };
  // A dropped connection now and then shouldn't sink the whole run.
  const dropdown = async (work: string, theater: string, type: string, date = '0') => {
    for (let attempt = 1; ; attempt++) {
      try {
        return await request(work, theater, type, date);
      } catch (e) {
        if (attempt === 3) throw e;
        await sleep(3000 * attempt);
      }
    }
  };
  for (const pair of pairs) {
    const theater = THEATERS.find(t => t.id === pair.theater)!;
    try {
      const days = await dropdown(pair.work, pair.theater, 'dates');
      // Every bookable day, this week's too: elCinema's theater pages can lag
      // a week's changeover, and sync lets these days override them.
      for (const day of days) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(day.value) || day.value < cairoToday()) continue;
        const times = await dropdown(pair.work, pair.theater, 'times', day.value);
        const filmId = out.film({ slug: pair.work, title: pair.title, url: `https://elcinema.com/en/work/${pair.work}/` });
        for (const time of times) {
          const start = showStart(day.value, time.value);
          if (!start) continue;
          out.showtime({ cinemaId: elcinemaCinemaId(theater.chain, theater.venue)!, filmId,
            businessDate: day.value, start, format: bookingFormat(theater.hall, time.category),
            bookingUrl: `https://elcinema.com/en/booking/${pair.work}/${pair.theater}/`,
          });
        }
      }
    } catch (e) { throw new Error(`Presales ${pair.title} / ${theater.venue}: ${errorMessage(e)}`); }
  }
  return out.build();
}

export const elcinemaPresales: Source = { id: 'elcinema-presales', scrape: () => scrapePresales() };
