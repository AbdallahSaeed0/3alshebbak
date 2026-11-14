-- The watchdog also speaks up when a source still runs but brings back far
-- fewer showtimes than usual: a site that changed its pages often "works"
-- and returns nothing. Problem `low:<source>` when the source's latest good
-- run has under 30% of its median over the week before (only for sources that
-- usually have at least 20 shows, so a small presale list that's legitimately
-- empty stays quiet). Clears itself on the next normal run.
-- Run once in the Supabase SQL editor. Safe to run again.

create or replace function shebbak.pipeline_watchdog_context()
returns jsonb language sql security definer set search_path='' as $$
with stale as (
  select expected.source from (values
    ('vox',35),('renaissance',95),('scene',95),('elcinema',150),('premiere',95),('alerts',35)
  ) as expected(source,minutes)
  where not exists(select 1 from shebbak.scrape_runs r where r.source=expected.source and r.ok=true
    and r.started_at > now()-make_interval(mins=>expected.minutes))
), latest as (
  select distinct on (r.source) r.source, r.showtimes, r.started_at
  from shebbak.scrape_runs r
  where r.ok and r.showtimes is not null
    and r.source in ('vox','renaissance','scene','elcinema','premiere')
    and r.started_at > now()-interval '1 day'
  order by r.source, r.started_at desc
), usual as (
  select l.source, l.showtimes,
    (select percentile_cont(0.5) within group (order by r.showtimes)
       from shebbak.scrape_runs r
      where r.source=l.source and r.ok and r.showtimes is not null
        and r.started_at between l.started_at-interval '7 days' and l.started_at-interval '1 minute') as median
  from latest l
), low as (
  select 'low:'||source as problem from usual where median >= 20 and showtimes < median*0.3
), issues as (
  select source as problem from stale
  union all select problem from low
  union all select 'dispatch' where not exists(
    select 1 from shebbak_private.pipeline_dispatches where status_code=204 and requested_at>now()-interval '25 minutes')
  union all select 'token_expiry' from shebbak_private.pipeline_watchdog_state
    where github_token_expires_at < now()+interval '7 days'
), problems as (
  select coalesce(jsonb_agg(problem order by problem),'[]'::jsonb) as items,
    coalesce(string_agg(problem,',' order by problem),'') as signature from issues
)
select jsonb_build_object(
  'problems',p.items,'signature',p.signature,'previous_signature',s.previous_signature,
  'firebase',(select decrypted_secret from vault.decrypted_secrets where name='shebbak_watchdog_firebase'),
  'device_token',(select token from shebbak.devices where
    encode(extensions.digest(token,'sha256'),'hex')='76627b80eb3c7abc8d99015d757fbc00c69946c20392668c5292cbba519b5249' limit 1)
) from problems p cross join shebbak_private.pipeline_watchdog_state s;
$$;
revoke all on function shebbak.pipeline_watchdog_context() from public,anon,authenticated;
grant execute on function shebbak.pipeline_watchdog_context() to service_role;

-- What the check sees, to read by hand: each source's latest count against its usual.
--   select * from shebbak.source_counts;
create or replace view shebbak.source_counts as
with latest as (
  select distinct on (source) source, showtimes, started_at
  from shebbak.scrape_runs where ok and showtimes is not null
  order by source, started_at desc
)
select l.source, l.started_at as last_run, l.showtimes as last_count,
  (select percentile_cont(0.5) within group (order by r.showtimes)
     from shebbak.scrape_runs r
    where r.source=l.source and r.ok and r.showtimes is not null
      and r.started_at > l.started_at-interval '7 days') as week_median
from latest l order by l.source;
revoke all on shebbak.source_counts from public, anon, authenticated;
grant select on shebbak.source_counts to service_role;
