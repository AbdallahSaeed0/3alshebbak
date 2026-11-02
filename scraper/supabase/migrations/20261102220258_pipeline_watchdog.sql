create table shebbak_private.pipeline_watchdog_state (
  singleton boolean primary key default true check(singleton),
  previous_signature text not null default '',
  github_token_expires_at timestamptz
);
alter table shebbak_private.pipeline_watchdog_state enable row level security;
revoke all on shebbak_private.pipeline_watchdog_state from public,anon,authenticated;
insert into shebbak_private.pipeline_watchdog_state(singleton) values(true);

create function shebbak.configure_pipeline_watchdog(p_firebase text,p_service_key text)
returns void language plpgsql security definer set search_path='' as $$
declare secret_id uuid; item record;
begin
  if p_firebase::jsonb->>'project_id' <> 'shebbak-app' then raise exception 'Unexpected Firebase project'; end if;
  for item in select * from (values ('shebbak_watchdog_firebase',p_firebase),('shebbak_service_role',p_service_key)) as s(name,value) loop
    select id into secret_id from vault.decrypted_secrets where name=item.name and decrypted_secret=item.value;
    if secret_id is not null then continue; end if;
    select id into secret_id from vault.secrets where name=item.name;
    if secret_id is null then perform vault.create_secret(item.value,item.name);
    else perform vault.update_secret(secret_id,item.value); end if;
  end loop;
end $$;
revoke all on function shebbak.configure_pipeline_watchdog(text,text) from public,anon,authenticated;
grant execute on function shebbak.configure_pipeline_watchdog(text,text) to service_role;

create function shebbak.pipeline_watchdog_context()
returns jsonb language sql security definer set search_path='' as $$
with stale as (
  select expected.source from (values
    ('vox',35),('renaissance',95),('scene',95),('elcinema',150),('premiere',95),('alerts',35)
  ) as expected(source,minutes)
  where not exists(select 1 from shebbak.scrape_runs r where r.source=expected.source and r.ok=true
    and r.started_at > now()-make_interval(mins=>expected.minutes))
), issues as (
  select source as problem from stale
  union all select 'dispatch' where not exists(
    select 1 from shebbak_private.pipeline_dispatches where status_code=204 and requested_at>now()-interval '25 minutes')
  union all select 'token_expiry' from shebbak_private.pipeline_watchdog_state
    where github_token_expires_at < now()+interval '7 days'
), problems as (
  select coalesce(jsonb_agg(problem order by problem),'[]'::jsonb) as items,
    coalesce(string_agg(problem,',' order by problem),'') as signature from issues
)
select jsonb_build_object(
  'problems',p.items,'signature',p.signature,'previous_signature',s.previous_signature,
  'firebase',(select decrypted_secret from vault.decrypted_secrets where name='shebbak_watchdog_firebase'),
  'device_token',(select token from shebbak.devices where
    encode(extensions.digest(token,'sha256'),'hex')='76627b80eb3c7abc8d99015d757fbc00c69946c20392668c5292cbba519b5249' limit 1)
) from problems p cross join shebbak_private.pipeline_watchdog_state s;
$$;
revoke all on function shebbak.pipeline_watchdog_context() from public,anon,authenticated;
grant execute on function shebbak.pipeline_watchdog_context() to service_role;

create function shebbak.ack_pipeline_watchdog(p_signature text)
returns void language sql security definer set search_path='' as $$
update shebbak_private.pipeline_watchdog_state set previous_signature=p_signature where singleton;
$$;
revoke all on function shebbak.ack_pipeline_watchdog(text) from public,anon,authenticated;
grant execute on function shebbak.ack_pipeline_watchdog(text) to service_role;

create function shebbak_private.invoke_pipeline_watchdog()
returns integer language plpgsql security invoker set search_path='' as $$
declare response extensions.http_response; access_key text;
begin
  select decrypted_secret into access_key from vault.decrypted_secrets where name='shebbak_service_role';
  if access_key is null then raise exception 'Watchdog service credential missing'; end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','60000');
  select * into response from extensions.http((
    'POST','https://enmcbbwunzhjxgwehzuf.supabase.co/functions/v1/pipeline-watchdog',
    array[extensions.http_header('Authorization','Bearer '||access_key)],'application/json','{}'
  )::extensions.http_request);
  if response.status <> 200 then raise exception 'Watchdog HTTP %',response.status; end if;
  return response.status;
end $$;
revoke all on function shebbak_private.invoke_pipeline_watchdog() from public,anon,authenticated;
select cron.schedule('shebbak-pipeline-watchdog','2,12,22,32,42,52 * * * *',
  $$select shebbak_private.invoke_pipeline_watchdog();$$);
