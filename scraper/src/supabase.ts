// Writes one sync into Supabase: cinemas, movies, each chain's film listings,
// then showtimes. Showtimes keep their `first_seen_at` across runs (it's only
// set on insert), which is what "tickets just opened" is built on. A source's
// future showtimes that this run no longer saw are deleted — cancelled shows.

import { createHash } from 'node:crypto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { ScrapeResult } from './model.js';
import type { Catalog } from './tmdb.js';
import { presaleFrom } from './time.js';

/** Sources that add only presale days to cinemas elCinema lists (vox.ts, premiere.ts). */
const PRESALE_SOURCES = ['vox', 'premiere', 'elcinema-presales'];

const BATCH = 500;

export function supabaseFromEnv(): SupabaseClient | null {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  // All of عالشباك's tables live in their own schema (see 001_init.sql).
  return url && key
    ? (createClient(url, key, { auth: { persistSession: false }, db: { schema: 'shebbak' } }) as unknown as SupabaseClient)
    : null;
}

export function showtimeId(cinemaId: string, filmId: string, start: string, format: string): string {
  return createHash('sha1').update(`${cinemaId}|${filmId}|${start}|${format}`).digest('hex').slice(0, 24);
}

async function upsert(db: SupabaseClient, table: string, rows: object[], ignoreDuplicates = false) {
  for (let i = 0; i < rows.length; i += BATCH) {
    const { error } = await db.from(table).upsert(rows.slice(i, i + BATCH), { onConflict: 'id', ignoreDuplicates });
    if (error) throw new Error(`${table}: ${error.message}`);
  }
}

export async function upload(db: SupabaseClient, results: ScrapeResult[], catalog: Catalog, runStartedAt: string) {
  const now = new Date().toISOString();

  await upsert(
    db,
    'cinemas',
    results.flatMap((r) =>
      r.cinemas.map((c) => ({
        id: c.id,
        source: c.source,
        chain: c.chain,
        name: c.name,
        name_ar: c.nameAr ?? null,
        city: c.city ?? null,
        area: c.area ?? null,
        address: c.address ?? null,
        url: c.url ?? null,
        attribution: c.attribution ?? null,
        lat: c.lat ?? null,
        lng: c.lng ?? null,
        location_approximate: c.locationApproximate ?? false,
        updated_at: now,
      })),
    ),
  );

  await upsert(
    db,
    'movies',
    catalog.movies.map((m) => ({
      id: m.id,
      tmdb_id: m.tmdbId,
      title: m.title,
      title_ar: m.titleAr,
      original_title: m.originalTitle,
      overview: m.overview,
      poster_path: m.posterPath,
      backdrop_path: m.backdropPath,
      release_date: m.releaseDate,
      runtime: m.runtime,
      genres: m.genres,
      rating: m.rating,
      trailer_key: m.trailerKey,
      fallback_poster_url: m.fallbackPosterUrl,
      updated_at: now,
    })),
  );

  await upsert(
    db,
    'source_films',
    results.flatMap((r) =>
      r.films.map((f) => ({
        id: f.id,
        source: f.source,
        movie_id: catalog.filmToMovie[f.id],
        title: f.title,
        url: f.url ?? null,
        poster_url: f.posterUrl ?? null,
        updated_at: now,
      })),
    ),
  );

  for (const r of results) {
    // `first_seen_at` is deliberately not sent: the column default sets it on
    // insert and an upsert leaves it alone after that.
    await upsert(
      db,
      'showtimes',
      r.showtimes.map((s) => ({
        id: showtimeId(s.cinemaId, s.filmId, s.start, s.format),
        source: r.source,
        cinema_id: s.cinemaId,
        movie_id: catalog.filmToMovie[s.filmId],
        source_film_id: s.filmId,
        business_date: s.businessDate,
        starts_at: s.start,
        format: s.format,
        booking_url: s.bookingUrl ?? null,
        price_egp: s.priceEgp ?? null,
        last_seen_at: runStartedAt,
      })),
    );

    // The alerts' memory (004_showtimes_seen.sql): insert-only, so a show that
    // drops out for a run and comes back keeps its first sighting.
    await upsert(
      db,
      'showtimes_seen',
      r.showtimes.map((s) => ({
        id: showtimeId(s.cinemaId, s.filmId, s.start, s.format),
        movie_id: catalog.filmToMovie[s.filmId],
        cinema_id: s.cinemaId,
        business_date: s.businessDate,
        starts_at: s.start,
      })),
      true,
    );

    const { error } = await db
      .from('showtimes')
      .delete()
      .eq('source', r.source)
      .gt('starts_at', now)
      .lt('last_seen_at', runStartedAt);
    if (error) throw new Error(`showtimes cleanup (${r.source}): ${error.message}`);

    await db.from('scrape_runs').insert({
      source: r.source,
      started_at: r.fetchedAt,
      ok: true,
      showtimes: r.showtimes.length,
      warnings: r.warnings,
    });
  }

  await removeOrphanMovies(db, new Set(catalog.movies.map((m) => m.id)));

  // A presale day that's now inside elCinema's week is elCinema's to list; the
  // presale copy goes, whichever sources this run had.
  const { error: overlap } = await db
    .from('showtimes')
    .delete()
    .in('source', PRESALE_SOURCES)
    .like('cinema_id', 'elcinema:%')
    .lt('business_date', presaleFrom());
  if (overlap) throw new Error(`presale cleanup: ${overlap.message}`);
  await removeBookingDuplicates(db);

  // Over shows are no use to the alerts.
  const dayAgo = new Date(Date.now() - 24 * 3600_000).toISOString();
  const { error } = await db.from('showtimes_seen').delete().lt('starts_at', dayAgo);
  if (error) throw new Error(`showtimes_seen cleanup: ${error.message}`);
}

