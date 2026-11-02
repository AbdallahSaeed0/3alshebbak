create extension if not exists pg_cron;
create extension if not exists pg_net;
create schema if not exists shebbak_private;
revoke all on schema shebbak_private from public, anon, authenticated;
create table if not exists shebbak_private.pipeline_dispatches (
  request_id bigint primary key,
  requested_at timestamptz not null default now(),
  sources text not null
);
alter table shebbak_private.pipeline_dispatches enable row level security;
revoke all on shebbak_private.pipeline_dispatches from public, anon, authenticated;

create or replace function shebbak_private.dispatch_pipeline()
returns bigint language plpgsql security invoker set search_path = '' as $$
declare
  access_token text;
  sources text;
  slot integer;
  request_id bigint;
begin
  -- Restrict the URL and repository in code; callers cannot redirect credentials.
  select decrypted_secret into access_token from vault.decrypted_secrets
    where name = 'shebbak_github_dispatch_token';
  if access_token is null then raise exception 'Pipeline dispatch token is missing'; end if;
  slot := extract(minute from now() at time zone 'UTC')::integer / 10;
  sources := case when slot = 0 then 'renaissance scene elcinema vox'
                  when slot = 3 then 'renaissance scene vox'
                  else 'vox' end;
  select net.http_post(
    url := 'https://api.github.com/repos/AbdallahSaeed0/3alshebbak/actions/workflows/pipeline.yml/dispatches',
    headers := jsonb_build_object('Authorization','Bearer ' || access_token,
      'Accept','application/vnd.github+json','Content-Type','application/json',
      'User-Agent','shebbak-supabase-cron','X-GitHub-Api-Version','2022-11-28'),
    body := jsonb_build_object('ref','main','inputs',jsonb_build_object('sources',sources)),
    timeout_milliseconds := 15000
  ) into request_id;
  insert into shebbak_private.pipeline_dispatches(request_id,sources) values(request_id,sources);
  delete from shebbak_private.pipeline_dispatches where requested_at < now() - interval '30 days';
  return request_id;
end $$;
revoke all on function shebbak_private.dispatch_pipeline() from public, anon, authenticated;


-- Authorization must be configured separately in Vault, never committed here.
revoke select on net.http_request_queue from public, anon, authenticated;
revoke select on net._http_response from public, anon, authenticated;
select cron.schedule('shebbak-showtimes-every-10-minutes',
  '7,17,27,37,47,57 * * * *', $$select shebbak_private.dispatch_pipeline();$$);
