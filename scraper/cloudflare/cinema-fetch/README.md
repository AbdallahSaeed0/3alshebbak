# cinema-fetch on Cloudflare Workers

The relay the scraper tries first for Premiere and Renaissance (their sites
turn GitHub's runners away); Supabase's `cinema-fetch` Edge Function is the
fallback. Moved here because every byte a Supabase function sends back is
egress on its free plan, and this relay was about half of it.

- Deploy: `npx wrangler deploy` in this folder (logged in with `npx wrangler login`).
- Key: `npx wrangler secret put RELAY_TOKEN`; the same value goes in the
  repository secret `CINEMA_FETCH_WORKER_TOKEN` (and `scraper/.env` locally).
- Free plan: 100,000 requests a day; the scraper makes about 7,000.
