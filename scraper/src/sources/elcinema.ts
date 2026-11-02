// elCinema.com — tier 2: cinemas whose own sites we can't or don't read: VOX
// (its bot protection rejects automated browsers) and every chain or single
// cinema with no usable site of its own.
//
// elCinema's data is its product, so this source is deliberately polite and
// open about itself: an identifying User-Agent, one request at a time with a
// pause between them, and every cinema carries an attribution the app shows.
// Booking links go to elCinema's own booking page when it has one, so we send
// them visitors in return.
//
// Theater page: /en/theater/<id>/?date=yyyy-mm-dd. One block per film (a `.row`
// holding the film's <h3> link), with <h6> format headings each followed by a
// table of times and prices.

import * as cheerio from 'cheerio';
import { clean, errorMessage, fetchText, sleep } from '../http.js';
import { ResultBuilder, type Source } from '../model.js';
import { showStart } from '../time.js';

const ORIGIN = 'https://elcinema.com';
const PAUSE_MS = 1500;
export const ATTRIBUTION = 'elCinema.com';

interface Theater {
  /** elCinema theater id. */
  id: string;
  chain: string;
  /** The physical cinema. elCinema lists some halls (VIP, Dine-in) as theaters of their own; those share a venue. */
  venue: string;
  /** Set for a hall listed separately; prefixed to its formats ("VIP · Standard"). */
  hall?: string;
  city: string;
  area?: string;
  /** Where to send people to book when elCinema has no booking link for a film. */
  fallbackBooking?: (date: string) => string;
}

const voxBooking = (date: string) => `https://egy.voxcinemas.com/showtimes?d=${date.replace(/-/g, '')}`;

