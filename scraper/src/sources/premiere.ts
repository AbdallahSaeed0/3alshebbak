// Premiere Cinemas. Its showtime API is encrypted, so times are read the way a
// visitor sees them: premiere.page.js clicks cinema → date → format →
// experience on the now-showing page. That costs a few seconds per movie, so a
// few pages work through the movies side by side, each with its own copy of
// the page so their clicks don't collide.
//
// For branches elCinema lists, this adds only presale days past elCinema's
// week, filed under elCinema's cinema. Branches elCinema doesn't list (Nile
// Cinema, Galaxy elManial) get every day, as premiere:* cinemas. Cloudflare
// turns GitHub's runners away from this site, so in CI the anonymous browser
// requests are transported through the private Supabase cinema-fetch function.
// The phone still supports reading it directly as well.

import { fileURLToPath } from 'node:url';
import type { Page } from 'playwright';
import { newContext } from '../browser.js';
import { cinemaFetch, cinemaRelayConfigured } from '../cinema-fetch.js';
import { errorMessage, hallName } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { addDays, cairoToday, presaleFrom, showStart } from '../time.js';
import { elcinemaCinemaId } from './elcinema.js';

const ORIGIN = 'https://www.premiere-cinemas.com';
const NOW_SHOWING = `${ORIGIN}/en/now-showing`;
const PAGE_SCRIPT = fileURLToPath(new URL('./premiere.page.js', import.meta.url));
const PAGES = 3;
/** How far past elCinema's week to look for presale date tiles. */
const PRESALE_DAYS = 60;
const PAGE_TIMEOUT_MS = 60_000;
/** Premiere's branch names where elCinema calls the venue something else. */
const ELCINEMA_VENUE: Record<string, string> = { 'Premiere Plaza': 'Americana Plaza' };

const slug = (name: string) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

/** "2D · PREMIUM" → "Standard", as elCinema names the same halls; "2D · MX4D" → "MX4D". */
export function premiereFormat(name: string): string {
  const parts = name
    .split('·')
    .map((p) => p.trim())
    .filter((p) => p && p !== '2D')
    .map((p) => (/^premium$/i.test(p) ? 'Standard' : hallName(p)));
  return parts.join(' · ') || 'Standard';
}

interface Listing { id: string; title: string; posterUrl: string | null; info: string | null; cinemas: string[]; url: string }
type Days = Record<string, { name: string; formats: { name: string; times: string[] }[] }[]>;

declare global {
  interface Window {
    __shebbakPremiere: { ready(): Promise<Listing[]>; crawl(job: { movieId: string; dates: string[] }): Promise<Days> };
  }
}

async function openNowShowing(page: Page): Promise<Listing[]> {
  const response = await page.goto(NOW_SHOWING, { waitUntil: 'load', timeout: PAGE_TIMEOUT_MS });
  try {
    return await page.evaluate(() => window.__shebbakPremiere.ready());
  } catch (e) {
    // Say what the page was instead, so a failure far away (CI) can be told
    // apart: a layout change, an error page, or a page that never loaded.
    const seen = await page
      .evaluate(() => `"${document.title}" — ${document.body?.innerText.replace(/\s+/g, ' ').slice(0, 200) ?? ''}`)
      .catch(() => '(unreadable)');
    throw new Error(`${errorMessage(e)} [HTTP ${response?.status() ?? '?'} ${page.url()} ${seen}]`);
  }
}


export const premiere: Source = {
  id: 'premiere',
  async scrape() {
    const out = new ResultBuilder('premiere');
    const context = await newContext();
    if (cinemaRelayConfigured()) {
      await context.route('**/*', async (route) => {
        const request = route.request();
        const host = new URL(request.url()).hostname;
        if (['image', 'media', 'font', 'stylesheet'].includes(request.resourceType()) ||
            !['www.premiere-cinemas.com', 'premiere-cinemas.com', 'mifcentral-api.premiere-cinemas.com'].includes(host)) {
          return route.abort();
        }
        try {
          const response = await cinemaFetch(request.url(), request.method(), await request.allHeaders(), request.postData() ?? undefined);
          await route.fulfill({ status: response.status, headers: response.headers, body: response.body });
        } catch (error) {
          out.warn(`Premiere transport: ${errorMessage(error)}`);
          await route.abort();
        }
      });
    }
    await context.addInitScript({ path: PAGE_SCRIPT });
    const from = presaleFrom();
    // From today: branches elCinema doesn't list (Nile Cinema, Galaxy elManial) need every day.
    const today = cairoToday();
    const dates = Array.from({ length: 7 + PRESALE_DAYS }, (_, i) => addDays(today, i));

    try {
      const pages = await Promise.all(Array.from({ length: PAGES }, () => context.newPage()));
      const listing = await openNowShowing(pages[0]);
      for (const m of listing) {
        out.film({ slug: m.id, title: m.title, url: m.url, posterUrl: m.posterUrl ?? undefined, genres: m.info ?? undefined });
      }

      const queue = listing.filter((m) => m.cinemas.length);
      await Promise.all(
        pages.map(async (page, i) => {
          try {
            if (i > 0) await openNowShowing(page);
          } catch (e) {
            out.warn(`Premiere page ${i}: ${errorMessage(e)}`);
            return;
          }
          for (let m = queue.shift(); m; m = queue.shift()) {
            const movie = m;
            try {
              const days = await page.evaluate((job) => window.__shebbakPremiere.crawl(job), { movieId: movie.id, dates });
              const filmId = `premiere:${movie.id}`;
              for (const [date, branches] of Object.entries(days)) {
                for (const b of branches) {
                  const listed = elcinemaCinemaId('Premiere', ELCINEMA_VENUE[b.name] ?? b.name);
                  // elCinema has this branch's week; only the days past it are ours.
                  if (listed && date < from) continue;
                  const cinemaId = listed ?? out.cinema({ slug: slug(b.name), chain: 'Premiere', name: b.name });
                  for (const f of b.formats) {
                    const format = premiereFormat(f.name);
                    for (const t of f.times) {
                      const start = showStart(date, t);
                      // Times are buttons on the movie page, not links; book from there.
                      if (start) out.showtime({ cinemaId, filmId, businessDate: date, start, format, bookingUrl: movie.url });
                    }
                  }
                }
              }
            } catch (e) {
              out.warn(`Premiere "${movie.title}": ${errorMessage(e)}`);
              // The page's picker state is unknown after a failure; start it over.
              await openNowShowing(page).catch(() => {});
            }
          }
        }),
      );
    } finally {
      await context.close();
    }

    // No presales anywhere is a normal week, not a failure.
    return out.build();
  },
};
