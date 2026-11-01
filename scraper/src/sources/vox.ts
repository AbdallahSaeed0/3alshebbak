// VOX Cinemas Egypt. Its bot protection stalls every plain HTTP client, so
// this opens today's /showtimes in a real browser, then fetches every other
// date from inside the page (same origin, so the requests carry the cookies the
// protection script just set) and parses them there — the approach the
// Pitflix desktop app uses.

import { newContext } from '../browser.js';
import { clean, errorMessage } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { showStart } from '../time.js';

const ORIGIN = 'https://egy.voxcinemas.com';
const PAGE_TIMEOUT_MS = 60_000;

interface VoxTime { time: string; bookingUrl: string | null }
interface VoxMovie {
  slug: string;
  title: string;
  classification: string | null;
  language: string | null;
  durationMins: number | null;
  posterUrl: string | null;
  cinemas: { name: string; formats: { name: string; times: VoxTime[] }[] }[];
}
interface VoxDay { date: string; movies: VoxMovie[] }

/** Runs inside the VOX page. Must be self-contained: Playwright serializes it. */
async function crawlInPage(): Promise<{ days: VoxDay[]; failed: string[] }> {
  const text = (el: Element | null | undefined) => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
  const abs = (href: string | null) => {
    try { return href ? new URL(href, location.origin).href : null; } catch { return null; }
  };
  const dateParam = (href: string | null) => {
    const m = /[?&]d=(\d{4})(\d{2})(\d{2})/.exec(href ?? '');
    return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
  };
  const cairoToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo' }).format(new Date());

  function parse(doc: Document, date: string): VoxDay {
    const movies = Array.from(doc.querySelectorAll('article.movie-compare')).map((art) => {
      const hero = art.querySelector('aside.movie-hero');
      const tags = Array.from(hero?.querySelectorAll('.tag') ?? []).map(text);
      const durationTag = tags.find((t) => /\bmin\b/.test(t));
      const cinemas: VoxMovie['cinemas'] = [];
      let current: VoxMovie['cinemas'][number] | null = null;
      for (const child of Array.from(art.querySelector('.dates')?.children ?? [])) {
        if (child.tagName === 'H3') {
          current = { name: text(child), formats: [] };
          cinemas.push(current);
        } else if (child.matches('ol.showtimes') && current) {
          for (const li of Array.from(child.children)) {
            const times = Array.from(li.querySelectorAll('a.showtime')).map((t) => ({
              time: text(t),
              bookingUrl: abs(t.getAttribute('href')),
            }));
            if (times.length) current.formats.push({ name: text(li.querySelector('strong')) || 'Standard', times });
          }
        }
      }
      return {
        slug: art.getAttribute('data-slug') ?? '',
        title: text(hero?.querySelector('h2')),
        classification: text(hero?.querySelector('.classification')) || null,
        language: tags.find((t) => t !== durationTag) ?? null,
        durationMins: durationTag ? parseInt(durationTag, 10) || null : null,
        posterUrl: abs(hero?.querySelector('img')?.getAttribute('src') ?? null),
        cinemas: cinemas.filter((c) => c.formats.length),
      };
    });
    return { date, movies };
  }

  const today = cairoToday();
  const dates = new Set<string>();
  document.querySelectorAll('a[href*="/showtimes?d="]').forEach((a) => {
    const d = dateParam(a.getAttribute('href'));
    if (d && d !== today) dates.add(d);
  });

  const days = [parse(document, today)];
  const failed: string[] = [];
  const queue = [...dates];
  async function worker() {
    for (let d = queue.shift(); d; d = queue.shift()) {
      try {
        const res = await fetch(`/showtimes?d=${d.replace(/-/g, '')}`, { credentials: 'include' });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const doc = new DOMParser().parseFromString(await res.text(), 'text/html');
        // A bot-check interstitial also comes back 200; make sure it's the real page.
        if (!doc.querySelector('article.movie-compare')) throw new Error('no showtimes on the page');
        days.push(parse(doc, d));
      } catch (e) {
        failed.push(`${d}: ${e instanceof Error ? e.message : e}`);
      }
    }
  }
  await Promise.all([worker(), worker(), worker(), worker()]);
  return { days, failed };
}

export const vox: Source = {
  id: 'vox',
  async scrape() {
    const out = new ResultBuilder('vox');
    const context = await newContext();
    try {
      const page = await context.newPage();
      await page.goto(`${ORIGIN}/showtimes`, { waitUntil: 'domcontentloaded', timeout: PAGE_TIMEOUT_MS });
      // The bot check may serve an interstitial first; wait for the real page.
      try {
        await page.waitForSelector('article.movie-compare, a[href*="/showtimes?d="]', { timeout: PAGE_TIMEOUT_MS });
      } catch {
        throw new Error(`VOX never served its showtimes page (title: "${clean(await page.title())}") — bot protection?`);
      }
      const { days, failed } = await page.evaluate(crawlInPage);
      for (const f of failed) out.warn(`VOX date ${f}`);

      for (const day of days) {
        for (const m of day.movies) {
          if (!m.slug) continue;
          const filmId = out.film({
            slug: m.slug,
            title: m.title,
            url: `${ORIGIN}/movies/${m.slug}`,
            posterUrl: m.posterUrl ?? undefined,
            classification: m.classification ?? undefined,
            language: m.language ?? undefined,
            durationMins: m.durationMins ?? undefined,
          });
          for (const c of m.cinemas) {
            const cinemaId = out.cinema({
              slug: c.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''),
              chain: 'VOX',
              name: c.name,
            });
            for (const f of c.formats) {
              for (const t of f.times) {
                const start = showStart(day.date, t.time);
                if (start) out.showtime({ cinemaId, filmId, businessDate: day.date, start, format: f.name, bookingUrl: t.bookingUrl ?? undefined });
              }
            }
          }
        }
      }
    } catch (e) {
      throw new Error(errorMessage(e));
    } finally {
      await context.close();
    }
    const result = out.build();
    if (!result.showtimes.length) throw new Error("Site layout changed: VOX's pages loaded but no showtimes were read");
    return result;
  },
};
