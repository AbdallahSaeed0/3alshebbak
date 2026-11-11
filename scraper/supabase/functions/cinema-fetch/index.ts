// Private transport for public cinema pages. No arbitrary destinations or redirects.
const hosts = new Set(['rnscinemas.com', 'www.rnscinemas.com', 'www.premiere-cinemas.com', 'premiere-cinemas.com', 'mifcentral-api.premiere-cinemas.com']);
const allowed = (url: URL) => url.protocol === 'https:' && !url.port && !url.username && !url.password && hosts.has(url.hostname);

Deno.serve(async (request: Request) => {
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!serviceKey || request.headers.get('Authorization') !== `Bearer ${serviceKey}`) {
    return new Response('Unauthorized', { status: 401 });
  }
  try {
    const input = await request.json();
    let url = new URL(input.url);
    if (!allowed(url) || !['GET', 'POST'].includes(input.method ?? 'GET')) return new Response('Destination denied', { status: 400 });
    const headers = new Headers();
    for (const name of ['accept', 'accept-language', 'content-type', 'referer', 'origin', 'user-agent', 'cookie', 'authorization', 'x-requested-with']) {
      if (typeof input.headers?.[name] === 'string') headers.set(name, input.headers[name]);
    }
    if (!['rnscinemas.com', 'www.rnscinemas.com'].includes(url.hostname)) {
      headers.set('User-Agent', '3alShebbakBot/0.1 (public cinema showtimes; https://github.com/AbdallahSaeed0/3alshebbak)');
    }
    const method = input.method ?? 'GET';
    if (typeof input.body === 'string' && input.body.length > 256_000) return new Response('Request too large', { status: 413 });
    let response: Response | undefined;
    for (let redirects = 0; redirects < 4; redirects++) {
      response = await fetch(url, { method, headers, body: method === 'POST' ? input.body : undefined, redirect: 'manual', signal: AbortSignal.timeout(25_000) });
      if (![301, 302, 303, 307, 308].includes(response.status)) break;
      const next = new URL(response.headers.get('location') ?? '', url);
      if (!allowed(next) || method !== 'GET') return new Response('Redirect denied', { status: 400 });
      url = next;
    }
    if (!response) throw new Error('No response');
    const body = await response.text();
    if (body.length > 4_000_000) return new Response('Response too large', { status: 413 });
    const resultHeaders: Record<string, string> = {};
    for (const name of ['content-type', 'set-cookie', 'access-control-allow-origin', 'access-control-allow-credentials']) {
      const value = response.headers.get(name);
      if (value) resultHeaders[name] = value;
    }
    return Response.json({ status: response.status, headers: resultHeaders, body });
  } catch {
    return new Response('Cinema fetch failed', { status: 502 });
  }
});
