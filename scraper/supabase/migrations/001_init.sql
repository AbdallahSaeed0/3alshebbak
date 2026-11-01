-- عالشباك — showtimes catalog. Written only by the scraper (service role);
-- read by the app with the anon key.
--
-- Lives in its own `shebbak` schema so it can share a Supabase project (for
-- now, Pitflix's) without touching that project's tables, and can be moved out
-- later in one piece. After running this, add `shebbak` to Settings → API →
-- Exposed schemas so the API can reach it.

create schema if not exists shebbak;
set search_path to shebbak;

create table cinemas (
  id           text primary key,          -- '<source>:<slug>', e.g. 'renaissance:downtown'
  source       text not null,
  chain        text not null,
  name         text not null,
  name_ar      text,
  city         text,
  area         text,
  address      text,
  url          text,
  attribution  text,                      -- shown in the app when set, e.g. 'elCinema.com'
  updated_at   timestamptz not null default now()
);

create table movies (
  id                  text primary key,   -- 'tmdb:<id>' or 'local:<normalized-title>'
  tmdb_id             integer unique,
  title               text not null,
  title_ar            text,
  original_title      text,
  overview            text,
  poster_path         text,               -- TMDB path; build URLs with image.tmdb.org
  backdrop_path       text,
  release_date        date,
  runtime             integer,
  genres              text[] not null default '{}',
  fallback_poster_url text,               -- a chain's own poster when TMDB has none
  updated_at          timestamptz not null default now()
);

-- Each chain's own listing of a film, joined to one movie.
create table source_films (
  id          text primary key,           -- '<source>:<slug>'
  source      text not null,
  movie_id    text not null references movies(id),
  title       text not null,
  url         text,
  poster_url  text,
  updated_at  timestamptz not null default now()
);

create table showtimes (
  id              text primary key,       -- hash of cinema, film, start and format
  source          text not null,
  cinema_id       text not null references cinemas(id),
  movie_id        text not null references movies(id),
  source_film_id  text not null references source_films(id),
  business_date   date not null,          -- the day the cinema lists it under
  starts_at       timestamptz not null,
  format          text not null,
  booking_url     text,
  price_egp       integer,
  first_seen_at   timestamptz not null default now(),  -- never overwritten: drives "tickets just opened"
  last_seen_at    timestamptz not null default now()
);

create index showtimes_upcoming on showtimes (starts_at);
create index showtimes_movie on showtimes (movie_id, starts_at);
create index showtimes_cinema on showtimes (cinema_id, starts_at);

create table scrape_runs (
  id           bigint generated always as identity primary key,
  source       text not null,
  started_at   timestamptz not null,
  finished_at  timestamptz not null default now(),
  ok           boolean not null,
  showtimes    integer,
  warnings     jsonb not null default '[]',
  error        text
);

-- A movie's tickets "just opened" at a cinema when its first showtime there
-- appeared recently. The very first sync makes everything look new, so the
-- app ignores this view until data is older than the window.
create view tickets_opened with (security_invoker = true) as
select movie_id,
       cinema_id,
       min(first_seen_at) as opened_at,
       min(starts_at)     as first_show
from showtimes
where starts_at > now()
group by movie_id, cinema_id
having min(first_seen_at) > now() - interval '3 days';

alter table cinemas      enable row level security;
alter table movies       enable row level security;
alter table source_films enable row level security;
alter table showtimes    enable row level security;
alter table scrape_runs  enable row level security;

create policy "public read" on cinemas      for select using (true);
create policy "public read" on movies       for select using (true);
create policy "public read" on source_films for select using (true);
create policy "public read" on showtimes    for select using (true);
-- scrape_runs stays private: no policy, so only the service role sees it.

grant usage on schema shebbak to anon, authenticated, service_role;
grant select on all tables in schema shebbak to anon, authenticated;
grant all on all tables in schema shebbak to service_role;
grant usage, select on all sequences in schema shebbak to service_role;

reset search_path;
