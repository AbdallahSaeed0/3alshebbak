# عالشباك — scraper

Reads Egyptian cinema showtimes from each chain's own site into one normalized
shape (`src/model.ts`): cinemas, films, showtimes with a real start time
(Cairo offset), format, and a deep link to book on the chain's site.

```bash
npm install
npx playwright install chromium   # Premiere needs a browser
npm run scrape                     # all sources → out/<source>.json
npm run scrape -- renaissance scene
```

Set `SCRAPER_CONTACT` (an email or URL) so site owners can reach us; it goes
in the User-Agent of every plain HTTP request. Copy `.env.example` to `.env`.

## Schedule (GitHub Actions)

Supabase Cron on the existing project dispatches `.github/workflows/pipeline.yml`
every 10 minutes (UTC minutes 7, 17, 27, 37, 47, 57). VOX presales run every
time, Renaissance, Scene and Premiere twice an hour, and elCinema once an hour. It
needs the repository secrets `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`TMDB_API_KEY` and `SCRAPER_CONTACT`. Run it by hand from the Actions tab
(optionally naming sources). GitHub's native cron is disabled; Supabase is
the scheduler, while GitHub Actions remains the execution host. Runner queues,
site failures and source coverage can still delay detecting a booking opening.

The `shebbak-showtimes-every-10-minutes` job calls the private
`shebbak_private.dispatch_pipeline()` function. GitHub authorization is kept in
Supabase Vault as `shebbak_github_dispatch_token`; it must be rotated if revoked.
Use a dedicated fine-grained token scoped to this repository with Actions
read/write, independent of `gh auth login`. Save it in the ignored local file
`.env.scheduler-token`, then run `npx tsx src/install-scheduler-token.ts`. The
installer verifies dispatch permission before replacing the Vault secret and
records its expiry for the watchdog. Until this is done the earlier CLI OAuth
credential remains active. Never put credentials into cron commands, committed
SQL or logs.

To inspect scheduling and delivery to GitHub (HTTP 204 means accepted):

```sql
select j.jobname, r.status, r.start_time, r.return_message
from cron.job_run_details r join cron.job j using (jobid)
where j.jobname = 'shebbak-showtimes-every-10-minutes'
order by r.start_time desc limit 10;

select requested_at, sources, status_code
from shebbak_private.pipeline_dispatches
order by requested_at desc limit 10;
```

Dispatch history is retained for 30 days. The HTTP extension sends requests
synchronously with a 15-second timeout: authorization headers are never stored
in a queue. A rejection or network error marks the cron run as failed; the next
scheduled run tries again. These are private operational objects, separate from
the application's exposed `shebbak` schema.

## Independent monitoring and cinema transport

`shebbak-pipeline-watchdog` runs from Supabase Cron every ten minutes, separately
from GitHub. The private `pipeline-watchdog` Edge Function checks dispatch
freshness, successful source uploads, alerts processing and token expiry. It
notifies only the verified administrator device when the set of problems
changes, and stays quiet while the state is unchanged. It retries a failed
notification; it does not broadcast operational alerts to app users. Device
token rotation requires updating the administrator fingerprint in its context
function. Failed cron executions remain visible in `cron.job_run_details`.

The pipeline provisions Firebase and Supabase credentials into Vault through
the service-role-only `configure_pipeline_watchdog` RPC. The monitoring path
does not use the GitHub dispatch credential and can report a revoked GitHub
credential after dispatches become stale. The expiry warning starts seven days
before the configured token expiry.

In CI, `CINEMA_FETCH_URL` points to the private `cinema-fetch` Edge Function.
Renaissance HTML and Premiere's anonymous browser requests are fetched from
Supabase rather than GitHub IPs, pinned to `eu-west-1` so the caller's location
does not change the transport region. The function requires service authorization,
restricts destination hosts and redirects, and limits timeouts and payload size.
Premiere continues to use its ordinary browser pickers; no API decryption or
login is performed. Local runs without the relay read the sites directly.

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

### Additional elCinema booking presales

`npm run scrape -- elcinema-presales` reads the public booking inventory and
Premiere date/time dropdowns, including Americana Plaza and Cima Arkan presales
that Premiere's own pages do not list. It reads selection data only, never
seats, checkout or orders; requests run sequentially with a 1.5-second pause.
Then `npm run sync -- elcinema-presales` uploads them through the usual alert
pipeline. Only dates outside the ordinary theater-page week are added.

This source currently requires an elCinema-permitted connection (verified
locally in Egypt). GitHub and the current Supabase region receive the geographic
unavailability page, so this source is intentionally **not scheduled** yet.
Do not treat the extra booking inventory as automatically monitored until an
eligible cloud runner is configured. Failed scrapes leave the existing data
intact instead of uploading an empty result.

After each upload, `src/notify.ts` finds films that opened a new day of
showtimes at a cinema and pushes a notification (Firebase Cloud Messaging) to
phones that follow the film and picked that cinema, at most once per film per
phone per day. Phones register through the `register_device` function
(`supabase/migrations/002_map_and_push.sql`). Needs the repository secret
`FIREBASE_SERVICE_ACCOUNT` (the service account key's JSON); without it the
step is skipped.

`notification_progress` remembers each phone/film's processed boundary. If one
phone fails, successful phones retain their progress even when the shared retry
crosses Cairo midnight. Updates intentionally suppressed by the daily rate limit
are also consumed, so they cannot reappear the next day. As with most external
push systems, an ambiguous network response or a crash between Firebase accepting
a push and recording progress can still produce an at-least-once retry.

## Sources (tier 1: chains' own sites)

| Source | How | Notes |
|---|---|---|
| `renaissance` | plain HTML, one page per branch per day | every time link carries its own data-* attributes |
| `scene` | plain HTML per movie + `?business_day=…&ajax=1` per day | one site per venue (cfc, district5) |
| `premiere` | headless Chromium, clicks through the pickers via the private Supabase transport | includes presales beyond elCinema's week and all dates for unlisted branches such as Nile Cinema |

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
