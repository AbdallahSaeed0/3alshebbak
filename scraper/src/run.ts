// `npm run scrape [-- vox premiere renaissance scene]` — runs the named sources
// (all by default), writes out/<source>.json and prints a summary per source.

import { mkdir, writeFile } from 'node:fs/promises';
import { closeBrowser } from './browser.js';
import { errorMessage } from './http.js';
import type { Source, SourceId } from './model.js';
import { elcinema } from './sources/elcinema.js';
import { premiere } from './sources/premiere.js';
import { renaissance } from './sources/renaissance.js';
import { scene } from './sources/scene.js';

// VOX comes through elcinema: its own site's bot protection rejects automated
// browsers. sources/vox.ts stays for if VOX ever gives us access.
const SOURCES: Record<string, Source> = { renaissance, scene, premiere, elcinema };

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
  let failed = false;
  for (const id of ids) {
    const started = Date.now();
    try {
      const result = await SOURCES[id].scrape();
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
      failed = true;
      console.error(`✗ ${id}: ${errorMessage(e)}`);
    }
  }
  if (failed) process.exitCode = 1;
}

main()
  .catch((e) => {
    console.error(errorMessage(e));
    process.exitCode = 1;
  })
  .finally(closeBrowser);
