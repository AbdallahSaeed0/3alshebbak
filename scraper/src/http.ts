// Polite HTTP for the plain-HTML sources: identifies itself honestly, caps
// concurrency per run, and retries a page once or twice before giving up on it.
import { cinemaFetch, cinemaRelayConfigured } from './cinema-fetch.js';

// `||`: CI passes an unset secret as an empty string.
const CONTACT = process.env.SCRAPER_CONTACT || 'https://github.com/AbdallahSaeed0/3alshebbak';
export const USER_AGENT = `3alShebbakBot/0.1 (cinema showtimes app; ${CONTACT})`;

const TIMEOUT_MS = 20_000;

/**
 * Sites read directly that now and then turn a GitHub runner away (VOX: a 403
 * every few dozen runs). Once one does, the rest of the run reads it through
 * the cinema relay instead of failing.
 */
const RELAY_WHEN_REFUSED = new Set(['egy.voxcinemas.com']);
const relayedHosts = new Set<string>();

export async function fetchText(url: string, retries = 2): Promise<string> {
  let lastError: unknown;
  const host = new URL(url).hostname;
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const renaissance = ['rnscinemas.com', 'www.rnscinemas.com'].includes(host);
      if ((renaissance || relayedHosts.has(host)) && cinemaRelayConfigured()) {
        // Renaissance's listing pages are read by their markup; its booking page's
        // scripts hold the hall id. VOX's pages come whole: trimmed, they parse
        // to no shows.
        const trim = renaissance && !url.includes('/start_booking/');
        const headers: Record<string, string> = renaissance
          ? { 'accept-language': 'en' }
          : { 'user-agent': USER_AGENT, 'accept-language': 'en' };
        const response = await cinemaFetch(url, 'GET', headers, undefined, trim);
        if (response.status !== 200) throw new Error(`HTTP ${response.status}`);
        return response.body;
      }
      const res = await fetch(url, {
        headers: renaissance ? { 'Accept-Language': 'en' } : { 'User-Agent': USER_AGENT, 'Accept-Language': 'en' },
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if ((res.status === 403 || res.status === 429) && RELAY_WHEN_REFUSED.has(host) && cinemaRelayConfigured()) {
        console.log(`  ${host} turned the runner away (HTTP ${res.status}); reading it through the cinema relay`);
        relayedHosts.add(host);
        attempt--; // the relay gets its own tries
        continue;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.text();
    } catch (e) {
      lastError = e;
      if (attempt < retries) await sleep(1000 * (attempt + 1));
    }
  }
  throw new Error(`${url}: ${errorMessage(lastError)}`);
}

/** Runs `tasks` at most `limit` at a time; a failed task doesn't stop the others. */
export async function pool<T>(items: T[], limit: number, task: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  async function worker() {
    while (next < items.length) await task(items[next++]);
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
}

export function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

export function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** Collapses whitespace the way a visitor reads the text. */
export function clean(s: string | undefined | null): string {
  return (s ?? '').replace(/\s+/g, ' ').trim();
}

/** Some chains shout hall names ("GOLD", "PREMIUM"); elCinema writes them "Gold". Acronyms stay. */
export function hallName(name: string): string {
  const n = clean(name) || 'Standard';
  return /^[A-Z]{4,}$/.test(n) && n !== 'IMAX' ? n[0] + n.slice(1).toLowerCase() : n;
}

/** Last path segment of a URL, without an extension: ".../movie/clayface" → "clayface". */
export function slugOf(url: string): string {
  const path = new URL(url).pathname.replace(/\/+$/, '');
  return decodeURIComponent(path.slice(path.lastIndexOf('/') + 1)).replace(/\.html?$/, '');
}
