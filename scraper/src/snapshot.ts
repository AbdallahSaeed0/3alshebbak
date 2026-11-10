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
  const body = JSON.stringify({ v: 1, generatedAt: new Date().toISOString(), cinemas, movies, showtimes });

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
