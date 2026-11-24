// «آخر فرصة» (last chance): a notification when a film is leaving a phone's
// cinemas. A film is leaving a cinema when the cinema's full program (days
// with at least half the films of its busiest day, so a couple of presale
// films weeks ahead don't count) runs past the film's last day there: the
// next week is out and the film isn't in it. It's last chance for a phone
// when that holds at every one of its cinemas still showing the film — the
// same rule as the app's Home section (AppData.lastChance).
//
// Read from the app's catalog file on the Cloudflare Worker, not the
// database, so it costs no Supabase egress. Checked at most every few hours,
// in the daytime only. Each phone hears about a film's last day once
// (notification_log, kind "last_chance"). Films the phone follows come one
// by one; phones on "every film" get one notification for all of them.
// NO_LAST_CHANCE in a phone's following list turns it off.

import type { SupabaseClient } from '@supabase/supabase-js';
import { Fcm, StaleToken } from './fcm.js';
import { errorMessage } from './http.js';
import { ALL_CINEMAS, dayName, displayTitle, EVERY_FILM, filmCount } from './notify.js';
import { cairoClock } from './weekly.js';
import { addDays, cairoToday } from './time.js';

/** In a device's following list: no last-chance notifications. */
export const NO_LAST_CHANCE = '@no-last-chance';

/** scrape_runs rows with this source mark the last check. */
const MARK = 'last_chance';
const KIND = 'last_chance';
const EVERY_MS = 3 * 3600_000;
/** Cairo hours a check may run in: no notifications at night. */
const FROM_HOUR = 10, UNTIL_HOUR = 22;
/** How soon the last day must be. */
const WITHIN_DAYS = 7;
const PAGE = 1000;
/** A cinema whose films typically show fewer days than this is skipped. */
const MIN_RUN_DAYS = 3;

export type Show = { cinema_id: string; movie_id: string; business_date: string };
type Device = { token: string; following: string[]; cinemas: string[] };
export type Leaving = { movieId: string; lastDay: string; cinemas: string[] };

/**
 * For each cinema, each film leaving it: film → its last day there. [shows]
 * are the catalog's, [today] the Cairo business date.
 */
export function leavingByCinema(shows: Show[], today: string): Map<string, Map<string, string>> {
  const filmsOn = new Map<string, Map<string, Set<string>>>();
  const last = new Map<string, string>();
  for (const s of shows) {
    if (s.business_date < today) continue;
    const days = filmsOn.get(s.cinema_id) ?? filmsOn.set(s.cinema_id, new Map()).get(s.cinema_id)!;
    (days.get(s.business_date) ?? days.set(s.business_date, new Set()).get(s.business_date)!).add(s.movie_id);
    const key = `${s.movie_id}|${s.cinema_id}`;
    if (!last.has(key) || s.business_date > last.get(key)!) last.set(key, s.business_date);
  }
  const out = new Map<string, Map<string, string>>();
  for (const [cinema, days] of filmsOn) {
    // A cinema of one-off screenings (a festival at Zawya: most films on a
    // day or two) has a film "leaving" every day: not what this is for.
    const daysPerFilm = new Map<string, number>();
    for (const films of days.values()) for (const f of films) daysPerFilm.set(f, (daysPerFilm.get(f) ?? 0) + 1);
    const runs = [...daysPerFilm.values()].sort((a, b) => a - b);
    if (runs[Math.floor(runs.length / 2)] < MIN_RUN_DAYS) continue;
    const peak = Math.max(...[...days.values()].map((f) => f.size));
    const enough = Math.max(2, peak / 2);
    const horizon = [...days].filter(([, f]) => f.size >= enough).map(([d]) => d).sort().at(-1);
    if (!horizon) continue;
    const films = new Map<string, string>();
    for (const film of new Set([...days.values()].flatMap((f) => [...f]))) {
      const l = last.get(`${film}|${cinema}`)!;
      if (l < horizon) films.set(film, l);
    }
    out.set(cinema, films);
  }
  return out;
}

/**
 * What's last chance for one phone: films showing at its cinemas whose every
 * cinema there is dropping them, last day within [withinDays], soonest first.
 */
export function leavingFor(
  device: Pick<Device, 'cinemas' | 'following'>,
  shows: Show[],
  leaving: Map<string, Map<string, string>>,
  today: string,
  withinDays = WITHIN_DAYS,
): Leaving[] {
  const everywhere = !device.cinemas.length || device.following.includes(ALL_CINEMAS);
  const mine = (c: string) => everywhere || device.cinemas.includes(c);
  const at = new Map<string, Set<string>>();
  for (const s of shows) {
    if (s.business_date >= today && mine(s.cinema_id)) {
      (at.get(s.movie_id) ?? at.set(s.movie_id, new Set()).get(s.movie_id)!).add(s.cinema_id);
    }
  }
  const until = addDays(today, withinDays);
  const out: Leaving[] = [];
  for (const [movieId, cinemas] of at) {
    const days = [...cinemas].map((c) => leaving.get(c)?.get(movieId));
    if (days.some((d) => !d)) continue; // still on through some cinema's program
    const lastDay = (days as string[]).sort().at(-1)!;
    if (lastDay <= until) out.push({ movieId, lastDay, cinemas: [...cinemas] });
  }
  return out.sort((a, b) => a.lastDay.localeCompare(b.lastDay));
}

/** "النهارده", "بكره", or the day's name. */
export function lastDayText(lastDay: string, today: string) {
  if (lastDay === today) return 'النهارده آخر يوم';
  if (lastDay === addDays(today, 1)) return 'بكره آخر يوم';
  return `آخر يوم ${dayName(lastDay)}`;
}

