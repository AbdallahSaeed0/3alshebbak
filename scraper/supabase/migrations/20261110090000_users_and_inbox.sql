-- عالشباك — counting users, and each phone's notification inbox.
-- Run once in the Supabase SQL editor. Safe to run again.

-- 1. Users. Every install makes up a random id (no account, nothing personal)
--    and reports it once a day when the app opens: enough to count daily and
--    total users, nothing to tell who anyone is.
create table if not exists shebbak.app_opens (
  install_id  text not null,
  day         date not null,                 -- Cairo date
  platform    text not null,                 -- 'android' | 'ios'
  version     text,
  first_at    timestamptz not null default now(),
  primary key (install_id, day)
);
create index if not exists app_opens_day on shebbak.app_opens (day);

alter table shebbak.app_opens enable row level security;
revoke all on shebbak.app_opens from public, anon, authenticated;
grant all on shebbak.app_opens to service_role;

create or replace function shebbak.record_open(p_install text, p_platform text, p_version text)
returns void
language sql
security definer
set search_path = shebbak
as $$
  insert into app_opens (install_id, day, platform, version)
  select p_install, (now() at time zone 'Africa/Cairo')::date,
         case when p_platform in ('android', 'ios') then p_platform else 'other' end,
         left(p_version, 20)
  where length(p_install) between 16 and 64
  on conflict (install_id, day) do nothing;
$$;

-- Daily users, and how many installs have ever opened the app.
create or replace view shebbak.daily_users as
  select day,
         count(*)                                     as users,
         count(*) filter (where platform = 'android') as android,
         count(*) filter (where platform = 'ios')     as ios
  from shebbak.app_opens group by day order by day desc;
revoke all on shebbak.daily_users from public, anon, authenticated;
grant select on shebbak.daily_users to service_role;

-- 2. Notification inbox. The log already keeps what each phone was sent for
--    two weeks; `since` adds the window the new showtimes were first seen in,
--    so the app can show them again (alertData in scraper/src/notify.ts).
alter table shebbak.notification_log add column if not exists since timestamptz;

-- A phone's own sent notifications, newest first. The log keeps only the
-- token's last 8 characters, so the full token must also be a registered
-- device: nobody can read another phone's notifications by guessing a tail.
create or replace function shebbak.my_notifications(p_token text)
returns table (run_at timestamptz, since timestamptz, movie_id text, kind text,
               cinemas text[], title text, body text)
language sql
stable
security definer
set search_path = shebbak
as $$
  select l.run_at, l.since, l.movie_id, l.kind, l.cinemas, l.title, l.body
  from notification_log l
  where l.device = right(p_token, 8)
    and l.outcome = 'sent'
    and exists (select 1 from devices d where d.token = p_token)
  order by l.run_at desc, l.id
  limit 300;
$$;

revoke all on function shebbak.record_open, shebbak.my_notifications from public;
grant execute on function shebbak.record_open, shebbak.my_notifications to anon, authenticated;
