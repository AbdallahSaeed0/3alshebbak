// Writes one sync into Supabase: cinemas, movies, each chain's film listings,
// then showtimes. Showtimes keep their `first_seen_at` across runs (it's only
// set on insert), which is what "tickets just opened" is built on. A source's
// future showtimes that this run no longer saw are deleted — cancelled shows.

import { createHash } from 'node:crypto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { ScrapeResult } from './model.js';
import type { Catalog } from './tmdb.js';
import { errorMessage } from './http.js';
import { presaleFrom } from './time.js';

/** Sources that add only presale days to cinemas elCinema lists (vox.ts, premiere.ts). */
/**
 * Sources that add only days past elCinema's week at elCinema's cinemas. VOX
 * and the booking page also cover this week; reconcileSources settles those.
 */
const PRESALE_SOURCES = ['premiere'];

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

/**
 * Saves a run's films and shows. Returns how many upcoming shows it removed
 * (gone from their source, or settled between sources), so the caller knows
 * whether the app's catalog file needs rebuilding.
 */
export async function upload(db: SupabaseClient, results: ScrapeResult[], catalog: Catalog, runStartedAt: string): Promise<number> {
  let removed = 0;
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

  const movieRows = catalog.movies.map((m) => ({
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
      credits: m.credits,
      updated_at: now,
    }));
  try {
    await upsert(db, 'movies', movieRows);
  } catch (e) {
    // A database without the credits column yet (migration
    // 20261112090000_movie_credits.sql): save the films without their cast.
    if (!/credits/.test(errorMessage(e))) throw e;
    await upsert(db, 'movies', movieRows.map(({ credits: _, ...row }) => row));
  }

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
    const showtimeRows = r.showtimes.map((s) => ({
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
      hall: s.hall ?? null,
      last_seen_at: runStartedAt,
    }));
    try {
      await upsert(db, 'showtimes', showtimeRows);
    } catch (e) {
      // A database without the hall column yet (migration
      // 20261114120000_showtime_hall.sql): save the shows without it.
      if (!/hall/.test(errorMessage(e))) throw e;
      await upsert(db, 'showtimes', showtimeRows.map(({ hall: _, ...row }) => row));
    }

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

    const { error, count } = await db
      .from('showtimes')
      .delete({ count: 'exact' })
      .eq('source', r.source)
      .gt('starts_at', now)
      .lt('last_seen_at', runStartedAt);
    if (error) throw new Error(`showtimes cleanup (${r.source}): ${error.message}`);
    removed += count ?? 0;

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
  const { error: overlap, count: overlapping } = await db
    .from('showtimes')
    .delete({ count: 'exact' })
    .in('source', PRESALE_SOURCES)
    .like('cinema_id', 'elcinema:%')
    .lt('business_date', presaleFrom());
  if (overlap) throw new Error(`presale cleanup: ${overlap.message}`);
  removed += overlapping ?? 0;
  removed += await reconcileSources(db);

  // Over shows are no use to the alerts.
  const dayAgo = new Date(Date.now() - 24 * 3600_000).toISOString();
  const { error } = await db.from('showtimes_seen').delete().lt('starts_at', dayAgo);
  if (error) throw new Error(`showtimes_seen cleanup: ${error.message}`);
  return removed;
}

export type Row = { id: string; source: string; movie_id: string; cinema_id: string; business_date: string; starts_at: string };

/**
 * One copy of each show at elCinema's cinemas, from the source nearest the
 * cinema. elCinema's theater pages can lag a week's changeover (last week's
 * film still listed, the new one missing), so:
 *   - for a film the booking page sells at a cinema, the booking page's days
 *     are the film's days there: elCinema's rows for it on a day the booking
 *     page covers for that cinema go. A film that isn't sold online at all
 *     (Moscow Cairo, say) keeps elCinema's listing;
 *   - a film's day on VOX's own page is VOX's: elCinema's rows for that film,
 *     cinema and day go;
 *   - a show both Premiere's site and the booking page list keeps Premiere's
 *     copy (it runs in the cloud; the booking page only from a local machine).
 */
