-- The hall a show is in, where the source says: "elcinema:<screen id>" from
-- elCinema's booking lookup (src/sources/elcinema.ts). The app matches it to
-- a recorded hall plan (scraper/data/halls.json, elcinemaScreenId) for the
-- 3D seat view. Null for shows whose hall isn't known.

alter table shebbak.showtimes
  add column if not exists hall text;

comment on column shebbak.showtimes.hall is
  'Hall the show is in, as "<source>:<hall id>" (e.g. "elcinema:1290004"); null when unknown.';
