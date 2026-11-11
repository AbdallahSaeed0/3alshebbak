// The whole catalog the app shows, as one file on Supabase Storage's CDN:
// the app opens with one download instead of a page of cinemas, one of
// movies and a dozen pages of showtimes from the database. Written after
// every sync; the app falls back to the database when it's missing or old
// (app/lib/data/supabase_repository.dart). Same rows and columns as the
// app's own queries, so one parser reads both.

import type { SupabaseClient } from '@supabase/supabase-js';

export const BUCKET = 'shebbak-public';
export const SNAPSHOT = 'catalog.json';

const CINEMA_COLUMNS = 'id,chain,name,name_ar,city,area,url,attribution,lat,lng,location_approximate';
const SHOWTIME_COLUMNS = 'cinema_id,movie_id,business_date,starts_at,format,booking_url,price_egp';
const PAGE = 1000;
const NEWS_DAYS = 14;
const NEWS_MAX = 3000;

/**
 * What the pipeline announced lately: each film's news per alerts run, with
 * every cinema it was announced for — no phones, just film, kind, cinemas and
 * time. The app's notifications page shows the ones that match its own films
 * and cinemas, so it isn't empty after a reinstall or with alerts off.
 */
export type News = { at: string; since: string | null; m: string; k: string; c: string[] };

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

/** Builds the snapshot from the database and uploads it. Returns its size in bytes. */
export async function publishSnapshot(db: SupabaseClient): Promise<number> {
  // Shows that ended an hour ago are of no use, as in the app's own query.
  const since = new Date(Date.now() - 3600_000).toISOString();
  const [cinemas, movies, showtimes] = await Promise.all([
    all(db, () => db.from('cinemas').select(CINEMA_COLUMNS).order('id')),
    all(db, () => db.from('movies').select('*').order('id')),
    all(db, () => db.from('showtimes').select(SHOWTIME_COLUMNS).gte('starts_at', since).order('starts_at').order('id')),
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