// Chosen from the elCinema inventory (Nov 2026): every Egyptian cinema showing
// at least 3 films that no tier-1 source already covers. Left out on purpose:
// the state-run Alshab (سينما الشعب) screens and single-film halls.
export const THEATERS: Theater[] = [
  // VOX — its own site rejects automated browsers.
  { id: '3101353', chain: 'VOX', venue: 'City Centre Almaza', city: 'Cairo', area: 'Heliopolis', fallbackBooking: voxBooking },
  { id: '3101271', chain: 'VOX', venue: 'Mall of Egypt', city: 'Cairo', area: '6th of October', fallbackBooking: voxBooking },
  { id: '3101027', chain: 'VOX', venue: 'City Centre Alexandria', city: 'Alexandria', area: 'Moharam Bek', fallbackBooking: voxBooking },
  // Premiere — its own site (sources/premiere.ts) blocks the CI servers, so
  // the pipeline reads Premiere here. elCinema has no Nile Cinema or Galaxy
  // elManial. Don't sync the premiere source alongside: Point90 and Arkan
  // would show up twice.
  { id: '3101133', chain: 'Premiere', venue: 'Americana Plaza', city: 'Cairo', area: '6th of October' },
  { id: '3101260', chain: 'Premiere', venue: 'Americana Plaza', hall: 'MX4D', city: 'Cairo', area: '6th of October' },
  { id: '3101134', chain: 'Premiere', venue: 'Americana Plaza', hall: 'IMAX', city: 'Cairo', area: '6th of October' },
  { id: '3101219', chain: 'Premiere', venue: 'Premiere Point90', city: 'Cairo', area: 'New Cairo' },
  { id: '3101261', chain: 'Premiere', venue: 'Premiere Point90', hall: 'MX4D', city: 'Cairo', area: 'New Cairo' },
  { id: '3101401', chain: 'Premiere', venue: 'Cima Arkan', city: 'Cairo', area: 'Sheikh Zayed' },
  { id: '3101402', chain: 'Premiere', venue: 'Cima Arkan', hall: 'VIP', city: 'Cairo', area: 'Sheikh Zayed' },
  // Galaxy
  { id: '3101080', chain: 'Galaxy', venue: 'Galaxy El Maadi', city: 'Cairo', area: 'Maadi' },
  { id: '3101576', chain: 'Galaxy', venue: 'Galaxy El Maadi', hall: 'Dine-in', city: 'Cairo', area: 'Maadi' },
  { id: '3101132', chain: 'Galaxy', venue: 'Galaxy Cineplex Mall of Arabia', city: 'Cairo', area: '6th of October' },
  { id: '3101077', chain: 'Galaxy', venue: 'Galaxy El Gezeera Plaza', city: 'Mansoura' },
  { id: '3101269', chain: 'Galaxy', venue: 'Galaxy Mall of University', city: 'Mansoura' },
  { id: '3101609', chain: 'Galaxy', venue: 'Galaxy Mega', city: 'Sohag', area: 'New Sohag' },
  // Sea Cinema
  { id: '3101048', chain: 'Sea Cinema', venue: 'Sea Cinema Amir', city: 'Alexandria', area: 'Downtown' },
  { id: '3101416', chain: 'Sea Cinema', venue: 'Sea Cinema Royal Plaza', city: 'Alexandria', area: 'Montazah' },
  { id: '3101413', chain: 'Sea Cinema', venue: 'Sea Cinema Arabella', city: 'Cairo', area: 'New Cairo' },
  { id: '3101408', chain: 'Sea Cinema', venue: 'Sea Cinema Tanta', city: 'Tanta' },
  { id: '3101280', chain: 'Sea Cinema', venue: 'Sea Cinema El Gouna', city: 'Hurghada', area: 'El Gouna' },
  { id: '3101362', chain: 'Sea Cinema', venue: 'Sea Cinema Shebin El Kom', city: 'Menofia', area: 'Shebin El Kom' },
  { id: '3101371', chain: 'Sea Cinema', venue: 'Sea Cinema Fayoum', city: 'Fayoum' },
  { id: '3101361', chain: 'Sea Cinema', venue: 'Sea Cinema Luxor', city: 'Luxor' },
  // Stars (City Stars mall)
  { id: '3101050', chain: 'Stars', venue: 'City Stars Cinema', city: 'Cairo', area: 'Nasr City' },
  { id: '3101069', chain: 'Stars', venue: 'Golden Stars', hall: 'Deluxe', city: 'Cairo', area: 'Nasr City' },
  { id: '3101253', chain: 'Stars', venue: 'Golden Stars', hall: 'VIP', city: 'Cairo', area: 'Nasr City' },
  { id: '3101335', chain: 'Stars', venue: 'Golden Stars', hall: 'Elite', city: 'Cairo', area: 'Nasr City' },
  // Smaller chains
  { id: '3101119', chain: 'Sun City', venue: 'Sun City', city: 'Cairo', area: 'Heliopolis' },
  { id: '3101257', chain: 'Sun City', venue: 'Sun City', hall: 'VIP', city: 'Cairo', area: 'Heliopolis' },
  { id: '3101118', chain: 'Cine Max', venue: 'Cine Max', city: 'Cairo', area: '6th of October' },
  { id: '3101495', chain: 'Cine Max', venue: 'Cine Max Minya', city: 'Minya' },
  { id: '3101019', chain: 'Diamond', venue: 'Diamond Bandar Maadi', city: 'Cairo', area: 'Maadi' },
  { id: '3101616', chain: 'Diamond', venue: 'Diamond Marseille Park', city: 'Alexandria', area: 'Montazah' },
  { id: '3101025', chain: 'Metro', venue: 'Cairo Metro', city: 'Cairo', area: 'Downtown' },
  { id: '3101032', chain: 'Metro', venue: 'Alexandria Metro', city: 'Alexandria', area: 'Downtown' },
  { id: '3101045', chain: 'Donia', venue: 'Donia Porto El Sokhna', city: 'Suez', area: 'Ain Sokhna' },
  { id: '3101591', chain: 'Almasa', venue: 'Almasa Matrouh', city: 'Marsa Matrouh' },
  // Independent cinemas
  { id: '3101183', chain: 'Independent', venue: 'Zawya', city: 'Cairo', area: 'Downtown' },
  { id: '3101262', chain: 'Independent', venue: 'Zamalek Cinema', city: 'Cairo', area: 'Zamalek' },
  { id: '3101618', chain: 'Independent', venue: 'El Tahrir Cinema', city: 'Cairo', area: 'Dokki' },
  { id: '3101051', chain: 'Independent', venue: 'Cosmos Cinema', city: 'Cairo', area: 'Downtown' },
  { id: '3101184', chain: 'Independent', venue: 'Lido Cinema', city: 'Cairo', area: 'Downtown' },
  { id: '3101532', chain: 'Independent', venue: 'Universal Cinema', city: 'Cairo', area: 'New Cairo' },
  { id: '3101093', chain: 'Independent', venue: 'Golf City Cinema', city: 'Cairo', area: 'Obour City' },
  { id: '3101342', chain: 'Independent', venue: 'Grand Nile Tower Cinema', city: 'Cairo', area: 'Garden City' },
  { id: '3101021', chain: 'Independent', venue: 'Cairo Mall Cinema', city: 'Cairo' },
  { id: '3101049', chain: 'Independent', venue: 'Green Plaza Cinema', city: 'Alexandria', area: 'Smouha' },
  { id: '3101041', chain: 'Independent', venue: 'Deeb Mall Cinema', city: 'Alexandria', area: 'Roshdy' },
  { id: '3101617', chain: 'Independent', venue: 'Agamy Star Cinema', city: 'Alexandria', area: 'Agamy' },
  { id: '3101475', chain: 'Independent', venue: 'Tulip of Alexandria Cinema', city: 'Alexandria' },
  { id: '3101630', chain: 'Independent', venue: 'White Rose Cinema', city: 'Alexandria', area: 'Montazah' },
  { id: '3101334', chain: 'Independent', venue: 'Grand Hurghada Cinema', city: 'Hurghada' },
  { id: '3101582', chain: 'Independent', venue: 'Kiroseiz Sharm El Sheikh', city: 'Sharm El Sheikh' },
  { id: '3101116', chain: 'Independent', venue: 'Horeya Cinema', city: 'Ismailia', area: 'Downtown' },
  { id: '3101037', chain: 'Independent', venue: 'Sea Way Suez Cinema', city: 'Suez', area: 'Port Tawfik' },
  { id: '3101632', chain: 'Independent', venue: 'Cinematy Port Said', city: 'Port Said' },
  { id: '3101635', chain: 'Independent', venue: 'El Shams Cinema', city: 'Cairo' },
];

