// Alerts for followed films, after each sync. For each phone and film, this
// run's new showtimes at the phone's cinemas make one of:
//   opened — the film had nothing on sale there before ("tickets are out"),
//   days   — booking now reaches days that weren't on sale (a week added),
//   shows  — more showtimes on days already on sale.
// "New" is judged against showtimes_seen (004_showtimes_seen.sql), which
// remembers every show until it's over, so a show that drops out of one
// scrape and comes back isn't announced again.
// At most one notification per film per phone per day.

import type { SupabaseClient } from '@supabase/supabase-js';
import { Fcm, StaleToken } from './fcm.js';
import { errorMessage } from './http.js';
import { cairoToday } from './time.js';

export type Seen = { movie_id: string; cinema_id: string; business_date: string; starts_at: string; first_seen_at?: string };
type Device = { token: string; following: string[]; cinemas: string[] };

export type Alert =
  | { kind: 'opened'; cinemas: string[] }
  | { kind: 'days'; cinemas: string[]; lastDay: string }
  | { kind: 'shows'; cinemas: string[]; count: number };

const PAGE = 1000;

async function all<T>(query: () => any): Promise<T[]> {
  const rows: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await query().range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    rows.push(...(data as T[]));
    if (data.length < PAGE) return rows;
  }
}

const day = (r: Seen) => `${r.cinema_id}|${r.business_date}`;
const show = (r: Seen) => `${r.cinema_id}|${Date.parse(r.starts_at)}`;
const unique = <T>(xs: T[]) => [...new Set(xs)];

/**
 * What one phone hears about one film. `fresh` is this run's new upcoming
 * showtimes and `before` the upcoming ones seen in earlier runs, both already
 * narrowed to the phone's cinemas.
 */
export function alertFor(freshRows: Seen[], before: Seen[]): Alert | null {
  // The same show under a new id is not news: a presale show passing from
  // VOX's own site to elCinema's listing, say.
  const known = new Set(before.map(show));
  const fresh = freshRows.filter((r) => !known.has(show(r)));
  if (!fresh.length) return null;
  if (!before.length) return { kind: 'opened', cinemas: unique(fresh.map((r) => r.cinema_id)) };

  const onSale = new Set(before.map(day));
  const newDays = fresh.filter((r) => !onSale.has(day(r)));
  if (newDays.length) {
    return {
      kind: 'days',
      cinemas: unique(newDays.map((r) => r.cinema_id)),
      lastDay: newDays.map((r) => r.business_date).sort().at(-1)!,
    };
  }
  return { kind: 'shows', cinemas: unique(fresh.map((r) => r.cinema_id)), count: fresh.length };
}

/** The notification for an alert, in Arabic like the rest of the app's pushes. */
export function message(alert: Alert, film: string, cinemaLabel: (id: string) => string) {
  const first = cinemaLabel(alert.cinemas[0]);
  const where = alert.cinemas.length > 1 ? `${first} و${alert.cinemas.length - 1} سينما كمان` : first;
  switch (alert.kind) {
    case 'opened':
      return { title: `🎟 تذاكر «${film}» نزلت`, body: `الحجز فتح في ${where}` };
    case 'days':
      return { title: `📅 «${film}»: أيام حجز جديدة`, body: `الحجز بقى لحد ${dayName(alert.lastDay)} في ${where}` };
    case 'shows':
      return { title: `🕐 «${film}»: حفلات جديدة`, body: `${showCount(alert.count)} في ${where}` };
  }
}

/** "الخميس 12 نوفمبر", as the app writes days. */
export function dayName(businessDate: string) {
  const parts = new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    timeZone: 'UTC',
  }).formatToParts(new Date(`${businessDate}T00:00:00Z`));
  const part = (type: string) => parts.find((p) => p.type === type)?.value;
  return `${part('weekday')} ${part('day')} ${part('month')}`;
}

export function showCount(n: number) {
  if (n === 1) return 'حفلة جديدة';
  if (n === 2) return 'حفلتين جداد';
  if (n <= 10) return `${n} حفلات جديدة`;
  return `${n} حفلة جديدة`;
}

