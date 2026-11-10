// Alerts for followed films, after each sync. For each phone and film, this
// run's new showtimes at the phone's cinemas make one of:
//   opened — the film had nothing on sale there before ("tickets are out"),
//   days   — booking now reaches days that weren't on sale (a week added),
//   shows  — more showtimes on days already on sale.
// "New" is judged against showtimes_seen (004_showtimes_seen.sql), which
// remembers every show until it's over, so a show that drops out of one
// scrape and comes back isn't announced again.
// At most one notification per film per phone per day. A phone can also ask
// for every film (EVERY_FILM in its following list, the app's "all films"
// setting); past a few such alerts in one run, the films it doesn't follow
// go out as one digest. Followed films are always announced on their own.

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

/** In a device's following list: alerts for every film, followed or not. */
export const EVERY_FILM = '*';

/**
 * In a device's following list: alerts from every cinema, not only the ones
 * the phone starred (the app's "all cinemas" choice under notifications).
 */
export const ALL_CINEMAS = '@all-cinemas';

/** More alerts than this in one run go out as one notification. */
const DIGEST_AFTER = 3;

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
  const where = alert.cinemas.length > 1 ? `${first} و${cinemaCount(alert.cinemas.length - 1)} كمان` : first;
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

export function cinemaCount(n: number) {
  if (n === 1) return 'سينما';
  if (n === 2) return 'سينمتين';
  if (n <= 10) return `${n} سينمات`;
  return `${n} سينما`;
}

/** Several films' alerts at once, for a phone that hears about every film. */
export function digest(films: string[]) {
  const named = films.slice(0, 2).map((f) => `«${f}»`).join(' و');
  const rest = films.length - 2;
  return {
    title: `🎬 مواعيد جديدة لـ${filmCount(films.length)}`,
    body: rest > 0 ? `${named} و${filmCount(rest)} كمان` : named,
  };
}

export function filmCount(n: number) {
  if (n === 1) return 'فيلم';
  if (n === 2) return 'فيلمين';
  if (n <= 10) return `${n} أفلام`;
  return `${n} فيلم`;
}

export function showCount(n: number) {
  if (n === 1) return 'حفلة جديدة';
  if (n === 2) return 'حفلتين جداد';
  if (n <= 10) return `${n} حفلات جديدة`;
  return `${n} حفلة جديدة`;
}

/** One line of notification_log (20261106120000_notification_log.sql). */
export type LogRow = {
  movie_id?: string | null;
  film?: string | null;
  device?: string | null;
  outcome: 'sent' | 'failed' | 'stale_device' | 'daily_limit' | 'not_new' | 'other_cinemas' | 'nobody_follows' | 'no_firebase';
  kind?: Alert['kind'] | 'digest' | null;
  cinemas?: string[] | null;
  new_shows?: number | null;
  title?: string | null;
  body?: string | null;
  error?: string | null;
  /** For a sent notification: start of the window its new shows were first seen in (the app's inbox). */
  since?: string | null;
};

const LOG_DAYS = 14;

/**
 * Collects what happened to every film this run. Rows are written as each
 * phone is done (flush), not only at the end, so a run that is cancelled or
 * killed partway still leaves a record of the notifications it already sent.
 * Best effort: a missing table or a failed write is reported and ignored, so
 * the log can never stop a notification.
 */
export class NotificationLog {
  readonly rows: (LogRow & { run_at: string })[] = [];
  constructor(private db: SupabaseClient | null, private runAt: string) {}

  add(row: LogRow) {
    this.rows.push({ ...row, run_at: this.runAt });
  }

  /** False once the database turns out not to have the `since` column yet. */
  private withSince = true;

  /** Writes the rows collected so far. */
  async flush() {
    let rows = this.rows.splice(0);
    if (!this.db || !rows.length) return;
    try {
      if (!this.withSince) rows = rows.map(({ since: _, ...r }) => r);
      for (let i = 0; i < rows.length; i += 500) {
        let { error } = await this.db.from('notification_log').insert(rows.slice(i, i + 500));
        // Before 20261110090000_users_and_inbox.sql is run: log without it.
        if (error && this.withSince && /since/.test(error.message)) {
          this.withSince = false;
          rows = rows.map(({ since: _, ...r }) => r);
          ({ error } = await this.db.from('notification_log').insert(rows.slice(i, i + 500)));
        }
        if (error) throw new Error(error.message);
      }
    } catch (e) {
      console.log(`  ! notification log not saved (${rows.length} rows): ${errorMessage(e)}`);
    }
  }

