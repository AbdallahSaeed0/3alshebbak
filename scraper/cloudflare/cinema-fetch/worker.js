// The cinema-fetch relay on Cloudflare Workers: the same job as
// supabase/functions/cinema-fetch (Premiere's and Renaissance's sites turn
// GitHub's runners away), without its egress counting against Supabase's
// free plan. The scraper tries this first and falls back to Supabase's
// (src/cinema-fetch.ts). Deploy: `npx wrangler deploy` in this folder, with
// the secret RELAY_TOKEN set (`npx wrangler secret put RELAY_TOKEN`).

const HOSTS = new Set(['rnscinemas.com', 'www.rnscinemas.com', 'www.premiere-cinemas.com', 'premiere-cinemas.com', 'mifcentral-api.premiere-cinemas.com']);
const allowed = (url) => url.protocol === 'https:' && !url.port && !url.username && !url.password && HOSTS.has(url.hostname);

// A copy of scraper/src/trim-html.ts: a page cut down to its markup, sent back
// when the caller asks (`trim: true`).
const trimHtml = (html) => html
  .replace(/<head\b[\s\S]*?<\/head>/gi, '')
  .replace(/<(script|style|svg|noscript)\b[\s\S]*?<\/\1>/gi, '')
  .replace(/<!--[\s\S]*?-->/g, '')
  .replace(/\s+/g, ' ');

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return new Response('Not found', { status: 404 });
    if (!env.RELAY_TOKEN || request.headers.get('Authorization') !== `Bearer ${env.RELAY_TOKEN}`) {
      return new Response('Unauthorized', { status: 401 });
    }
    try {
      const input = await request.json();
      let url = new URL(input.url);
      const method = input.method ?? 'GET';
      if (!allowed(url) || !['GET', 'POST'].includes(method)) return new Response('Destination denied', { status: 400 });
      if (typeof input.body === 'string' && input.body.length > 256_000) return new Response('Request too large', { status: 413 });
      const headers = new Headers();
      for (const name of ['accept', 'accept-language', 'content-type', 'referer', 'origin', 'user-agent', 'cookie', 'authorization', 'x-requested-with']) {
        if (typeof input.headers?.[name] === 'string') headers.set(name, input.headers[name]);
      }
      if (!['rnscinemas.com', 'www.rnscinemas.com'].includes(url.hostname)) {
        headers.set('User-Agent', '3alShebbakBot/0.1 (public cinema showtimes; https://github.com/AbdallahSaeed0/3alshebbak)');
      }
      let response;
      for (let redirects = 0; redirects < 4; redirects++) {
        response = await fetch(url, { method, headers, body: method === 'POST' ? input.body : undefined, redirect: 'manual' });
        if (![301, 302, 303, 307, 308].includes(response.status)) break;
        const next = new URL(response.headers.get('location') ?? '', url);
        if (!allowed(next) || method !== 'GET') return new Response('Redirect denied', { status: 400 });
        url = next;
      }
      let body = await response.text();
      if (body.length > 4_000_000) return new Response('Response too large', { status: 413 });
      if (input.trim === true && /html/i.test(response.headers.get('content-type') ?? '')) body = trimHtml(body);
      const resultHeaders = {};
      for (const name of ['content-type', 'set-cookie', 'access-control-allow-origin', 'access-control-allow-credentials', 'server', 'via', 'x-cache', 'cf-mitigated', 'x-amz-cf-pop']) {
        const value = response.headers.get(name);
        if (value) resultHeaders[name] = value;
      }
      return Response.json({ status: response.status, headers: resultHeaders, body, colo: request.cf?.colo });
    } catch {
      return new Response('Cinema fetch failed', { status: 502 });
    }
  },
};
