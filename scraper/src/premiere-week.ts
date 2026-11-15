// Premiere's branches are shown from Premiere's own site (premiere.ts): its
// times are the ones it sells, each with its hall and a link to book it there.
// elCinema lists Premiere Plaza, Point90 and Cima Arkan too, sometimes at
// times Premiere doesn't have; so on a day Premiere lists a film at a branch,
// elCinema's shows of that film there that day are left out. Film by film, not
// whole days: Premiere puts a day up in parts (one film's presale weeks before
// the rest), and a film whose page failed keeps elCinema's shows.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ScrapeResult } from './model.js';

const filmKey = (cinemaId: string, movieId: string, date: string) => `${cinemaId}|${movieId}|${date}`;

/** The film-days ("cinema|movie|date") Premiere's site lists at elCinema's cinemas, from this run or the database. */
export async function premiereDays(
  results: ScrapeResult[],
  filmToMovie: Record<string, string>,
  db: SupabaseClient | null,
): Promise<Set<string>> {
  const premiere = results.find((r) => r.source === 'premiere');
  if (premiere) {
    return new Set(
      premiere.showtimes
        .filter((s) => s.cinemaId.startsWith('elcinema:'))
        .map((s) => filmKey(s.cinemaId, filmToMovie[s.filmId], s.businessDate)),
    );
  }
  // Premiere not in this run: what its last run left in the database.
  if (!db || !results.some((r) => r.source === 'elcinema')) return new Set();
  const days = new Set<string>();
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db
      .from('showtimes')
      .select('cinema_id,movie_id,business_date')
      .eq('source', 'premiere')
      .like('cinema_id', 'elcinema:%')
      .gt('starts_at', new Date().toISOString())
      .range(from, from + 999);
    if (error) throw new Error(`premiere days: ${error.message}`);
    for (const r of data) days.add(filmKey(r.cinema_id, r.movie_id, r.business_date));
    if (data.length < 1000) break;
  }
  return days;
}

/** Removes elCinema's shows that [days] covers; returns how many. */
export function leaveToPremiere(results: ScrapeResult[], filmToMovie: Record<string, string>, days: Set<string>): number {
  let removed = 0;
  for (const r of results) {
    if (r.source !== 'elcinema' || !days.size) continue;
    const before = r.showtimes.length;
    r.showtimes = r.showtimes.filter(
      (s) => !days.has(filmKey(s.cinemaId, filmToMovie[s.filmId], s.businessDate)),
    );
    removed += before - r.showtimes.length;
  }
  return removed;
}