/** scrape_runs rows with this source mark how far alerts have been checked. */
const ALERTS = 'alerts';
const MAX_LOOKBACK_MS = 24 * 3600_000;

/**
 * Where the last alerts check stopped. Showtimes added since, by this run or
 * by a sync that couldn't send pushes (one run by hand without the Firebase
 * key), are what's new now.
 */
async function lastCheck(db: SupabaseClient, runStartedAt: string): Promise<string> {
  const { data, error } = await db
    .from('scrape_runs')
    .select('started_at')
    .eq('source', ALERTS)
    .order('started_at', { ascending: false })
    .limit(1);
  if (error) throw new Error(`alerts checkpoint: ${error.message}`);
  const last = data?.[0]?.started_at as string | undefined;
  if (!last) return runStartedAt;
  const floor = new Date(Date.now() - MAX_LOOKBACK_MS).toISOString();
  return new Date(last).toISOString() > floor ? new Date(last).toISOString() : floor;
}

export async function notifyDrops(db: SupabaseClient, runStartedAt: string) {
  const fcm = Fcm.fromEnv();
  if (!fcm) return console.log('  notifications: FIREBASE_SERVICE_ACCOUNT not set, skipped (the next run that can send picks these up)');

  const now = new Date().toISOString();
  await announce(db, fcm, await lastCheck(db, runStartedAt), now);
  const { error } = await db.from('scrape_runs').insert({ source: ALERTS, started_at: now, ok: true });
  if (error) throw new Error(`save alerts checkpoint: ${error.message}`);
}

