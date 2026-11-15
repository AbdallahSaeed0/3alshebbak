// Cinemas shown from their chain's own site only: Premiere's branches
// (premiere.ts) and VOX's cinemas (vox.ts). Their times are the ones the chain
// sells, with a link to book each. elCinema lists these cinemas too (its
// theater pages and its booking page), but with shows the chain doesn't have:
// times moved, days missing, days not yet on sale filled in from the week
// before. So at a cinema the chain's own site lists, elCinema's shows are left
// out of a run and deleted from the database. If the chain's site fails for a
// while, the cinema keeps the shows its last good run stored.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ScrapeResult, SourceId } from './model.js';

/** Sources read from the chain's own site, which elCinema's copy steps back for. */
const OWN_SITES: SourceId[] = ['premiere', 'vox'];
/** elCinema's sources. */
const CEDING: SourceId[] = ['elcinema', 'elcinema-presales'];

/** The elCinema cinemas a chain's own site lists, from this run or (for a source not in it) the database. */
export async function ownSiteCinemas(results: ScrapeResult[], db: SupabaseClient | null): Promise<Set<string>> {
  const cinemas = new Set<string>();
  const ran = results.map((r) => r.source);
  for (const r of results) {
    if (!OWN_SITES.includes(r.source)) continue;
    for (const s of r.showtimes) if (s.cinemaId.startsWith('elcinema:')) cinemas.add(s.cinemaId);
  }
  const missing = OWN_SITES.filter((s) => !ran.includes(s));
  // Only needed to keep elCinema's copy out of a run that has it.
  if (!db || !missing.length || !results.some((r) => CEDING.includes(r.source))) return cinemas;
  for (const source of missing) {
    const { data, error } = await db
      .from('showtimes')
      .select('cinema_id')
      .eq('source', source)
      .like('cinema_id', 'elcinema:%')
      .gt('starts_at', new Date().toISOString())
      .limit(1000);
    if (error) throw new Error(`own-site cinemas (${source}): ${error.message}`);
    for (const r of data) cinemas.add(r.cinema_id as string);
  }
  return cinemas;
}

/** Removes elCinema's shows at [cinemas]; returns how many. */
export function leaveToOwnSites(results: ScrapeResult[], cinemas: Set<string>): number {
  let removed = 0;
  for (const r of results) {
    if (!CEDING.includes(r.source) || !cinemas.size) continue;
    const before = r.showtimes.length;
    r.showtimes = r.showtimes.filter((s) => !cinemas.has(s.cinemaId));
    removed += before - r.showtimes.length;
  }
  return removed;
}

/**
 * Deletes elCinema's stored upcoming shows at [cinemas], for the sources this
 * run didn't have (a run with them leaves them out and deletes its own unseen
 * rows anyway); returns how many went.
 */
export async function removeCededFromDb(db: SupabaseClient, cinemas: Set<string>, ranSources: string[]): Promise<number> {
  const sources = CEDING.filter((s) => !ranSources.includes(s));
  if (!sources.length || !cinemas.size) return 0;
  const { error, count } = await db
    .from('showtimes')
    .delete({ count: 'exact' })
    .in('source', sources)
    .in('cinema_id', [...cinemas])
    .gt('starts_at', new Date().toISOString());
  if (error) throw new Error(`own-site cleanup: ${error.message}`);
  return count ?? 0;
}
