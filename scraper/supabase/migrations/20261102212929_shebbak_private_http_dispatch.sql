-- Use synchronous HTTP so authorization headers are never persisted in a queue.
create extension if not exists http with schema extensions;
create sequence if not exists shebbak_private.dispatch_request_id_seq start 1000000;
alter table shebbak_private.pipeline_dispatches add column if not exists status_code integer;

create or replace function shebbak_private.dispatch_pipeline()
returns bigint language plpgsql security invoker set search_path = '' as $$
declare
  access_token text;
  sources text;
  slot integer;
  request_id bigint;
  response extensions.http_response;
begin
  select decrypted_secret into access_token from vault.decrypted_secrets
    where name = 'shebbak_github_dispatch_token';
  if access_token is null then raise exception 'Pipeline dispatch token is missing'; end if;
  slot := extract(minute from now() at time zone 'UTC')::integer / 10;
  sources := case when slot = 0 then 'renaissance scene elcinema vox'
                  when slot = 3 then 'renaissance scene vox' else 'vox' end;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');
  select * into response from extensions.http((
    'POST',
    'https://api.github.com/repos/AbdallahSaeed0/3alshebbak/actions/workflows/pipeline.yml/dispatches',
    array[
      extensions.http_header('Authorization','Bearer ' || access_token),
      extensions.http_header('Accept','application/vnd.github+json'),
      extensions.http_header('User-Agent','shebbak-supabase-cron'),
      extensions.http_header('X-GitHub-Api-Version','2022-11-28')
    ],
    'application/json',
    jsonb_build_object('ref','main','inputs',jsonb_build_object('sources',sources))::text
  )::extensions.http_request);
  if response.status <> 204 then
    raise exception 'GitHub dispatch rejected: HTTP %', response.status;
  end if;
  request_id := nextval('shebbak_private.dispatch_request_id_seq');
  insert into shebbak_private.pipeline_dispatches(request_id,sources,status_code)
    values(request_id,sources,response.status);
  delete from shebbak_private.pipeline_dispatches where requested_at < now() - interval '30 days';
  return request_id;
end $$;
revoke all on function shebbak_private.dispatch_pipeline() from public, anon, authenticated;

-- pg_net was introduced only by the preceding scheduler migration.
drop extension if exists pg_net;