  /** The last flush, then drops rows older than LOG_DAYS. */
  async close() {
    await this.flush();
    if (!this.db) return;
    try {
      const cutoff = new Date(Date.parse(this.runAt) - LOG_DAYS * 86_400_000).toISOString();
      const { error } = await this.db.from('notification_log').delete().lt('run_at', cutoff);
      if (error) throw new Error(error.message);
    } catch (e) {
      console.log(`  ! old notification log rows not pruned: ${errorMessage(e)}`);
    }
  }
}

/** FCM refuses a message over 4 KB; the title, body and keys need some of it. */
const DATA_BUDGET = 3000;

/**
 * What a notification is about, for the app's "what's new" screen: each film,
 * what kind of news it is and the cinemas it happened at, plus the window the
 * new showtimes were first seen in (`first_seen_at`, since ≤ t < until). The
 * app fetches those showtimes itself, so the message stays small. When the
 * cinema lists would make it too big they're left out and the app falls back
 * to the phone's own cinemas.
 */
export function alertData(
  films: { movieId: string; alert: Alert }[],
  since: string,
  until: string,
): Record<string, string> {
  const withCinemas = films.map((f) => ({ m: f.movieId, k: f.alert.kind, c: f.alert.cinemas }));
  let list = JSON.stringify(withCinemas);
  if (list.length > DATA_BUDGET) list = JSON.stringify(withCinemas.map(({ m, k }) => ({ m, k })));
  if (list.length > DATA_BUDGET) {
    // A digest of very many films: the first ones, as many as fit.
    const kept: { m: string; k: string }[] = [];
    for (const { m, k } of withCinemas) {
      if (JSON.stringify([...kept, { m, k }]).length > DATA_BUDGET) break;
      kept.push({ m, k });
    }
    list = JSON.stringify(kept);
  }
  return { type: 'alert', films: list, since, until };
}

/** The tail of a token: enough to tell phones apart in the log, no more. */
const deviceTag = (token: string) => token.slice(-8);

/** scrape_runs rows with this source mark how far alerts have been checked. */
const ALERTS = 'alerts';

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
  // Per-device progress prevents replay. Do not silently drop an unsent,
  // still-upcoming show just because an outage lasted more than 24 hours.
  return new Date(last).toISOString();
}

export async function notifyDrops(db: SupabaseClient, runStartedAt: string) {
  const fcm = Fcm.fromEnv();
  const now = new Date().toISOString();
  const log = new NotificationLog(db, now);
  if (!fcm) {
    log.add({ outcome: 'no_firebase' });
    await log.close();
    return console.log('  notifications: FIREBASE_SERVICE_ACCOUNT not set, skipped (the next run that can send picks these up)');
  }

  try {
    await announce(db, fcm, await lastCheck(db, runStartedAt), now, log);
  } finally {
    await log.close();
  }
  const { error } = await db.from('scrape_runs').insert({ source: ALERTS, started_at: now, ok: true });
  if (error) throw new Error(`save alerts checkpoint: ${error.message}`);
}

