// Premiere's branches are shown from Premiere's own site only (premiere.ts):
// its times are the ones it sells, each with its hall and a link to book it
// there. elCinema lists Premiere Plaza, Point90 and Cima Arkan too (its theater
// pages and its booking page), but with shows Premiere doesn't have: times it
// moved, and days Premiere hasn't put on sale filled in from the week before.
// So at a branch Premiere's site lists, elCinema's shows are left out of a run
// and deleted from the database. If Premiere's site fails for a while, the
// branch keeps the shows Premiere's last good run stored.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ScrapeResult } from './model.js';

/** elCinema's sources, whose copies of Premiere's branches step back. */
const CEDING: string[] = ['elcinema', 'elcinema-presales'];

/** The elCinema cinemas Premiere's site lists, from this run or the database. */
export async function premiereBranches(results: ScrapeResult[], db: SupabaseClient | null): Promise<Set<string>> {
  const premiere = results.find((r) => r.source === 'premiere');
  if (premiere) {
    return new Set(premiere.showtimes.map((s) => s.cinemaId).filter((id) => id.startsWith('elcinema:')));
  }
  // Premiere not in this run: the branches its last run left shows at.
  if (!db || !results.some((r) => CEDING.includes(r.source))) return new Set();
  const { data, error } = await db
    .from('showtimes')
    .select('cinema_id')
    .eq('source', 'premiere')
    .like('cinema_id', 'elcinema:%')
    .gt('starts_at', new Date().toISOString())
    .limit(1000);
  if (error) throw new Error(`premiere branches: ${error.message}`);
  return new Set(data.map((r) => r.cinema_id as string));
}

/** Removes elCinema's shows at [branches]; returns how many. */
export function leaveToPremiere(results: ScrapeResult[], branches: Set<string>): number {
  let removed = 0;
  for (const r of results) {
    if (!CEDING.includes(r.source) || !branches.size) continue;
    const before = r.showtimes.length;
    r.showtimes = r.showtimes.filter((s) => !branches.has(s.cinemaId));
    removed += before - r.showtimes.length;
  }
  return removed;
}

/**
 * Deletes elCinema's stored upcoming shows at [branches], for the sources
 * this run didn't have (a run with them leaves them out and deletes its own
 * unseen rows anyway); returns how many went.
 */
export async function removeCededFromDb(db: SupabaseClient, branches: Set<string>, ranSources: string[]): Promise<number> {
  const sources = CEDING.filter((s) => !ranSources.includes(s));
  if (!sources.length || !branches.size) return 0;
  const { error, count } = await db
    .from('showtimes')
    .delete({ count: 'exact' })
    .in('source', sources)
    .in('cinema_id', [...branches])
    .gt('starts_at', new Date().toISOString());
  if (error) throw new Error(`premiere branches cleanup: ${error.message}`);
  return count ?? 0;
}