export async function reconcileSources(db: SupabaseClient): Promise<number> {
  // In the database (20261114150000_reconcile_in_database.sql): nothing to
  // download. Until that's run, the same rules here, on downloaded rows.
  const { data: removed, error: rpcError } = await db.rpc('reconcile_sources');
  if (!rpcError) return removed as number;
  // PGRST202: no such function yet. Anything else is a real failure.
  if (rpcError.code !== 'PGRST202') {
    throw new Error(`reconcile sources: ${rpcError.message}`);
  }
  const rows: Row[] = [];
  // Two weeks back too: a film whose last booked day has passed (The Odyssey
  // replaced at IMAX) must not get elCinema's stale later days back.
  const since = new Date(Date.now() - 14 * 24 * 3600_000).toISOString();
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db
      .from('showtimes')
      .select('id,source,movie_id,cinema_id,business_date,starts_at')
      .in('source', ['elcinema', 'vox', 'premiere', 'elcinema-presales'])
      .like('cinema_id', 'elcinema:%')
      .gt('starts_at', since)
      .order('id')
      .range(from, from + 999);
    if (error) throw new Error(`reconcile sources: ${error.message}`);
    rows.push(...(data as Row[]));
    if (data.length < 1000) break;
  }
  const drop = reconcileDrops(rows, Date.now());
  for (let i = 0; i < drop.length; i += 200) {
    const { error } = await db.from('showtimes').delete().in('id', drop.slice(i, i + 200));
    if (error) throw new Error(`reconcile sources: ${error.message}`);
  }
  return drop.length;
}

/** The ids reconcileSources removes from [rows] (the last two weeks' shows at elCinema's cinemas). */
export function reconcileDrops(rows: Row[], now: number): string[] {
  const of = (source: string, upcoming = true) =>
    rows.filter((r) => r.source === source && (!upcoming || Date.parse(r.starts_at) > now));
  const show = (r: Row) => `${r.movie_id}|${r.cinema_id}|${Date.parse(r.starts_at)}`;
  const bookingDays = new Set(of('elcinema-presales').map((r) => `${r.cinema_id}|${r.business_date}`));
  const bookingFilms = new Set(of('elcinema-presales', false).map((r) => `${r.movie_id}|${r.cinema_id}`));
  const voxDays = new Set(of('vox').map((r) => `${r.movie_id}|${r.cinema_id}|${r.business_date}`));
  const premiere = new Set(of('premiere').map(show));

  const drop = [
    ...of('elcinema').filter(
      (r) =>
        (bookingFilms.has(`${r.movie_id}|${r.cinema_id}`) && bookingDays.has(`${r.cinema_id}|${r.business_date}`)) ||
        voxDays.has(`${r.movie_id}|${r.cinema_id}|${r.business_date}`),
    ),
    ...of('elcinema-presales').filter((r) => premiere.has(show(r))),
  ].map((r) => r.id);
  return [...new Set(drop)];
}

/**
 * Movies a re-match replaced (a title that's now joined to its TMDB entry)
 * stay behind otherwise. In the database, one call
 * (20261114170000_remove_orphan_movies.sql): only movies no show or source
 * film points at go. Until that's run, one delete per id, and the foreign
 * keys refuse the ones still in use.
 */
async function removeOrphanMovies(db: SupabaseClient, current: Set<string>) {
  const { error: rpcError } = await db.rpc('remove_orphan_movies', { keep: [...current] });
  if (!rpcError) return;
  // PGRST202: no such function yet. Anything else is a real failure.
  if (rpcError.code !== 'PGRST202') throw new Error(`remove orphan movies: ${rpcError.message}`);
  const { data, error } = await db.from('movies').select('id');
  if (error) throw new Error(`movies: ${error.message}`);
  for (const { id } of data as { id: string }[]) {
    if (!current.has(id)) await db.from('movies').delete().eq('id', id);
  }
}

export async function recordFailure(db: SupabaseClient, source: string, startedAt: string, error: string) {
  await db.from('scrape_runs').insert({ source, started_at: startedAt, ok: false, error });
}