async function announce(db: SupabaseClient, fcm: Fcm, since: string, now: string, log: NotificationLog) {
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
    db.from('devices').select('token,following,cinemas').overlaps('following', [...movieIds, EVERY_FILM]).order('token'),
  );
  const [{ data: movies }, { data: cinemas }] = await Promise.all([
    db.from('movies').select('id,tmdb_id,title,title_ar,original_title').in('id', movieIds),
    db.from('cinemas').select('id,chain,name,name_ar').in('id', unique(fresh.map((r) => r.cinema_id))),
  ]);
  const title = new Map((movies ?? []).map((m) => [m.id, displayTitle(m)]));
  const label = new Map((cinemas ?? []).map((c) => [c.id, cinemaLabel(c)]));
  const name = (id: string) => title.get(id) ?? id;

  const filmsOf = (d: Device) => (d.following.includes(EVERY_FILM) ? movieIds : d.following);
  const followed = movieIds.filter((id) => devices.some((d) => filmsOf(d).includes(id)));
  for (const id of movieIds.filter((m) => !followed.includes(m))) {
    const rows = fresh.filter((r) => r.movie_id === id);
    log.add({
      movie_id: id, film: name(id), outcome: 'nobody_follows',
      new_shows: rows.length, cinemas: unique(rows.map((r) => r.cinema_id)),
    });
  }
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

  const today = cairoToday();
  const counts = { opened: 0, days: 0, shows: 0 };
  let failed = false;
  for (const device of devices) {
    // The previous phone's rows (sends, daily limits…) go out before this
    // one's notifications do.
    await log.flush();
    // A phone that picked its cinemas hears only about those, unless it
    // asked for every cinema.
    const everywhere = !device.cinemas.length || device.following.includes(ALL_CINEMAS);
    const mine = (rows: Seen[]) =>
      everywhere ? rows : rows.filter((r) => device.cinemas.includes(r.cinema_id));

    const tag = deviceTag(device.token);
    const due: { movieId: string; alert: Alert }[] = [];
    for (const movieId of filmsOf(device)) {
      const anywhere = freshBy.get(movieId) ?? [];
      const through = checked.get(`${device.token}|${movieId}`);
      const rows = mine(anywhere);
      const handled = (row: Seen) => !!through && !!row.first_seen_at && Date.parse(row.first_seen_at) < Date.parse(through);
      const alert = alertFor(rows.filter((r) => !handled(r)), [
        ...mine(beforeBy.get(movieId) ?? []), ...rows.filter(handled),
      ]);
      if (!alert) {
        // Only films the phone follows by name: logging every film for every
        // "all films" phone would bury the answers in noise.
        if (anywhere.length && device.following.includes(movieId)) {
          log.add({
            movie_id: movieId, film: name(movieId), device: tag,
            outcome: rows.length ? 'not_new' : 'other_cinemas',
            new_shows: anywhere.length, cinemas: unique(anywhere.map((r) => r.cinema_id)),
          });
        }
        continue;
      }

      // The primary key makes this the once-a-day check: a second insert fails.
      const { error: seen } = await db
        .from('notifications_sent')
        .insert({ token: device.token, movie_id: movieId, sent_on: today });
      if (seen) {
        if (seen.code === '23505') {
          // Consume updates intentionally suppressed by today's rate limit,
          // so another phone's retry cannot resurrect them tomorrow.
          await advance(device.token, movieId);
          log.add({
            movie_id: movieId, film: name(movieId), device: tag, outcome: 'daily_limit',
            kind: alert.kind, cinemas: alert.cinemas, new_shows: rows.length,
          });
          continue;
        }
        throw new Error(`reserve notification: ${seen.message}`);
      }
      due.push({ movieId, alert });
    }
    if (!due.length) continue;

    // Films the phone follows always get their own notification; only the
    // rest (every-film mode) are bundled, and only past DIGEST_AFTER of them.
    const own = due.filter((d) => device.following.includes(d.movieId));
    const others = due.filter((d) => !device.following.includes(d.movieId));
    const bundle = others.length > DIGEST_AFTER;
    const sends: { push: { title: string; body: string; data: Record<string, string> }; films: typeof due; digest: boolean }[] = [
      ...[...own, ...(bundle ? [] : others)].map((d) => ({
        push: {
          ...message(d.alert, name(d.movieId), (id) => label.get(id) ?? id),
          // movieId: what app versions before the "what's new" screen open.
          data: { movieId: d.movieId, ...alertData([d], since, now) },
        },
        films: [d],
        digest: false,
      })),
      ...(bundle
        ? [{ push: { ...digest(others.map((d) => name(d.movieId))), data: alertData(others, since, now) }, films: others, digest: true }]
        : []),
    ];
    const logSend = (one: (typeof sends)[number], outcome: LogRow['outcome'], error?: string) => {
      for (const d of one.films) {
        log.add({
          movie_id: d.movieId, film: name(d.movieId), device: tag, outcome,
          kind: one.digest ? 'digest' : d.alert.kind, cinemas: d.alert.cinemas,
          new_shows: d.alert.kind === 'shows' ? d.alert.count : null,
          title: one.push.title, body: one.push.body, error: error ?? null,
          since: outcome === 'sent' ? since : null,
        });
      }
    };
    const done = new Set<string>();
    let stale = false;
    for (const one of sends) {
      try {
        await fcm.send({ token: device.token, ...one.push });
        for (const d of one.films) done.add(d.movieId);
        logSend(one, 'sent');
      } catch (e) {
        if (e instanceof StaleToken) {
          stale = true;
          for (const rest of sends.filter((x) => !x.films.some((d) => done.has(d.movieId)))) logSend(rest, 'stale_device');
          break;
        }
        failed = true;
        logSend(one, 'failed', errorMessage(e));
        console.log(`  ! notification to …${device.token.slice(-6)}: ${errorMessage(e)}`);
      }
    }
    // Recorded as soon as they're out: a run cancelled from here on still
    // leaves these rows behind.
    await log.flush();
    // A failed send must not consume today's notification or advance the
    // checkpoint: the next run needs to pick this alert up again.
    for (const d of due) {
      if (done.has(d.movieId)) {
        await advance(device.token, d.movieId);
        counts[d.alert.kind]++;
        continue;
      }
      const { error: release } = await db.from('notifications_sent').delete()
        .eq('token', device.token).eq('movie_id', d.movieId).eq('sent_on', today);
      if (release) throw new Error(`release failed notification: ${release.message}`);
    }
    if (stale) {
      const { error } = await db.from('devices').delete().eq('token', device.token);
      if (error) throw new Error(`remove stale device: ${error.message}`);
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
