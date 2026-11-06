-- What happened to each film's new showtimes, per phone, each alerts run, so
-- "why didn't I get a notification for X?" has an answer. Kept two weeks
-- (notify.ts deletes older rows). Read it in the Supabase table editor or with
-- `npm run notify-log -- <film>`.
--
-- outcome:
--   sent           a notification went out (kind = opened / days / shows / digest)
--   failed         Firebase refused it; the next run retries (error says why)
--   stale_device   the phone's token is dead (app uninstalled); device removed
--   daily_limit    this phone already heard about this film today
--   not_new        the "new" shows were ones the phone already knew about
--   other_cinemas  the film got shows, but none at this phone's cinemas
--   nobody_follows the film got shows and no phone follows it (device is null)
--   no_firebase    the run had no Firebase key, so nothing could be sent
create table shebbak.notification_log (
  id        bigint generated always as identity primary key,
  run_at    timestamptz not null,
  movie_id  text,
  film      text,
  device    text,            -- last 8 characters of the phone's token
  outcome   text not null,
  kind      text,
  cinemas   text[],
  new_shows int,
  title     text,
  body      text,
  error     text
);
create index notification_log_run_at on shebbak.notification_log (run_at desc);
create index notification_log_movie on shebbak.notification_log (movie_id, run_at desc);

alter table shebbak.notification_log enable row level security;
revoke all on shebbak.notification_log from public, anon, authenticated;
grant all on shebbak.notification_log to service_role;
