// The whole catalog the app shows, as one file on Supabase Storage's CDN:
// the app opens with one download instead of a page of cinemas, one of
// movies and a dozen pages of showtimes from the database. Rewritten after a
// sync that changed something, and at least hourly; the app falls back to the
// database when it's missing or old
// (app/lib/data/supabase_repository.dart). Same rows and columns as the
// app's own queries, so one parser reads both.

import type { SupabaseClient } from '@supabase/supabase-js';

export const BUCKET = 'shebbak-public';
export const SNAPSHOT = 'catalog.json';

const CINEMA_COLUMNS = 'id,chain,name,name_ar,city,area,url,attribution,lat,lng,location_approximate';
const SHOWTIME_COLUMNS = 'cinema_id,movie_id,business_date,starts_at,format,booking_url,price_egp';
/** The hall a show is in, where known (migration 20261114120000_showtime_hall.sql). */
const SHOWTIME_HALL = ',hall';
const PAGE = 1000;
const NEWS_DAYS = 14;
const NEWS_MAX = 3000;

/**
 * What the pipeline announced lately: each film's news per alerts run, with
 * every cinema it was announced for — no phones, just film, kind, cinemas and
 * time. The app's notifications page shows the ones that match its own films
 * and cinemas, so it isn't empty after a reinstall or with alerts off.
 */
export type News = {
  at: string;
  since: string | null;
  m: string;
  k: string;
  c: string[];
  /** The new shows themselves, still to come: cinema → start times (epoch minutes). */
  s?: Record<string, number[]>;
};

export type SeenShow = { movie_id: string; cinema_id: string; starts_at: string; first_seen_at: string };

/**
 * Attaches each news item's actual new shows: the ones first seen in its run's
 * window, at its cinemas — read from showtimes_seen, the table the alerts were
 * worked out from (showtimes' own first_seen_at moves when a show is listed
 * again under a new id). Runs logged before the window was kept get the hour
 * before them.
 */
export function attachShows(news: News[], seen: SeenShow[]): News[] {
  const byMovie = new Map<string, SeenShow[]>();
  for (const r of seen) byMovie.set(r.movie_id, [...(byMovie.get(r.movie_id) ?? []), r]);
  return news.map((n) => {
    const until = Date.parse(n.at);
    const from = n.since ? Date.parse(n.since) : until - 3600_000;
    const shows: Record<string, Set<number>> = {};
    for (const r of byMovie.get(n.m) ?? []) {
      const first = Date.parse(r.first_seen_at);
      if (first < from || first >= until || !n.c.includes(r.cinema_id)) continue;
      (shows[r.cinema_id] ??= new Set()).add(Math.round(Date.parse(r.starts_at) / 60_000));
    }
    const s = Object.fromEntries(Object.entries(shows).map(([c, t]) => [c, [...t].sort((a, b) => a - b)]));
    return Object.keys(s).length ? { ...n, s } : n;
  });
}

export function collectNews(rows: { run_at: string; since: string | null; movie_id: string | null; kind: string | null; cinemas: string[] | null }[]): News[] {
  const byKey = new Map<string, News>();
  for (const r of rows) {
    if (!r.movie_id) continue;
    // A digest bundles films that each got new showtimes.
    const k = r.kind && r.kind !== 'digest' ? r.kind : 'shows';
    const key = `${r.run_at}|${r.movie_id}|${k}`;
    const n = byKey.get(key) ?? { at: r.run_at, since: r.since, m: r.movie_id, k, c: [] };
    for (const c of r.cinemas ?? []) if (!n.c.includes(c)) n.c.push(c);
    if (r.since && (!n.since || r.since < n.since)) n.since = r.since;
    byKey.set(key, n);
  }
  return [...byKey.values()].sort((a, b) => b.at.localeCompare(a.at)).slice(0, NEWS_MAX);
}

async function all(db: SupabaseClient, query: () => any): Promise<unknown[]> {
  const rows: unknown[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await query().range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    rows.push(...data);
    if (data.length < PAGE) return rows;
  }
}

/** Upcoming shows, with their hall where the database has the column yet. */
async function showtimeRows(db: SupabaseClient, since: string): Promise<unknown[]> {
  const query = (columns: string) => () =>
    db.from('showtimes').select(columns).gte('starts_at', since).order('starts_at').order('id');
  try {
    const rows = (await all(db, query(SHOWTIME_COLUMNS + SHOWTIME_HALL))) as Record<string, unknown>[];
    // Most shows have no hall: leave the key out rather than ship
    // `"hall":null` thousands of times in a file every app open downloads.
    for (const r of rows) if (r.hall == null) delete r.hall;
    return rows;
  } catch (e) {
    if (!/hall/.test(e instanceof Error ? e.message : String(e))) throw e;
    return all(db, query(SHOWTIME_COLUMNS));
  }
}