async function announce(db: SupabaseClient, fcm: Fcm, since: string, now: string) {
  const fresh = await all<Seen>(() =>
    db
      .from('showtimes_seen')
      .select('movie_id,cinema_id,business_date,starts_at,first_seen_at')
      .gte('first_seen_at', since)
      .lt('first_seen_at', now)
      .gt('starts_at', now)
      .order('id'),
  );
  if (!fresh.length) return console.log('  notifications: no new showtimes');

  const movieIds = unique(fresh.map((r) => r.movie_id));
  const devices = await all<Device>(() =>
    db.from('devices').select('token,following,cinemas').overlaps('following', movieIds).order('token'),
  );
  if (!devices.length) return console.log(`  notifications: ${movieIds.length} films got showtimes, nobody follows them`);

  // Successful devices advance independently of failed devices. This survives
  // midnight, unlike the per-day rate limit in notifications_sent.
  const progress = await all<{ token: string; movie_id: string; checked_through: string }>(() =>
    db.from('notification_progress').select('token,movie_id,checked_through')
      .in('movie_id', movieIds).order('token').order('movie_id'),
  );
  const checked = new Map(progress.map((p) => [`${p.token}|${p.movie_id}`, p.checked_through]));
  const advance = async (token: string, movie_id: string) => {
    const { error } = await db.from('notification_progress').upsert(
      { token, movie_id, checked_through: now }, { onConflict: 'token,movie_id' },
    );
    if (error) throw new Error(`save device notification progress: ${error.message}`);
  };

  const followed = movieIds.filter((id) => devices.some((d) => d.following.includes(id)));
  const before = await all<Seen>(() =>
    db
      .from('showtimes_seen')
      .select('movie_id,cinema_id,business_date,starts_at')
      .in('movie_id', followed)
      .lt('first_seen_at', since)
      .gt('starts_at', now)
      .order('id'),
  );
  const byMovie = (rows: Seen[]) => {
    const m = new Map<string, Seen[]>();
    for (const r of rows) m.set(r.movie_id, [...(m.get(r.movie_id) ?? []), r]);
    return m;
  };
  const freshBy = byMovie(fresh);
  const beforeBy = byMovie(before);

  const [{ data: movies }, { data: cinemas }] = await Promise.all([
    db.from('movies').select('id,tmdb_id,title,title_ar,original_title').in('id', followed),
    db.from('cinemas').select('id,chain,name,name_ar').in('id', unique(fresh.map((r) => r.cinema_id))),
  ]);
  const title = new Map((movies ?? []).map((m) => [m.id, displayTitle(m)]));
  const label = new Map((cinemas ?? []).map((c) => [c.id, cinemaLabel(c)]));

  const today = cairoToday();
  const counts = { opened: 0, days: 0, shows: 0 };
  let failed = false;
  for (const device of devices) {
    // A phone that picked its cinemas hears only about those.
    const mine = (rows: Seen[]) =>
      device.cinemas.length ? rows.filter((r) => device.cinemas.includes(r.cinema_id)) : rows;

    for (const movieId of device.following) {
      const through = checked.get(`${device.token}|${movieId}`);
      const rows = mine(freshBy.get(movieId) ?? []);
      const handled = (row: Seen) => !!through && !!row.first_seen_at && row.first_seen_at < through;
      const alert = alertFor(rows.filter((r) => !handled(r)), [
        ...mine(beforeBy.get(movieId) ?? []), ...rows.filter(handled),
      ]);
      if (!alert) continue;

      // The primary key makes this the once-a-day check: a second insert fails.
      const { error: seen } = await db
        .from('notifications_sent')
        .insert({ token: device.token, movie_id: movieId, sent_on: today });
      if (seen) {
        if (seen.code === '23505') {
          // Consume updates intentionally suppressed by today's rate limit,
          // so another phone's retry cannot resurrect them tomorrow.
          await advance(device.token, movieId);
          continue;
        }
        throw new Error(`reserve notification: ${seen.message}`);
      }

      try {
        await fcm.send({
          token: device.token,
          ...message(alert, title.get(movieId) ?? movieId, (id) => label.get(id) ?? id),
          data: { movieId },
        });
      } catch (e) {
        // A failed send must not consume today's notification or advance the
        // checkpoint: the next run needs to pick this alert up again.
        const { error: release } = await db.from('notifications_sent').delete()
          .eq('token', device.token).eq('movie_id', movieId).eq('sent_on', today);
        if (release) throw new Error(`release failed notification: ${release.message}`);
        if (e instanceof StaleToken) {
          const { error } = await db.from('devices').delete().eq('token', device.token);
          if (error) throw new Error(`remove stale device: ${error.message}`);
          break;
        }
        failed = true;
        console.log(`  ! notification to …${device.token.slice(-6)}: ${errorMessage(e)}`);
        continue;
      }
      await advance(device.token, movieId);
      counts[alert.kind]++;
    }
  }
  console.log(
    `✓ notifications: ${counts.opened} opened, ${counts.days} new days, ${counts.shows} new showtimes`,
  );
  if (failed) throw new Error('Some notifications failed; checkpoint retained for retry');
}

const CHAINS_AR: Record<string, string> = {
  Renaissance: 'رينيسانس',
  Scene: 'سين',
  Premiere: 'بريمير',
  VOX: 'ڤوكس',
};

/** As the app labels a cinema in Arabic (Cinema.label). */
function cinemaLabel(c: { id: string; chain: string; name: string; name_ar: string | null }) {
  if (c.name_ar) return c.id.startsWith('elcinema:') ? c.name_ar : `${CHAINS_AR[c.chain] ?? c.chain} · ${c.name_ar}`;
  return c.chain === 'Independent' ? c.name : `${c.chain} · ${c.name}`;
}

const ARABIC_LETTERS = /[ء-ي]/;
/** Letters Persian, Kurdish and Urdu add: a Kurdish title is in Arabic script but isn't Arabic. */
const OTHER_SCRIPT_LETTERS = /[پ-ۿ]/;

/** As the app shows it (Movie.displayTitle): Arabic films by their Arabic title, foreign ones in English. */
function displayTitle(m: { tmdb_id: number | null; title: string; title_ar: string | null; original_title: string | null }) {
  const original = m.original_title ?? (m.tmdb_id == null ? (m.title_ar ?? '') : m.title);
  const arabic = ARABIC_LETTERS.test(original) && !OTHER_SCRIPT_LETTERS.test(original);
  return arabic ? (m.title_ar ?? m.original_title ?? m.title) : m.title;
}
