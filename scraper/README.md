# عالشباك — scraper

Reads Egyptian cinema showtimes from each chain's own site into one normalized
shape (`src/model.ts`): cinemas, films, showtimes with a real start time
(Cairo offset), format, and a deep link to book on the chain's site.

```bash
npm install
npx playwright install chromium   # only VOX and Premiere need a browser
npm run scrape                     # all sources → out/<source>.json
npm run scrape -- renaissance scene
```

Set `SCRAPER_CONTACT` (an email or URL) so site owners can reach us; it goes
in the User-Agent of every plain HTTP request. Copy `.env.example` to `.env`.

## Schedule (GitHub Actions)

Supabase Cron on the existing project dispatches `.github/workflows/pipeline.yml`
every 10 minutes (UTC minutes 7, 17, 27, 37, 47, 57). VOX presales run every
time, Renaissance and Scene twice an hour, and elCinema once an hour. It
needs the repository secrets `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`TMDB_API_KEY` and `SCRAPER_CONTACT`. Run it by hand from the Actions tab
(optionally naming sources). GitHub's native cron is disabled; Supabase is
the scheduler, while GitHub Actions remains the execution host. Runner queues,
site failures and source coverage can still delay detecting a booking opening.

The `shebbak-showtimes-every-10-minutes` job calls the private
`shebbak_private.dispatch_pipeline()` function. GitHub authorization is kept in
Supabase Vault as `shebbak_github_dispatch_token`; it must be rotated if revoked.
The current credential is the existing GitHub CLI OAuth credential, not a
repository-scoped token. A dedicated repository-scoped Actions-write token can
replace it using `vault.update_secret` without changing the scheduler. Never
put credentials into cron commands, committed SQL or logs.

To inspect scheduling and delivery to GitHub (HTTP 204 means accepted):

```sql
select j.jobname, r.status, r.start_time, r.return_message
from cron.job_run_details r join cron.job j using (jobid)
where j.jobname = 'shebbak-showtimes-every-10-minutes'
order by r.start_time desc limit 10;

select d.requested_at, d.sources, r.status_code, r.error_msg
from shebbak_private.pipeline_dispatches d
left join net._http_response r on r.id = d.request_id
order by d.requested_at desc limit 10;
```

Dispatch history is retained for 30 days; pg_net responses normally last six
hours. Read access to pg_net's queue and responses is restricted to prevent
client roles from reading authorization headers. These are private operational
objects, separate from the application's exposed `shebbak` schema.

## Sync: TMDB + Supabase

```bash
npm run sync       # out/*.json → TMDB matching → Supabase
npm run pipeline   # scrape, then sync
```

- **TMDB** (`src/tmdb.ts`): every chain's listing of a film is joined into one
  movie by TMDB id. Lookups are cached in `data/tmdb-cache.json`. When a match
  is wrong or missing, pin it in `data/tmdb-overrides.json`:
  `{ "normalized title": 12345 }` (or `null` for "not on TMDB"). Run a sync and
  check the "not on TMDB" line it prints. The app must show TMDB's attribution.
- **Supabase**: run `supabase/migrations/001_init.sql` once in the project's
  SQL editor. Without `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`, sync is a
  dry run that writes `out/catalog.json`.
- Showtimes keep `first_seen_at` from the run that first saw them; the
  `tickets_opened` view is built on it. Future showtimes a source stops listing
  are deleted. Scrape output older than 2 hours is never synced.

## Map pins

Every cinema's coordinates are in `data/cinema-locations.json` (kept by hand;
`approximate: true` marks a mall's or town's pin rather than the cinema's).
A new cinema without one gets a warning in the run; add it with
`npx tsx scripts/geocode-cinemas.ts` (OpenStreetMap lookup) and check the pin.

## "Tickets are out" notifications

After each upload, `src/notify.ts` finds films that opened a new day of
showtimes at a cinema and pushes a notification (Firebase Cloud Messaging) to
phones that follow the film and picked that cinema, at most once per film per
phone per day. Phones register through the `register_device` function
(`supabase/migrations/002_map_and_push.sql`). Needs the repository secret
`FIREBASE_SERVICE_ACCOUNT` (the service account key's JSON); without it the
step is skipped.

## Sources (tier 1: chains' own sites)

| Source | How | Notes |
|---|---|---|
| `renaissance` | plain HTML, one page per branch per day | every time link carries its own data-* attributes |
| `scene` | plain HTML per movie + `?business_day=…&ajax=1` per day | one site per venue (cfc, district5) |
| `premiere` | headless Chromium, clicks through the pickers | showtime API is encrypted; Cloudflare blocks GitHub's servers, so CI reads Premiere through elCinema (local use only) |

## Tier 2: elCinema.com

| Source | Covers | Notes |
|---|---|---|
| `elcinema` | VOX (Almaza, Mall of Egypt, Alexandria) | VOX's bot protection rejects automated browsers, so `sources/vox.ts` is not run |

elCinema's data is its product, so `elcinema` is polite on purpose: one request
at a time with a pause, an identifying User-Agent, an `attribution` on every
cinema that the app must show, and booking links to elCinema whenever it has
one. Add more theaters by id to `THEATERS` in `sources/elcinema.ts`.

A show after midnight belongs to the previous schedule day: `businessDate` is
the day the cinema lists it under, `start` is when it really starts.
