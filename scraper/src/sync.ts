// `npm run sync [-- vox premiere …]` — takes the latest out/<source>.json files
// (only the named sources', when given), matches their films to TMDB and writes
// everything to Supabase. Without Supabase credentials it stops after matching
// and writes out/catalog.json instead (a dry run).

import { readdir, readFile, writeFile } from 'node:fs/promises';
import { errorMessage } from './http.js';
import { placeCinemas } from './locations.js';
import type { ScrapeResult } from './model.js';
import { notifyDrops } from './notify.js';
import { supabaseFromEnv, upload } from './supabase.js';
import { buildCatalog } from './tmdb.js';

/** Older scrape output is skipped: re-uploading it would mark stale shows as seen now. */
const MAX_AGE_MS = 2 * 3600_000;

async function freshResults(only: string[]): Promise<ScrapeResult[]> {
  const files = (await readdir('out')).filter(
    (f) => f.endsWith('.json') && f !== 'catalog.json' && (!only.length || only.includes(f.slice(0, -'.json'.length))),
  );
  const results: ScrapeResult[] = [];
  for (const file of files) {
    const r = JSON.parse(await readFile(`out/${file}`, 'utf8')) as ScrapeResult;
    if (Date.now() - Date.parse(r.fetchedAt) > MAX_AGE_MS) console.log(`  skip ${file}: scraped ${r.fetchedAt}, too old`);
    // Placed again here so a pin fixed by hand reaches Supabase on the next sync.
    else results.push(placeCinemas(r));
  }
  return results;
}

async function main() {
  try {
    process.loadEnvFile();
  } catch {
    // No .env: credentials may come from the real environment.
  }
  const runStartedAt = new Date().toISOString();
  const results = await freshResults(process.argv.slice(2));
  if (!results.length) throw new Error('Nothing fresh in out/ — run `npm run scrape` first');

  const films = results.flatMap((r) => r.films);
  const catalog = await buildCatalog(films, (m) => console.log(`  ${m}`));
  const matched = catalog.movies.filter((m) => m.tmdbId != null).length;
  console.log(
    `✓ catalog: ${films.length} chain listings → ${catalog.movies.length} movies ` +
      `(${matched} on TMDB, ${catalog.movies.length - matched} local)`,
  );
  if (catalog.unmatched.length) console.log(`  not on TMDB: ${catalog.unmatched.join(' · ')}`);

  // Always kept: it's what to check matches against, and what the app bundles offline.
  await writeFile('out/catalog.json', JSON.stringify(catalog, null, 2));
  const db = supabaseFromEnv();
  if (!db) {
    console.log('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set: wrote out/catalog.json only (dry run)');
    return;
  }
  await upload(db, results, catalog, runStartedAt);
  const showtimes = results.reduce((n, r) => n + r.showtimes.length, 0);
  console.log(`✓ supabase: ${results.map((r) => r.source).join(', ')} — ${showtimes} showtimes`);
  await notifyDrops(db, runStartedAt);
}

main().catch((e) => {
  console.error(`✗ sync: ${errorMessage(e)}`);
  process.exitCode = 1;
});
