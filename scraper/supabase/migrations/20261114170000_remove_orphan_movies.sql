-- Removes movies a re-match replaced, in one call. The pipeline used to try
-- deleting every movie missing from its run one request at a time (about a
-- hundred refused deletes each VOX-only run) and let the foreign keys keep
-- the ones still in use; this deletes only those nothing points at.
-- [keep]: the movies this run matched, which stay either way.
-- Returns how many it removed.

create or replace function shebbak.remove_orphan_movies(keep text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed integer;
begin
  delete from shebbak.movies m
  where m.id <> all (keep)
    and not exists (select 1 from shebbak.showtimes s where s.movie_id = m.id)
    and not exists (select 1 from shebbak.source_films f where f.movie_id = m.id);
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function shebbak.remove_orphan_movies(text[]) from public, anon, authenticated;
grant execute on function shebbak.remove_orphan_movies(text[]) to service_role;
