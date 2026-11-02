create table shebbak.notification_progress (
  token text not null references shebbak.devices(token) on delete cascade,
  movie_id text not null,
  checked_through timestamptz not null,
  primary key(token,movie_id)
);
alter table shebbak.notification_progress enable row level security;
revoke all on shebbak.notification_progress from public,anon,authenticated;
grant all on shebbak.notification_progress to service_role;
-- Preserve previously applied daily suppression while upgrading.
insert into shebbak.notification_progress(token,movie_id,checked_through)
select token,movie_id,max((sent_on+1)::timestamp at time zone 'Africa/Cairo')
from shebbak.notifications_sent group by token,movie_id;
