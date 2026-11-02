export interface CinemaResponse { status: number; headers: Record<string, string>; body: string }

export function cinemaRelayConfigured(): boolean {
  return !!process.env.CINEMA_FETCH_URL && !!process.env.SUPABASE_SERVICE_ROLE_KEY;
}

export async function cinemaFetch(url: string, method = 'GET', headers: Record<string, string> = {}, body?: string): Promise<CinemaResponse> {
  if (!cinemaRelayConfigured()) throw new Error('Cinema relay is not configured');
  const response = await fetch(process.env.CINEMA_FETCH_URL!, {
    method: 'POST',
    headers: { Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ url, method, headers, body }),
    signal: AbortSignal.timeout(35_000),
  });
  if (!response.ok) throw new Error(`Cinema relay HTTP ${response.status}`);
  return await response.json() as CinemaResponse;
}