/** One film the phone follows. */
export function oneMessage(film: string, lastDay: string, where: string, today: string) {
  return { title: `⏳ آخر فرصة تشوف «${film}»`, body: `${lastDayText(lastDay, today)} في ${where}` };
}

/** Several films leaving, for a phone on "every film". */
export function manyMessage(films: string[]) {
  const named = films.slice(0, 2).map((f) => `«${f}»`).join(' و');
  const rest = films.length - 2;
  return {
    title: films.length === 1 ? '⏳ فيلم خارج من سينماتك قريب' : `⏳ ${filmCount(films.length)} خارجين من سينماتك قريب`,
    body: `${rest > 0 ? `${named} و${filmCount(rest)} كمان` : named}: آخر فرصة تشوفهم`,
  };
}

async function all<T>(query: () => any): Promise<T[]> {
  const rows: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await query().range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    rows.push(...(data as T[]));
    if (data.length < PAGE) return rows;
  }
}

type Catalog = {
  showtimes: Show[];
  movies: { id: string; tmdb_id: number | null; title: string; title_ar: string | null; original_title: string | null }[];
  cinemas: { id: string; name: string; name_ar: string | null }[];
};

/** Sends due last-chance notifications. Never throws. */
export async function lastChance(db: SupabaseClient, now = new Date()) {
  try {
    const { hour } = cairoClock(now);
    if (hour < FROM_HOUR || hour >= UNTIL_HOUR) return;
    const fcm = Fcm.fromEnv();
    const base = process.env.CINEMA_FETCH_WORKER_URL;
    if (!fcm || !base) return;
    const { data: last, error } = await db.from('scrape_runs').select('started_at').eq('source', MARK)
      .gt('started_at', new Date(now.getTime() - EVERY_MS).toISOString()).limit(1);
    if (error) throw new Error(`last-chance checkpoint: ${error.message}`);
    if (last?.length) return;
    const { error: mark } = await db.from('scrape_runs').insert({ source: MARK, started_at: now.toISOString(), ok: true });
    if (mark) throw new Error(`last-chance checkpoint: ${mark.message}`);

    const res = await fetch(new URL('/catalog.json', base), { signal: AbortSignal.timeout(60_000) });
    if (!res.ok) throw new Error(`catalog HTTP ${res.status}`);
    const catalog = (await res.json()) as Catalog;
    const today = cairoToday();
    const leaving = leavingByCinema(catalog.showtimes, today);
    if (![...leaving.values()].some((m) => m.size)) return console.log('  last chance: nothing leaving');

    const title = new Map(catalog.movies.map((m) => [m.id, displayTitle(m)]));
    const label = new Map(catalog.cinemas.map((c) => [c.id, c.name_ar ?? c.name]));
    const devices = await all<Device>(() => db.from('devices').select('token,following,cinemas').order('token'));
    // Who already heard about which film's last day (notification_log keeps two weeks).
    const told = new Set(
      (await all<{ device: string; movie_id: string; body: string }>(() =>
        db.from('notification_log').select('device,movie_id,body').eq('kind', KIND).eq('outcome', 'sent').order('id'),
      )).map((r) => `${r.device}|${r.movie_id}|${r.body}`),
    );
    const runAt = now.toISOString();
    const logRows: object[] = [];
    let sent = 0;
    for (const device of devices) {
      if (device.following.includes(NO_LAST_CHANCE)) continue;
      const everyFilm = device.following.includes(EVERY_FILM);
      const tag = device.token.slice(-8);
      const due = leavingFor(device, catalog.showtimes, leaving, today)
        .filter((l) => everyFilm || device.following.includes(l.movieId))
        // The last day is part of what's remembered: a film whose run is
        // extended and then ends again is news again.
        .filter((l) => !told.has(`${tag}|${l.movieId}|${l.lastDay}`));
      if (!due.length) continue;
      const own = due.filter((l) => device.following.includes(l.movieId));
      const others = due.filter((l) => !device.following.includes(l.movieId));
      const pushes = [
        ...own.map((l) => ({
          push: oneMessage(title.get(l.movieId) ?? l.movieId, l.lastDay, label.get(l.cinemas[0]) ?? l.cinemas[0], today),
          films: [l],
        })),
        ...(others.length ? [{ push: manyMessage(others.map((l) => title.get(l.movieId) ?? l.movieId)), films: others }] : []),
      ];
      for (const p of pushes) {
        try {
          await fcm.send({
            token: device.token, ...p.push, ttlSeconds: 86_400,
            data: p.films.length === 1 ? { movieId: p.films[0].movieId } : {},
          });
          sent++;
          for (const l of p.films) {
            logRows.push({
              run_at: runAt, device: tag, movie_id: l.movieId, film: title.get(l.movieId) ?? null,
              outcome: 'sent', kind: KIND, cinemas: l.cinemas, title: p.push.title,
              // body holds the last day, the key told[] checks against.
              body: l.lastDay,
            });
          }
        } catch (e) {
          if (e instanceof StaleToken) break;
          console.log(`  ! last chance to …${device.token.slice(-6)}: ${errorMessage(e)}`);
        }
      }
    }
    for (let i = 0; i < logRows.length; i += 500) {
      const { error: logError } = await db.from('notification_log').insert(logRows.slice(i, i + 500));
      if (logError) console.log(`  ! last-chance log: ${logError.message}`);
    }
    console.log(`✓ last chance: ${sent} notifications`);
  } catch (e) {
    console.log(`  ! last chance: ${errorMessage(e)}`);
  }
}
