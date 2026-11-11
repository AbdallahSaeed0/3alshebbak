-- Who's in each film and who directed it, for the film page's cast section.
-- Filled by the pipeline (src/tmdb.ts) from TMDB's credits.

alter table shebbak.movies
  add column if not exists credits jsonb;

comment on column shebbak.movies.credits is
  'TMDB credits: {"cast": [{"n": name, "c": character, "p": profile_path}], "dir": [director names]}; null when unknown.';
