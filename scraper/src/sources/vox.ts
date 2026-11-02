// VOX Cinemas Egypt — presale days only. VOX's week comes through elCinema;
// this adds what's on sale further out (a big release weeks ahead).
//
// VOX answers a bot that says who it is, and its robots.txt allows film pages
// but no URL with a query string. So this reads only the film pages listed in
// VOX's own sitemap, one at a time, and never the `?d=` day links: each film
// page shows its first day on sale, which for a presale is its opening day.
// The rest of its days arrive through elCinema once they're inside its week.
//
// Shows are filed under the VOX cinemas elCinema already gave us
// (elcinema:city-centre-almaza, …), so the app sees one cinema, not two.

import * as cheerio from 'cheerio';
import { clean, errorMessage, fetchText, hallName, slugOf } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { cairoToday, dayFromLabel, presaleFrom, showStart } from '../time.js';
import { elcinemaCinemaId } from './elcinema.js';

const ORIGIN = 'https://egy.voxcinemas.com';
const SITEMAP = 'https://assets.voxcinemas.com/sitemap/sitemap.EG.xml';
const PAUSE_MS = 1000;

const pause = () => new Promise((r) => setTimeout(r, PAUSE_MS));
const slug = (name: string) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

/** "Avengers: Doomsday (Infinity Vision)" → the film, plus the experience as part of the format. */
export function splitTitle(title: string): { title: string; experience?: string } {
  const m = /^(.*?)\s*\(([^)]*Vision[^)]*)\)\s*$/i.exec(title);
  return m ? { title: m[1], experience: m[2] } : { title };
}

async function filmPages(): Promise<string[]> {
  const xml = await fetchText(SITEMAP);
  const urls = [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => m[1]);
  return [...new Set(urls.filter((u) => /^https:\/\/egy\.voxcinemas\.com\/movies\/[^/?#]+$/.test(u)))];
}

function parseFilm(out: ResultBuilder, $: cheerio.CheerioAPI, url: string, from: string, today: string) {
  // The day shown is the date tab without a link.
  const day = dayFromLabel(clean($('nav.date-filter li > span').first().text()), today);
  if (!day || day < from) return;

  const { title, experience } = splitTitle(clean($('#showtimes h2').first().text()).replace(/\s*-\s*Showtimes$/i, ''));
  if (!title) return out.warn(`VOX ${url}: no title (layout changed?)`);
  const filmSlug = experience ? slugOf(url).replace(new RegExp(`-${slug(experience)}$`), '') : slugOf(url);
  const filmId = out.film({ slug: filmSlug, title, url: `${ORIGIN}/movies/${filmSlug}` });

  let cinemaId: string | null = null;
  $('#showtimes .dates')
    .children()
    .each((_, el) => {
      const node = $(el);
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
          .find('a.showtime')
          .each((_, a) => {
            const start = showStart(day, clean($(a).text()));
            if (start) out.showtime({ cinemaId: at, filmId, businessDate: day, start, format, bookingUrl: $(a).attr('href') });
          });
      });
    });
}

export const vox: Source = {
  id: 'vox',
  async scrape() {
    const out = new ResultBuilder('vox');
    const today = cairoToday();
    const from = presaleFrom();
    const pages = await filmPages();
    if (!pages.length) throw new Error('VOX sitemap lists no film pages (moved?)');

    for (const url of pages) {
      try {
        parseFilm(out, cheerio.load(await fetchText(url)), url, from, today);
      } catch (e) {
        out.warn(`VOX ${url}: ${errorMessage(e)}`);
      }
      await pause();
    }
    // No presales anywhere is a normal week, not a failure.
    return out.build();
  },
};
