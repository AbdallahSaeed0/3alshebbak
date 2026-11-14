-- Settles shows two sources list at elCinema's cinemas inside the database,
-- instead of the pipeline downloading ~30k rows after every sync to work it
-- out (that was most of the project's egress). Same rules as the TypeScript
-- it replaces (src/supabase.ts, reconcileSources), which stays as the
-- fallback until this is run:
--   - elCinema's upcoming row goes when the booking page sells that film at
--     that cinema (any of its rows in the last two weeks) and covers that
--     cinema's day, or when VOX's own page lists that film there that day;
--   - the booking page's upcoming row goes when Premiere's site lists the
--     same film, cinema and start.
-- Returns how many rows it removed.

create or replace function shebbak.reconcile_sources()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed integer;
begin
  with base as (
    select id, source, movie_id, cinema_id, business_date, starts_at
    from shebbak.showtimes
    where source in ('elcinema', 'vox', 'premiere', 'elcinema-presales')
      and cinema_id like 'elcinema:%'
      and starts_at > now() - interval '14 days'
  ),
  upcoming as (
    select * from base where starts_at > now()
  ),
  doomed as (
    select e.id
    from upcoming e
    where e.source = 'elcinema'
      and (
        (
          exists (
            select 1 from base b
            where b.source = 'elcinema-presales'
              and b.movie_id = e.movie_id and b.cinema_id = e.cinema_id
          )
          and exists (
            select 1 from upcoming p
            where p.source = 'elcinema-presales'
              and p.cinema_id = e.cinema_id and p.business_date = e.business_date
          )
        )
        or exists (
          select 1 from upcoming v
          where v.source = 'vox'
            and v.movie_id = e.movie_id and v.cinema_id = e.cinema_id
            and v.business_date = e.business_date
        )
      )
    union
    select p.id
    from upcoming p
    where p.source = 'elcinema-presales'
      and exists (
        select 1 from upcoming q
        where q.source = 'premiere'
          and q.movie_id = p.movie_id and q.cinema_id = p.cinema_id
          and q.starts_at = p.starts_at
      )
  )
  delete from shebbak.showtimes s
  using doomed d
  where s.id = d.id;

  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function shebbak.reconcile_sources() from public, anon, authenticated;
grant execute on function shebbak.reconcile_sources() to service_role;
