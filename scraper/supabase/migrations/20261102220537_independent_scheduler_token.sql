create function shebbak.replace_scheduler_token(p_token text,p_expires_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare secret_id uuid;
begin
  if p_token not like 'github_pat_%' or p_expires_at <= now() then
    raise exception 'A valid independent fine-grained token and future expiry are required';
  end if;
  select id into secret_id from vault.secrets where name='shebbak_github_dispatch_token';
  if secret_id is null then perform vault.create_secret(p_token,'shebbak_github_dispatch_token');
  else perform vault.update_secret(secret_id,p_token); end if;
  update shebbak_private.pipeline_watchdog_state set github_token_expires_at=p_expires_at where singleton;
end $$;
revoke all on function shebbak.replace_scheduler_token(text,timestamptz) from public,anon,authenticated;
grant execute on function shebbak.replace_scheduler_token(text,timestamptz) to service_role;
