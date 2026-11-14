// Wednesday's weekly roundup: new films open in Egypt on Wednesdays, so once a
// week, on the first sync of Wednesday evening, every phone that allows
// notifications hears which films are new this week at its cinemas — one
// notification, also for phones that don't follow any film. A phone turns it
// off with NO_WEEKLY in its following list (the app's "Wednesday roundup"
// switch).

import type { SupabaseClient } from '@supabase/supabase-js';
import { Fcm, StaleToken } from './fcm.js';
import { errorMessage } from './http.js';
import { ALL_CINEMAS, displayTitle, filmCount } from './notify.js';
import { addDays, cairoToday } from './time.js';

/** In a device's following list: no Wednesday roundup. */
export const NO_WEEKLY = '@no-weekly';

/** scrape_runs rows with this source mark that this week's roundup went out. */
const WEEKLY = 'weekly';

/** Sent from this Cairo hour on Wednesday, until midnight. */
const FROM_HOUR = 17;

const PAGE = 1000;

type Device = { token: string; following: string[]; cinemas: string[] };
type Show = { movie_id: string; cinema_id: string };

/** Cairo's weekday (0 = Sunday) and hour now. */
export function cairoClock(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Africa/Cairo', weekday: 'short', hour: 'numeric', hourCycle: 'h23',
  }).formatToParts(now);
  const weekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(parts.find((p) => p.type === 'weekday')!.value);
  return { weekday, hour: Number(parts.find((p) => p.type === 'hour')!.value) };
}

/** Wednesday evening, Cairo time. */
export function roundupTime(now = new Date()) {
  const { weekday, hour } = cairoClock(now);
  return weekday === 3 && hour >= FROM_HOUR;
}

/** The roundup for one phone: its new films, by how many shows they have there. */
export function roundup(films: string[]) {
  const named = films.slice(0, 2).map((f) => `«${f}»`).join(' و');
  const rest = films.length - 2;
  return {
    title: films.length === 1 ? '🍿 فيلم جديد في السينمات الأسبوع ده' : `🍿 ${filmCount(films.length)} جداد في السينمات الأسبوع ده`,
    body: `${rest > 0 ? `${named} و${filmCount(rest)} كمان` : named} في سينماتك`,
  };
}

/**
 * Films new this week at a phone's cinemas, the most shown first. `shows` are
 * this week's showtimes of the films that opened this week.
 */
export function newFor(device: Device, shows: Show[]): string[] {
  const everywhere = !device.cinemas.length || device.following.includes(ALL_CINEMAS);
  const count = new Map<string, number>();
  for (const s of shows) {
    if (everywhere || device.cinemas.includes(s.cinema_id)) count.set(s.movie_id, (count.get(s.movie_id) ?? 0) + 1);
  }
  return [...count.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id);
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

/** Sends this week's roundup if it's Wednesday evening and it hasn't gone out. Never throws. */
export async function weeklyRoundup(db: SupabaseClient, now = new Date()) {
  try {
    if (!roundupTime(now)) return;
    const fcm = Fcm.fromEnv();
    if (!fcm) return console.log('  weekly roundup: FIREBASE_SERVICE_ACCOUNT not set, skipped');

    const { data: last, error } = await db.from('scrape_runs').select('started_at').eq('source', WEEKLY)
      .gt('started_at', new Date(now.getTime() - 5 * 86_400_000).toISOString()).limit(1);
    if (error) throw new Error(`weekly checkpoint: ${error.message}`);
    if (last?.length) return;
    // Marked before sending: a run cancelled halfway must not send it twice
    // (a second sync this evening would otherwise start over).
    const { error: mark } = await db.from('scrape_runs').insert({ source: WEEKLY, started_at: now.toISOString(), ok: true });
    if (mark) throw new Error(`weekly checkpoint: ${mark.message}`);

    const wednesday = cairoToday();
    const week = await all<Show & { business_date: string }>(() =>
      db.from('showtimes').select('movie_id,cinema_id,business_date')
        .gte('business_date', wednesday).lte('business_date', addDays(wednesday, 6)).order('id'),
    );
    // New this week: nothing listed before today (past shows stay in the table).
    const opened: string[] = [];
    for (const id of new Set(week.map((s) => s.movie_id))) {
      const { data, error } = await db.from('showtimes').select('id').eq('movie_id', id).lt('business_date', wednesday).limit(1);
      if (error) throw new Error(`weekly films: ${error.message}`);
      if (!data.length) opened.push(id);
    }
    if (!opened.length) return console.log('  weekly roundup: no new films this week');
    const shows = week.filter((s) => opened.includes(s.movie_id));

    const { data: movies } = await db.from('movies').select('id,tmdb_id,title,title_ar,original_title').in('id', opened);
    const title = new Map((movies ?? []).map((m) => [m.id as string, displayTitle(m)]));
    const devices = await all<Device>(() => db.from('devices').select('token,following,cinemas').order('token'));

    let sent = 0, failed = 0;
    for (const device of devices) {
      if (device.following.includes(NO_WEEKLY)) continue;
      const films = newFor(device, shows);
      if (!films.length) continue;
      const push = roundup(films.map((id) => title.get(id) ?? id));
      try {
        await fcm.send({
          token: device.token, ...push, ttlSeconds: 2 * 86_400,
          // The app's "what's new" screen: these films' coming shows.
          data: {
            type: 'alert', films: JSON.stringify(films.slice(0, 40).map((m) => ({ m, k: 'opened' }))),
            since: addDays(wednesday, -60) + 'T00:00:00Z', until: now.toISOString(),
          },
        });
        sent++;
      } catch (e) {
        if (e instanceof StaleToken) await db.from('devices').delete().eq('token', device.token);
        else failed++;
      }
    }
    console.log(`✓ weekly roundup: ${opened.length} new films, sent to ${sent} phones${failed ? `, ${failed} failed` : ''}`);
  } catch (e) {
    console.log(`  ! weekly roundup: ${errorMessage(e)}`);
  }
}
