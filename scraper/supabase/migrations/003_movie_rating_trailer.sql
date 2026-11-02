-- TMDB's rating and a YouTube trailer for each film, shown on the film page
-- and the cards. Filled by the pipeline (src/tmdb.ts).

alter table shebbak.movies
  add column if not exists rating numeric(3, 1),
  add column if not exists trailer_key text;

comment on column shebbak.movies.rating is
  'TMDB vote average out of 10; null until enough people voted.';
comment on column shebbak.movies.trailer_key is
  'YouTube video id of the trailer (youtube.com/watch?v=<key>).';
