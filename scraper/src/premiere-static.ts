// Premiere's site scripts (/_next/static/…), kept between runs: about half of
// what a Premiere scrape pulls through the cinema relay, the same every run.
// Their names carry a hash of their contents, so a changed script comes under
// a new name and is fetched fresh; nothing with show data (pages, the API) is
// kept. CI keeps the file in the Actions cache, like the TMDB lookups.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { CinemaResponse } from './cinema-fetch.js';

const CACHE_FILE = 'data/premiere-static.json';
/** Scripts no run has asked for in this long are dropped. */
const KEEP_DAYS = 7;

interface Entry extends CinemaResponse { used: number }

let entries: Record<string, Entry> | undefined;
let changed = false;

/** A script whose name carries its contents' hash: safe to keep. */
export function keepable(method: string, url: string): boolean {
  const u = new URL(url);
  return method === 'GET' && !u.search && u.hostname === 'www.premiere-cinemas.com' &&
    (/^\/_next\/static\/.*[-.][0-9a-f]{8,}\.js$/.test(u.pathname) ||
      /^\/_next\/static\/[\w-]{10,}\/_(build|ssg)Manifest\.js$/.test(u.pathname));
}

async function load(): Promise<Record<string, Entry>> {
  if (!entries) {
    try {
      entries = JSON.parse(await readFile(CACHE_FILE, 'utf8')) as Record<string, Entry>;
    } catch {
      entries = {};
    }
  }
  return entries;
}

export async function cachedScript(url: string): Promise<CinemaResponse | undefined> {
  const entry = (await load())[url];
  if (!entry) return undefined;
  entry.used = Date.now();
  changed = true;
  return { status: entry.status, headers: entry.headers, body: entry.body };
}

export async function keepScript(url: string, response: CinemaResponse): Promise<void> {
  if (response.status !== 200 || !/javascript/i.test(response.headers['content-type'] ?? '')) return;
  const { 'set-cookie': _, ...headers } = response.headers;
  (await load())[url] = { status: 200, headers, body: response.body, used: Date.now() };
  changed = true;
}

export async function saveScripts(): Promise<void> {
  if (!entries || !changed) return;
  const cutoff = Date.now() - KEEP_DAYS * 86_400_000;
  for (const [url, entry] of Object.entries(entries)) if (entry.used < cutoff) delete entries[url];
  await mkdir(dirname(CACHE_FILE), { recursive: true });
  await writeFile(CACHE_FILE, JSON.stringify(entries));
  changed = false;
}