/** Builds the snapshot from the database and uploads it. Returns its size in bytes. */
export async function publishSnapshot(db: SupabaseClient): Promise<number> {
  // Shows that ended an hour ago are of no use, as in the app's own query.
  const since = new Date(Date.now() - 3600_000).toISOString();
  const [cinemas, movies, showtimes] = await Promise.all([
    all(db, () => db.from('cinemas').select(CINEMA_COLUMNS).order('id')),
    all(db, () => db.from('movies').select('*').order('id')),
    showtimeRows(db, since),
  ]);
  // Best effort: a snapshot without news still opens the app.
  let news: News[] = [];
  try {
    const from = new Date(Date.now() - NEWS_DAYS * 86_400_000).toISOString();
    news = collectNews(
      (await all(db, () =>
        db.from('notification_log').select('*').eq('outcome', 'sent').gte('run_at', from).order('id'),
      )) as Parameters<typeof collectNews>[0],
    );
    const seen = (await all(db, () =>
      db.from('showtimes_seen').select('movie_id,cinema_id,starts_at,first_seen_at')
        .gte('first_seen_at', from).gt('starts_at', new Date().toISOString()).order('id'),
    )) as SeenShow[];
    news = attachShows(news, seen);
  } catch (e) {
    console.log(`  ! snapshot without news: ${e instanceof Error ? e.message : e}`);
  }
  // Films already showing: a show of theirs started in the last day
  // (showtimes_seen keeps shows a day past their start). "Coming soon" leaves
  // these out, even late at night when their next show is tomorrow.
  let started: string[] = [];
  try {
    const rows = (await all(db, () =>
      db.from('showtimes_seen').select('movie_id').lt('starts_at', new Date().toISOString()).order('id'),
    )) as { movie_id: string }[];
    started = [...new Set(rows.map((r) => r.movie_id))].sort();
  } catch (e) {
    console.log(`  ! snapshot without started films: ${e instanceof Error ? e.message : e}`);
  }
  const body = JSON.stringify({ v: 1, generatedAt: new Date().toISOString(), cinemas, movies, showtimes, news, started });

  const storage = db.storage;
  const { error: missing } = await storage.getBucket(BUCKET);
  if (missing) {
    const { error } = await storage.createBucket(BUCKET, { public: true });
    if (error && !/already exists/i.test(error.message)) throw new Error(`create bucket: ${error.message}`);
  }
  const { error } = await storage.from(BUCKET).upload(SNAPSHOT, new Blob([body], { type: 'application/json' }), {
    upsert: true,
    contentType: 'application/json',
    // The pipeline runs every ten minutes; phones may reuse a copy a minute old.
    cacheControl: '60',
  });
  if (error) throw new Error(`upload snapshot: ${error.message}`);
  return body.length;
}

/** scrape_runs' source for each published snapshot: when it was last built. */
const SNAPSHOT_MARK = 'snapshot';

/**
 * Rebuilt at least this often even with nothing new, so shows that have
 * started drop out of the file and it never looks stale to the app (which
 * trusts it for 90 minutes).
 */
const SNAPSHOT_MAX_AGE_MS = 50 * 60_000;

/**
 * Why the catalog file needs rebuilding now, or null when it's up to date.
 * Rebuilding reads every upcoming show from the database, so it isn't done
 * after the many runs that change nothing (a VOX check every ten minutes).
 * Each check here is a count, with no rows downloaded.
 */
export async function snapshotDue(db: SupabaseClient, removedShows: number): Promise<string | null> {
  if (removedShows > 0) return `${removedShows} shows removed`;
  const { data: last, error } = await db
    .from('scrape_runs')
    .select('started_at')
    .eq('source', SNAPSHOT_MARK)
    .order('started_at', { ascending: false })
    .limit(1);
  if (error) throw new Error(`last snapshot: ${error.message}`);
  const at = last?.[0]?.started_at as string | undefined;
  if (!at) return 'no snapshot yet';
  if (Date.now() - Date.parse(at) > SNAPSHOT_MAX_AGE_MS) return 'hourly refresh';
  const since = new Date(at).toISOString();
  const count = async (table: string, filter: (q: any) => any) => {
    const { count: n, error: e } = await filter(db.from(table).select('id', { count: 'exact', head: true }));
    if (e) throw new Error(`${table} since last snapshot: ${e.message}`);
    return n ?? 0;
  };
  // A new row: a new show, or one that came back under a new id.
  const added = await count('showtimes', (q) => q.gte('first_seen_at', since));
  if (added) return `${added} new shows`;
  const sent = await count('notification_log', (q) => q.eq('outcome', 'sent').gte('run_at', since));
  if (sent) return 'new notifications';
  return null;
}

/** Notes a published snapshot, built from what the database held at [startedAt]. */
export async function recordSnapshot(db: SupabaseClient, startedAt: string, bytes: number) {
  const { error } = await db.from('scrape_runs').insert({
    source: SNAPSHOT_MARK,
    started_at: startedAt,
    ok: true,
    warnings: [`${bytes} bytes`],
  });
  if (error) throw new Error(`record snapshot: ${error.message}`);
}
