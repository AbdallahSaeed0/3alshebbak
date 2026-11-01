// Premiere Cinemas. Its showtime API is encrypted, so times are read the way a
// visitor sees them: premiere.page.js clicks cinema → date → format →
// experience on the now-showing page. That costs a few seconds per movie, so a
// few pages work through the movies side by side, each with its own copy of
// the page so their clicks don't collide.

import { fileURLToPath } from 'node:url';
import type { Page } from 'playwright';
import { newContext } from '../browser.js';
import { errorMessage } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { addDays, cairoToday, showStart } from '../time.js';

const ORIGIN = 'https://www.premiere-cinemas.com';
const NOW_SHOWING = `${ORIGIN}/en/now-showing`;
const PAGE_SCRIPT = fileURLToPath(new URL('./premiere.page.js', import.meta.url));
const PAGES = 3;
const DAYS_AHEAD = 7;
const PAGE_TIMEOUT_MS = 60_000;

interface Listing { id: string; title: string; posterUrl: string | null; info: string | null; cinemas: string[]; url: string }
type Days = Record<string, { name: string; formats: { name: string; times: string[] }[] }[]>;

declare global {
  interface Window {
    __shebbakPremiere: { ready(): Promise<Listing[]>; crawl(job: { movieId: string; dates: string[] }): Promise<Days> };
  }
}

async function openNowShowing(page: Page): Promise<Listing[]> {
  await page.goto(NOW_SHOWING, { waitUntil: 'load', timeout: PAGE_TIMEOUT_MS });
  return page.evaluate(() => window.__shebbakPremiere.ready());
}

const slug = (name: string) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

export const premiere: Source = {
  id: 'premiere',
  async scrape() {
    const out = new ResultBuilder('premiere');
    const context = await newContext();
    await context.addInitScript({ path: PAGE_SCRIPT });
    const today = cairoToday();
    const dates = Array.from({ length: DAYS_AHEAD }, (_, i) => addDays(today, i));

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
                  const cinemaId = out.cinema({ slug: slug(b.name), chain: 'Premiere', name: b.name });
                  for (const f of b.formats) {
                    for (const t of f.times) {
                      const start = showStart(date, t);
                      // Times are buttons on the movie page, not links; book from there.
                      if (start) out.showtime({ cinemaId, filmId, businessDate: date, start, format: f.name, bookingUrl: movie.url });
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

    const result = out.build();
    if (!result.showtimes.length) throw new Error("Site layout changed: Premiere's pages loaded but no showtimes were read");
    return result;
  },
};
