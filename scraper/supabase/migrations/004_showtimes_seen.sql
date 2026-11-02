-- عالشباك — every showtime the sources have ever listed, for alerts. Run once
-- in the SQL editor, before the pipeline that writes it runs.
--
-- `showtimes` drops a show the moment a source stops listing it, so a show
-- that disappears for one run and comes back would look new. This table keeps
-- each id until the show is over, which is what "new days / new showtimes"
-- alerts compare against.

set search_path to shebbak;

create table showtimes_seen (
  id             text primary key,        -- same id as showtimes.id
  movie_id       text not null,
  cinema_id      text not null,
  business_date  date not null,
  starts_at      timestamptz not null,
  first_seen_at  timestamptz not null default now()
);

create index showtimes_seen_movie on showtimes_seen (movie_id, starts_at);
create index showtimes_seen_first on showtimes_seen (first_seen_at);

alter table showtimes_seen enable row level security;
revoke all on showtimes_seen from anon, authenticated;
grant all on showtimes_seen to service_role;

-- What's on sale today counts as already seen, so the first run after this
-- announces nothing that wasn't new anyway.
insert into showtimes_seen (id, movie_id, cinema_id, business_date, starts_at, first_seen_at)
select id, movie_id, cinema_id, business_date, starts_at, first_seen_at
from showtimes
on conflict (id) do nothing;