/**
 * elCinema's booking page and Premiere's own site list the same presale show
 * at a Premiere branch, one as "2D" and one as "Standard", so the app would
 * show it twice. Premiere's copy stays: it runs in the cloud, the booking
 * page only from a local machine.
 */
export async function removeBookingDuplicates(db: SupabaseClient) {
  const rows: { id: string; source: string; movie_id: string; cinema_id: string; starts_at: string }[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db
      .from('showtimes')
      .select('id,source,movie_id,cinema_id,starts_at')
      .in('source', ['premiere', 'elcinema-presales'])
      .like('cinema_id', 'elcinema:%')
      .order('id')
      .range(from, from + 999);
    if (error) throw new Error(`booking duplicates: ${error.message}`);
    rows.push(...data);
    if (data.length < 1000) break;
  }
  const show = (r: (typeof rows)[number]) => `${r.movie_id}|${r.cinema_id}|${Date.parse(r.starts_at)}`;
  const premiere = new Set(rows.filter((r) => r.source === 'premiere').map(show));
  const dupes = rows.filter((r) => r.source === 'elcinema-presales' && premiere.has(show(r))).map((r) => r.id);
  for (let i = 0; i < dupes.length; i += 200) {
    const { error } = await db.from('showtimes').delete().in('id', dupes.slice(i, i + 200));
    if (error) throw new Error(`booking duplicates: ${error.message}`);
  }
}

/**
 * Movies a re-match replaced (a title that's now joined to its TMDB entry)
 * stay behind otherwise. One delete per id: a movie that past showtimes or an
 * unsynced source still point at is refused by its foreign key and kept.
 */
async function removeOrphanMovies(db: SupabaseClient, current: Set<string>) {
  const { data, error } = await db.from('movies').select('id');
  if (error) throw new Error(`movies: ${error.message}`);
  for (const { id } of data as { id: string }[]) {
    if (!current.has(id)) await db.from('movies').delete().eq('id', id);
  }
}

export async function recordFailure(db: SupabaseClient, source: string, startedAt: string, error: string) {
  await db.from('scrape_runs').insert({ source, started_at: startedAt, ok: false, error });
}
