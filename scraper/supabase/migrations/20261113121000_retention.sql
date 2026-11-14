-- Do people come back? From app_opens (one row per install per day it opened),
-- installs grouped by the week they first opened the app, and how many of
-- them opened it again: the next day, within the first week (days 1–7), and in
-- the second week (days 8–14). Null where that week hasn't fully passed yet.
-- Read with `npm run users`. Run once in the Supabase SQL editor. Safe to run again.

create or replace view shebbak.retention as
with firsts as (
  select install_id, min(day) as first_day, (array_agg(platform order by day))[1] as platform
  from shebbak.app_opens group by install_id
), back as (
  select f.install_id, f.first_day, f.platform,
    bool_or(o.day = f.first_day + 1)                                  as d1,
    bool_or(o.day between f.first_day + 1 and f.first_day + 7)        as week1,
    bool_or(o.day between f.first_day + 8 and f.first_day + 14)       as week2
  from firsts f
  left join shebbak.app_opens o on o.install_id = f.install_id and o.day > f.first_day
  group by f.install_id, f.first_day, f.platform
), today as (select (now() at time zone 'Africa/Cairo')::date as d)
select date_trunc('week', b.first_day)::date as cohort_week,
  count(*)                                                             as new_installs,
  count(*) filter (where b.platform = 'ios')                           as ios,
  case when max(b.first_day) + 1  < t.d then round(100.0 * count(*) filter (where b.d1)    / count(*)) end as d1_pct,
  case when max(b.first_day) + 7  < t.d then round(100.0 * count(*) filter (where b.week1) / count(*)) end as week1_pct,
  case when max(b.first_day) + 14 < t.d then round(100.0 * count(*) filter (where b.week2) / count(*)) end as week2_pct
from back b cross join today t
group by date_trunc('week', b.first_day), t.d
order by cohort_week desc;

revoke all on shebbak.retention from public, anon, authenticated;
grant select on shebbak.retention to service_role;
