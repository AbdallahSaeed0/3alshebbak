export interface CinemaResponse { status: number; headers: Record<string, string>; body: string }

export function cinemaRelayConfigured(): boolean {
  return !!process.env.CINEMA_FETCH_URL && !!process.env.SUPABASE_SERVICE_ROLE_KEY;
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
  const response = await fetch(process.env.CINEMA_FETCH_URL!, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      // Keep the egress region stable regardless of the caller's location.
      'x-region': process.env.CINEMA_FETCH_REGION || 'eu-west-1',
    },
    body: JSON.stringify({ url, method, headers, body, ...(trim ? { trim } : {}) }),
    signal: AbortSignal.timeout(35_000),
  });
  if (!response.ok) throw new Error(`Cinema relay HTTP ${response.status}`);
  return await response.json() as CinemaResponse;
}
