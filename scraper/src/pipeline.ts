// `npm run pipeline [-- renaissance scene …]` — scrape the named sources (all by
// default), then sync them. Sync runs even when a source failed: it uploads
// whichever of them is fresh in out/ and skips the rest.
// (A plain `a; b` npm script doesn't work on Windows, where npm uses cmd.exe.)

import { spawnSync } from 'node:child_process';

function step(script: string, args: string[] = []): number {
  const result = spawnSync(process.execPath, ['--import', 'tsx', script, ...args], { stdio: 'inherit' });
  return result.status ?? 1;
}

const scraped = step('src/run.ts', process.argv.slice(2));
const synced = step('src/sync.ts', process.argv.slice(2));
process.exitCode = scraped || synced;
