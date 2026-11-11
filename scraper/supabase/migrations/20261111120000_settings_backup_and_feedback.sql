-- عالشباك — two things in one file: a phone's settings, kept so they come
-- back after the app is deleted and installed again on the same phone; and
-- the app's feedback form (further down). Run once in the Supabase SQL
-- editor. Safe to run again.
--
-- The key is a SHA-256 hash the app makes from an id that survives a
-- reinstall on that phone (Android's per-app ANDROID_ID; on iPhone a random
-- id kept in the Keychain). The id itself never leaves the phone. What's kept
-- is what the app's settings hold: cinemas, followed films, alert choices,
-- home city, language and look. Never the phone's location.
create table if not exists shebbak.settings_backups (
  owner       text primary key,           -- sha256 hex
  settings    jsonb not null,
  platform    text,
  updated_at  timestamptz not null default now()
);

alter table shebbak.settings_backups enable row level security;
revoke all on shebbak.settings_backups from public, anon, authenticated;
grant all on shebbak.settings_backups to service_role;

create or replace function shebbak.save_settings(p_owner text, p_settings jsonb, p_platform text)
returns void
language sql
security definer
set search_path = shebbak
as $$
  insert into settings_backups (owner, settings, platform)
  select p_owner, p_settings, left(p_platform, 10)
  where p_owner ~ '^[0-9a-f]{64}$'
    and jsonb_typeof(p_settings) = 'object'
    and pg_column_size(p_settings) < 32768
  on conflict (owner) do update
    set settings = excluded.settings,
        platform = excluded.platform,
        updated_at = now();
$$;

create or replace function shebbak.load_settings(p_owner text)
returns jsonb
language sql
stable
security definer
set search_path = shebbak
as $$
  select settings from settings_backups where owner = p_owner;
$$;

revoke all on function shebbak.save_settings, shebbak.load_settings from public;
grant execute on function shebbak.save_settings, shebbak.load_settings to anon, authenticated;

-- Feedback from the app's "send us your thoughts" page: complaints,
-- suggestions, wrong showtimes. Read it with `npm run feedback` (scraper/).
create table if not exists shebbak.feedback (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  kind        text not null,              -- 'complaint' | 'idea' | 'showtimes' | 'other'
  message     text not null,
  contact     text,                       -- optional: how to reply
  platform    text,
  version     text,
  install_id  text,                       -- the random id from app_opens, for rate limiting
  handled     boolean not null default false
);
create index if not exists feedback_created on shebbak.feedback (created_at desc);

alter table shebbak.feedback enable row level security;
revoke all on shebbak.feedback from public, anon, authenticated;
grant all on shebbak.feedback to service_role;

-- Returns false when refused (empty, too long, or too many from one install).
create or replace function shebbak.submit_feedback(
  p_kind text, p_message text, p_contact text,
  p_platform text, p_version text, p_install text)
returns boolean
language plpgsql
security definer
set search_path = shebbak
as $$
begin
  if length(trim(coalesce(p_message, ''))) < 3 or length(p_message) > 4000
     or length(coalesce(p_contact, '')) > 200 then
    return false;
  end if;
  if p_install is not null and (
       select count(*) from feedback
       where install_id = p_install and created_at > now() - interval '1 hour') >= 5 then
    return false;
  end if;
  insert into feedback (kind, message, contact, platform, version, install_id)
  values (
    case when p_kind in ('complaint', 'idea', 'showtimes', 'other') then p_kind else 'other' end,
    trim(p_message), nullif(trim(coalesce(p_contact, '')), ''),
    left(p_platform, 10), left(p_version, 20), left(p_install, 64));
  return true;
end;
$$;

revoke all on function shebbak.submit_feedback from public;
grant execute on function shebbak.submit_feedback to anon, authenticated;
