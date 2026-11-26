// `npm run scrape [-- vox premiere renaissance scene]` — runs the named sources
// (all by default), writes out/<source>.json and prints a summary per source.

import { mkdir, writeFile } from 'node:fs/promises';
import { closeBrowser } from './browser.js';
import { errorMessage } from './http.js';
import { placeCinemas } from './locations.js';
import { recordFailure, supabaseFromEnv } from './supabase.js';
import type { Source, SourceId } from './model.js';
import { elcinema } from './sources/elcinema.js';
import { elcinemaPresales } from './sources/elcinema-presales.js';
import { premiere } from './sources/premiere.js';
import { renaissance } from './sources/renaissance.js';
import { scene } from './sources/scene.js';
import { vox } from './sources/vox.js';

// VOX's and Premiere's cinemas come from their own sites (own-site.ts drops
// elCinema's copy of them).
const SOURCES: Record<string, Source> = { renaissance, scene, premiere, elcinema, vox, 'elcinema-presales': elcinemaPresales };

async function main() {
  try {
    process.loadEnvFile();
  } catch {
    // No .env: SCRAPER_CONTACT may come from the real environment.
  }
  const wanted = process.argv.slice(2);
  const ids = (wanted.length ? wanted : Object.keys(SOURCES)) as SourceId[];
  const unknown = ids.filter((id) => !SOURCES[id]);
  if (unknown.length) throw new Error(`Unknown source(s): ${unknown.join(', ')}. Known: ${Object.keys(SOURCES).join(', ')}`);

  await mkdir('out', { recursive: true });
  const failures: { id: string; at: string; error: string }[] = [];
  for (const id of ids) {
    const started = Date.now();
    try {
      const result = placeCinemas(await SOURCES[id].scrape());
      await writeFile(`out/${id}.json`, JSON.stringify(result, null, 2));
      const days = new Set(result.showtimes.map((s) => s.businessDate));
      console.log(
        `✓ ${id}: ${result.cinemas.length} cinemas, ${result.films.length} films, ` +
          `${result.showtimes.length} showtimes over ${days.size} days ` +
          `(${((Date.now() - started) / 1000).toFixed(1)}s)` +
          (result.warnings.length ? `, ${result.warnings.length} warnings` : ''),
      );
      for (const w of result.warnings.slice(0, 5)) console.log(`    ! ${w}`);
    } catch (e) {
      failures.push({ id, at: new Date(started).toISOString(), error: errorMessage(e) });
      console.error(`✗ ${id}: ${errorMessage(e)}`);
    }
  }
  // Kept in scrape_runs (ok = false) so a site that failed can be looked up
  // later; the watchdog still goes by each source's last good run.
  const db = supabaseFromEnv();
  for (const f of failures) {
    try {
      if (db) await recordFailure(db, f.id, f.at, f.error.slice(0, 1000));
    } catch {
      // Recording is best effort.
    }
  }
  // One site having a bad run (a timeout, a refused request) isn't a failed
  // pipeline: the others are synced as usual and the next run tries it again.
  // Only every source failing fails the run (and sends GitHub's email).
  if (failures.length && failures.length === ids.length) process.exitCode = 1;
}

main()
  .catch((e) => {
    console.error(errorMessage(e));
    process.exitCode = 1;
  })
  .finally(closeBrowser);
