// Relays for the cinema sites that turn GitHub's runners away (Premiere,
// Renaissance): a Cloudflare Worker first (cloudflare/cinema-fetch; its
// traffic isn't on Supabase's free-plan quota), then Supabase's cinema-fetch
// Edge Function when the Worker can't be reached or the site turns it away.

export interface CinemaResponse { status: number; headers: Record<string, string>; body: string }

const workerConfigured = () => !!process.env.CINEMA_FETCH_WORKER_URL && !!process.env.CINEMA_FETCH_WORKER_TOKEN;
const supabaseConfigured = () => !!process.env.CINEMA_FETCH_URL && !!process.env.SUPABASE_SERVICE_ROLE_KEY;

export function cinemaRelayConfigured(): boolean {
  return workerConfigured() || supabaseConfigured();
}

/** Hosts a site turned the Worker away from this run: they go straight to Supabase's relay. */
const workerRefused = new Set<string>();

/** The site answering this way to the Worker means it's turning it away. */
const refusal = (status: number) => status === 403 || status === 429 || status === 503;

async function relay(endpoint: string, auth: string, extra: Record<string, string>, payload: object): Promise<CinemaResponse> {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json', ...extra },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(35_000),
  });
  if (!response.ok) throw new Error(`Cinema relay HTTP ${response.status}`);
  return (await response.json()) as CinemaResponse;
}

/**
 * [trim]: the relay sends back the page cut down to its markup (trim-html.ts);
 * a relay deployed before that option ignores it and sends the whole page.
 */
export async function cinemaFetch(
  url: string,
  method = 'GET',
  headers: Record<string, string> = {},
  body?: string,
  trim = false,
): Promise<CinemaResponse> {
  if (!cinemaRelayConfigured()) throw new Error('Cinema relay is not configured');
  const payload = { url, method, headers, body, ...(trim ? { trim } : {}) };
  const host = new URL(url).hostname;
  if (workerConfigured() && !workerRefused.has(host)) {
    try {
      const answer = await relay(process.env.CINEMA_FETCH_WORKER_URL!, process.env.CINEMA_FETCH_WORKER_TOKEN!, {}, payload);
      if (!refusal(answer.status) || !supabaseConfigured()) return answer;
      workerRefused.add(host);
      console.log(`  cinema relay: ${host} turned the Cloudflare Worker away (HTTP ${answer.status}); using Supabase's`);
    } catch (e) {
      if (!supabaseConfigured()) throw e;
    }
  }
  return relay(process.env.CINEMA_FETCH_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
    // Keep the egress region stable regardless of the caller's location.
    'x-region': process.env.CINEMA_FETCH_REGION || 'eu-west-1',
  }, payload);
}
