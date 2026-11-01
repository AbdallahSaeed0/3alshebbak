-- عالشباك — map pins and push notifications. Run once in the SQL editor,
-- before the pipeline that writes `lat`/`lng` runs.

set search_path to shebbak;

-- Map pins (scraper/data/cinema-locations.json).
alter table cinemas
  add column lat                  double precision,
  add column lng                  double precision,
  add column location_approximate boolean not null default false;  -- the mall's or the town's pin

-- One row per phone that allows notifications. No accounts: the push token is
-- the identity, and the phone re-registers whenever its picks change.
create table devices (
  token       text primary key,           -- Firebase Cloud Messaging token
  platform    text not null,              -- 'android' | 'ios'
  following   text[] not null default '{}',  -- movie ids
  cinemas     text[] not null default '{}',  -- cinema ids ("my cinemas")
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- What was sent, so a film is announced to a phone at most once a day.
create table notifications_sent (
  token     text not null references devices(token) on delete cascade,
  movie_id  text not null,
  sent_on   date not null,
  primary key (token, movie_id, sent_on)
);

alter table devices            enable row level security;
alter table notifications_sent enable row level security;
-- No policies: nobody but the service role reads these tables. Phones write
-- only through the two functions below.
revoke all on devices, notifications_sent from anon, authenticated;
grant all on devices, notifications_sent to service_role;

create function register_device(p_token text, p_platform text, p_following text[], p_cinemas text[])
returns void
language sql
security definer
set search_path = shebbak
as $$
  insert into devices (token, platform, following, cinemas)
  values (p_token, p_platform, coalesce(p_following, '{}'), coalesce(p_cinemas, '{}'))
  on conflict (token) do update
    set platform = excluded.platform,
        following = excluded.following,
        cinemas = excluded.cinemas,
        updated_at = now();
$$;

create function unregister_device(p_token text)
returns void
language sql
security definer
set search_path = shebbak
as $$
  delete from devices where token = p_token;
$$;

revoke all on function register_device, unregister_device from public;
grant execute on function register_device, unregister_device to anon, authenticated;

reset search_path;