const slugify = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const theaterUrl = (id: string, date?: string) => `${ORIGIN}/en/theater/${id}/${date ? `?date=${date}` : ''}`;

/** Dates offered in the page's date picker (yyyy-mm-dd). */
function scheduleDates($: cheerio.CheerioAPI): string[] {
  return $('#theater-showtimes-date-selector option')
    .map((_, o) => $(o).attr('value') ?? '')
    .get()
    .filter((v) => /^\d{4}-\d{2}-\d{2}$/.test(v));
}

/**
 * The id this source gives a chain's venue, for sources that add presale days
 * to the same cinema (vox.ts, premiere.ts). Null for a venue elCinema doesn't list.
 */
export function elcinemaCinemaId(chain: string, venue: string): string | null {
  const s = slugify(venue);
  return THEATERS.some((t) => t.chain === chain && slugify(t.venue) === s) ? `elcinema:${s}` : null;
}

function parseDay(out: ResultBuilder, $: cheerio.CheerioAPI, theater: Theater, date: string) {
  // The picker shows the day actually rendered; a date past the schedule falls back to today.
  const shown = $('#theater-showtimes-date-selector option[selected]').attr('value');
  if (shown && shown !== date) {
    out.warn(`elCinema ${theater.id}: asked for ${date}, page shows ${shown}`);
    return;
  }

  const cinemaId = out.cinema({
    slug: slugify(theater.venue),
    chain: theater.chain,
    name: theater.venue,
    // A separately listed hall's Arabic name is the hall's, not the venue's.
    nameAr: theater.hall ? undefined : clean($('h3.no-margin').first().text()) || undefined,
    city: theater.city,
    area: theater.area,
    url: theaterUrl(theater.id),
    attribution: ATTRIBUTION,
  });

  $('h3 > a[href^="/en/work/"]').each((_, link) => {
    const workHref = $(link).attr('href')!;
    const workId = /\/work\/(\d+)/.exec(workHref)?.[1];
    if (!workId) return;
    const block = $(link).closest('div.row');
    const filmId = out.film({
      slug: workId,
      title: clean($(link).text()),
      url: ORIGIN + workHref,
      posterUrl: block.find('img[data-src]').first().attr('data-src'),
      genres: block.find('a[href*="/genre/"]').map((_, g) => clean($(g).text())).get().join(', ') || undefined,
      language: clean(block.find('a[href*="/language/"]').first().text()) || undefined,
    });
    const booking = block.find(`a[href^="/en/booking/${workId}/${theater.id}"]`).attr('href');
    const bookingUrl = booking ? ORIGIN + booking : theater.fallbackBooking?.(date);

    // Walk the block in document order: an <h6> sets the format for the rows after it.
    let format = theater.hall ?? 'Standard';
    block.find('h6, tr').each((_, el) => {
      if (el.tagName === 'h6') {
        const name = clean($(el).text()) || 'Standard';
        format = theater.hall ? `${theater.hall} · ${name}` : name;
        return;
      }
      const start = showStart(date, $(el).find('strong').first().text());
      if (!start) return;
      const price = parseInt(clean($(el).find('.price').text()), 10);
      out.showtime({
        cinemaId,
        filmId,
        businessDate: date,
        start,
        format,
        bookingUrl,
        priceEgp: Number.isFinite(price) ? price : undefined,
      });
    });
  });
}

export const elcinema: Source = {
  id: 'elcinema',
  async scrape() {
    const out = new ResultBuilder('elcinema');
    // Strictly one request at a time, with a pause: this is someone else's site.
    for (const theater of THEATERS) {
      try {
        const $today = cheerio.load(await fetchText(theaterUrl(theater.id)));
        const dates = scheduleDates($today);
        if (!dates.length) {
          out.warn(`elCinema ${theater.id} (${theater.venue}${theater.hall ? ` ${theater.hall}` : ''}): no date picker — nothing scheduled, or layout changed`);
          continue;
        }
        parseDay(out, $today, theater, dates[0]);
        for (const date of dates.slice(1)) {
          await sleep(PAUSE_MS);
          try {
            parseDay(out, cheerio.load(await fetchText(theaterUrl(theater.id, date))), theater, date);
          } catch (e) {
            out.warn(errorMessage(e));
          }
        }
      } catch (e) {
        out.warn(errorMessage(e));
      }
      await sleep(PAUSE_MS);
    }

    const result = out.build();
    if (!result.showtimes.length) throw new Error('Site layout changed: elCinema pages loaded but no showtimes were read');
    return result;
  },
};
