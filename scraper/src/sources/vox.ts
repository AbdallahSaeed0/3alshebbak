// VOX Cinemas Egypt, from VOX's own site: every day it has on sale at each of
// its three cinemas, presales included. elCinema lists these cinemas too, but
// its copy drifts from VOX's (times moved, whole days missing, days filled in
// before VOX puts them on sale), so VOX's cinemas are shown from here alone
// (sync drops elCinema's copy; own-site.ts).
//
// Each cinema's showtimes page lists the days on sale and shows one of them;
// the others are its `?d=yyyymmdd` links. VOX's robots.txt asks bots to keep
// off URLs with a query string; reading those day links anyway was a
// deliberate choice (Nov 2026), since nothing else on the site gives a
// cinema's days and elCinema's copy proved wrong. Kept light: one page at a
// time, a pause between them, a client that says who it is.
//
// Shows are filed under the VOX cinemas elCinema already gave us
// (elcinema:city-centre-almaza, …), so the app sees one cinema, not two.

import * as cheerio from 'cheerio';
import { clean, errorMessage, fetchText, hallName } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { addDays, cairoToday, dayFromLabel, showStart } from '../time.js';
import { elcinemaCinemaId } from './elcinema.js';

const ORIGIN = 'https://egy.voxcinemas.com';
const CINEMAS = ['city-centre-almaza', 'mall-of-egypt', 'city-centre-alexandria'];
const PAUSE_MS = 1000;

const pause = () => new Promise((r) => setTimeout(r, PAUSE_MS));
const slug = (name: string) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

/** "Avengers: Doomsday (Infinity Vision)" → the film, plus the experience as part of the format. */
export function splitTitle(title: string): { title: string; experience?: string } {
  const m = /^(.*?)\s*\(([^)]*Vision[^)]*)\)\s*$/i.exec(title);
  return m ? { title: m[1], experience: m[2] } : { title };
}

/** The day a showtimes page shows ("Today", "Tomorrow", "Tue 17 Nov"). */
export function shownDay(label: string, today: string): string | null {
  if (/^today$/i.test(label)) return today;
  if (/^tomorrow$/i.test(label)) return addDays(today, 1);
  return dayFromLabel(label, today);
}

/** The other days a showtimes page links to, as `yyyymmdd`. */
export function otherDays($: cheerio.CheerioAPI): string[] {
  const days = new Set<string>();
  $('nav.date-filter a').each((_, a) => {
    const m = /[?&]d=(\d{8})/.exec($(a).attr('href') ?? '');
    if (m) days.add(m[1]);
  });
  return [...days];
}

/** One day of a cinema's showtimes page: each film, its halls, its times (sold-out ones too). */
export function parseCinemaDay(out: ResultBuilder, $: cheerio.CheerioAPI, day: string) {
  $('article.movie-compare').each((_, el) => {
    const article = $(el);
    const { title, experience } = splitTitle(clean(article.find('h2').first().text()));
    const pageSlug = article.attr('data-slug');
    if (!title || !pageSlug) return out.warn(`VOX ${day}: a film without a title or slug (layout changed?)`);
    const filmSlug = experience ? pageSlug.replace(new RegExp(`-${slug(experience)}$`), '') : pageSlug;
    const filmId = out.film({ slug: filmSlug, title, url: `${ORIGIN}/movies/${filmSlug}` });

    let cinemaId: string | null = null;
    article
      .find('.dates')
      .children()
      .each((_, child) => {
        const node = $(child);
        if (node.is('h3')) {
          const name = clean(node.text());
          cinemaId = elcinemaCinemaId('VOX', name);
          if (!cinemaId) out.warn(`VOX "${name}": not one of elCinema's VOX cinemas, skipped`);
          return;
        }
        if (!cinemaId || !node.is('ol.showtimes')) return;
        const at = cinemaId;
        node.children('li').each((_, li) => {
          const hall = hallName($(li).children('strong').first().text());
          const format = experience ? `${hall} · ${experience}` : hall;
          $(li)
            .find('li[data-id]')
            .each((_, show) => {
              const id = $(show).attr('data-id')!;
              const start = showStart(day, clean($(show).find('.showtime').first().text()));
              if (start) {
                out.showtime({ cinemaId: at, filmId, businessDate: day, start, format, bookingUrl: `${ORIGIN}/booking/${id}` });
              }
            });
        });
      });
  });
}

/** A failed fetch that reads as VOX turning us away rather than a passing fault. */
export const refused = (message: string) => /HTTP (401|403|407|429|451)(?!\d)/.test(message);

export const vox: Source = {
  id: 'vox',
  async scrape() {
    const out = new ResultBuilder('vox');
    const today = cairoToday();
    // A page that can't be read fails the whole run: uploading the rest would
    // delete the unread days' shows, and a failed run keeps the last good copy
    // (and GitHub emails the run's owner, so a refusal gets noticed).
    const failures: string[] = [];
    for (const cinema of CINEMAS) {
      try {
        const first = cheerio.load(await fetchText(`${ORIGIN}/showtimes/${cinema}`));
        const pages: [string, cheerio.CheerioAPI][] = [[`${ORIGIN}/showtimes/${cinema}`, first]];
        for (const d of otherDays(first)) {
          await pause();
          const url = `${ORIGIN}/showtimes?c=${cinema}&d=${d}`;
          try {
            pages.push([url, cheerio.load(await fetchText(url))]);
          } catch (e) {
            failures.push(errorMessage(e));
          }
        }
        for (const [url, $] of pages) {
          // The day the page really shows: a day VOX dropped renders today instead.
          const day = shownDay(clean($('nav.date-filter li > span').first().text()), today);
          const asked = /[?&]d=(\d{4})(\d{2})(\d{2})/.exec(url);
          if (!day || (asked && day !== `${asked[1]}-${asked[2]}-${asked[3]}`)) {
            out.warn(`VOX ${url}: shows "${$('nav.date-filter li > span').first().text().trim()}", skipped`);
            continue;
          }
          parseCinemaDay(out, $, day);
        }
      } catch (e) {
        failures.push(`${cinema}: ${errorMessage(e)}`);
      }
      if (failures.some(refused)) break; // turned away: don't keep knocking
      await pause();
    }
    if (failures.length) {
      throw new Error(
        `${failures.some(refused) ? 'VOX refused the scraper' : "VOX's pages couldn't all be read"} ` +
          `(kept the last good copy): ${failures.slice(0, 3).join(' · ')}`,
      );
    }
    const result = out.build();
    if (!result.showtimes.length) throw new Error("VOX's showtimes pages listed no shows (layout changed?)");
    return result;
  },
};
