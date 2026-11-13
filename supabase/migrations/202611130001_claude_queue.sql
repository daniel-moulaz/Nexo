-- 1.17.0: the assistant's queue works with the app closed.
--
-- * Each device may register a push token (Firebase Cloud Messaging). When
--   the connector enqueues a request, the Edge Function sends a silent
--   message that wakes the phone to apply it. Only the function reads tokens.
-- * A request may need a minimum app build (e.g. dollar fields, build 58).
--   A device below it, or one that never listed the kind, does not take it:
--   it waits for a device that can, so nothing is recorded wrong and the
--   order of requests is kept.
-- * Each claim records when the device last checked the queue, for the
--   "Fila do Claude" status in the app and in get_request_status.
-- * Connector status for the app (last call, requests) and the reason a
--   token stopped working (revoked vs. unknown), for clearer errors.

alter table nexo_mcp_private.commands add column if not exists min_build integer
  check (min_build is null or min_build between 1 and 1000000);
alter table nexo_mcp_private.capabilities add column if not exists checked_at timestamptz;

create table if not exists nexo_mcp_private.push_tokens (
  owner_id uuid not null,
  dataset_id uuid not null,
  device_id uuid not null,
  token text not null check (length(token) between 20 and 4096),
  platform text not null default 'android' check (platform in ('android')),
  updated_at timestamptz not null default now(),
  primary key (owner_id, dataset_id, device_id)
);
alter table nexo_mcp_private.push_tokens enable row level security;
revoke all on nexo_mcp_private.push_tokens from public, anon, authenticated;

-- The build number of an app version such as '1.17.0+59'; 0 when unknown.
create or replace function nexo_mcp_private.build_of(p_version text)
returns integer language sql immutable set search_path = '' as $$
  select case when p_version ~ '\+[0-9]{1,9}$'
    then substring(p_version from '\+([0-9]{1,9})$')::integer else 0 end;
$$;

-- ── Called by the signed-in app ─────────────────────────────────────────
create or replace function public.nexo_push_register(
  p_dataset_id uuid, p_device_id uuid, p_token text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if not exists (select 1 from nexo_sync_lab_private.datasets
      where id = p_dataset_id and owner_id = v_user) then
    raise exception using errcode = '42501', message = 'dataset_unavailable';
  end if;
  if p_token is null then
    delete from nexo_mcp_private.push_tokens
      where owner_id = v_user and dataset_id = p_dataset_id and device_id = p_device_id;
    return;
  end if;
  if length(p_token) not between 20 and 4096 or p_token !~ '^[A-Za-z0-9_:\-\.]+$' then
    raise exception using errcode = '22023', message = 'invalid_token';
  end if;
  -- A token belongs to one installation: drop it from any older device id.
  delete from nexo_mcp_private.push_tokens
    where owner_id = v_user and token = p_token and device_id <> p_device_id;
  insert into nexo_mcp_private.push_tokens(owner_id, dataset_id, device_id, token, updated_at)
    values (v_user, p_dataset_id, p_device_id, p_token, now())
  on conflict (owner_id, dataset_id, device_id) do update
    set token = excluded.token, updated_at = now();
end;
$$;

-- What the "Fila do Claude" screen shows: the queue and each device.
create or replace function public.nexo_mcp_queue_status(p_dataset_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return jsonb_build_object(
    'pending', (select count(*) from nexo_mcp_private.commands
      where owner_id = v_user and dataset_id = p_dataset_id and status in ('pending', 'applying')),
    'oldest_pending_at', (select min(created_at) from nexo_mcp_private.commands
      where owner_id = v_user and dataset_id = p_dataset_id and status in ('pending', 'applying')),
    'waiting_for_update', (select count(*) from nexo_mcp_private.commands c
      where c.owner_id = v_user and c.dataset_id = p_dataset_id and c.status = 'pending'
        and c.min_build is not null
        and not exists (select 1 from nexo_mcp_private.capabilities d
          where d.owner_id = v_user and d.dataset_id = p_dataset_id
            and nexo_mcp_private.build_of(d.app_version) >= c.min_build)),
    'last_done_at', (select max(finished_at) from nexo_mcp_private.commands
      where owner_id = v_user and dataset_id = p_dataset_id and status in ('done', 'rejected')),
    'devices', coalesce((select jsonb_agg(jsonb_build_object(
        'device_id', d.device_id, 'app_version', d.app_version,
        'seen_at', d.seen_at, 'checked_at', d.checked_at,
        'push', exists (select 1 from nexo_mcp_private.push_tokens t
          where t.owner_id = v_user and t.dataset_id = p_dataset_id and t.device_id = d.device_id))
        order by d.seen_at desc)
      from nexo_mcp_private.capabilities d
      where d.owner_id = v_user and d.dataset_id = p_dataset_id
        and d.seen_at > now() - interval '60 days'), '[]'::jsonb));
end;
$$;

-- Connectors with their use, for the app's connector status.
create or replace function public.nexo_mcp_connector_status()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', k.id, 'label', k.label, 'dataset_id', k.dataset_id, 'scope', k.scope,
      'created_at', k.created_at, 'last_used_at', k.last_used_at, 'revoked_at', k.revoked_at,
      'requests', (select count(*) from nexo_mcp_private.commands c where c.connector_id = k.id),
      'requests_7d', (select count(*) from nexo_mcp_private.commands c
        where c.connector_id = k.id and c.created_at > now() - interval '7 days'),
      'last_request_at', (select max(created_at) from nexo_mcp_private.commands c
        where c.connector_id = k.id))
      order by k.created_at desc)
    from nexo_mcp_private.connectors k where k.owner_id = v_user), '[]'::jsonb);
end;
$$;

-- Claim: as before (one at a time per dataset, oldest first), plus the
-- device check and the time of the check.
create or replace function public.nexo_mcp_claim(p_dataset_id uuid, p_device_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_row nexo_mcp_private.commands%rowtype;
  v_device nexo_mcp_private.capabilities%rowtype;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('nexo_mcp_claim:' || p_dataset_id::text, 0));
  update nexo_mcp_private.capabilities set checked_at = now()
    where owner_id = v_user and dataset_id = p_dataset_id and device_id = p_device_id
    returning * into v_device;
  if exists (select 1 from nexo_mcp_private.commands
      where owner_id = v_user and dataset_id = p_dataset_id
        and status = 'applying' and claimed_at >= now() - interval '5 minutes') then
    return null;
  end if;
  select * into v_row from nexo_mcp_private.commands
    where owner_id = v_user and dataset_id = p_dataset_id
      and (status = 'pending'
        or (status = 'applying' and claimed_at < now() - interval '5 minutes'))
    order by created_at limit 1 for update;
  if not found then return null; end if;
  -- The oldest request waits for a device that can apply it; later ones
  -- wait behind it, so the order the assistant asked in is kept.
  if v_row.min_build is not null
      and coalesce(nexo_mcp_private.build_of(v_device.app_version), 0) < v_row.min_build then
    return null;
  end if;
  if v_device.device_id is not null and not (v_row.kind = any(v_device.kinds)) then
    return null;
  end if;
  update nexo_mcp_private.commands set status = 'applying', device_id = p_device_id,
      claimed_at = now()
    where id = v_row.id;
  return jsonb_build_object('id', v_row.id, 'kind', v_row.kind, 'args', v_row.args,
    'created_at', v_row.created_at);
end;
$$;

-- ── Called only by the Edge Function (service_role) ───────────────────
-- Enqueue with an optional minimum build. Same rules as v2.
create or replace function public.nexo_mcp_enqueue_v3(
  p_connector_id uuid, p_kind text, p_args jsonb, p_key text, p_min_build integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if p_min_build is not null and p_min_build not between 1 and 1000000 then
    raise exception using errcode = '22023', message = 'invalid_min_build';
  end if;
  v_result := public.nexo_mcp_enqueue_v2(p_connector_id, p_kind, p_args, p_key);
  -- Same transaction: no device can claim the new row before this update.
  if p_min_build is not null and not coalesce((v_result->>'deduplicated')::boolean, false) then
    update nexo_mcp_private.commands set min_build = p_min_build
      where id = (v_result->>'id')::uuid;
  end if;
  return v_result;
end;
$$;

-- Push tokens of the connector's dataset, newest device first.
create or replace function public.nexo_push_targets(p_connector_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_row nexo_mcp_private.connectors%rowtype;
begin
  select * into v_row from nexo_mcp_private.connectors
    where id = p_connector_id and revoked_at is null;
  if not found then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('device_id', device_id, 'token', token)
      order by updated_at desc)
    from nexo_mcp_private.push_tokens
    where owner_id = v_row.owner_id and dataset_id = v_row.dataset_id
      and updated_at > now() - interval '60 days'), '[]'::jsonb);
end;
$$;

-- FCM said the token no longer exists: forget it.
create or replace function public.nexo_push_forget(p_connector_id uuid, p_token text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_row nexo_mcp_private.connectors%rowtype;
begin
  select * into v_row from nexo_mcp_private.connectors where id = p_connector_id;
  if not found then return; end if;
  delete from nexo_mcp_private.push_tokens
    where owner_id = v_row.owner_id and token = p_token;
end;
$$;

-- Why a token does not authenticate: 'revoked' (with when) or 'unknown'.
-- Says nothing about whose it was.
create or replace function public.nexo_mcp_token_state(p_token_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_revoked timestamptz;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('state', 'unknown');
  end if;
  select revoked_at into v_revoked from nexo_mcp_private.connectors
    where token_hash = p_token_hash;
  if not found then return jsonb_build_object('state', 'unknown'); end if;
  if v_revoked is null then return jsonb_build_object('state', 'active'); end if;
  return jsonb_build_object('state', 'revoked', 'revoked_at', v_revoked);
end;
$$;

revoke all on function nexo_mcp_private.build_of(text) from public, anon, authenticated;
revoke all on function public.nexo_push_register(uuid, uuid, text) from public, anon;
revoke all on function public.nexo_mcp_queue_status(uuid) from public, anon;
revoke all on function public.nexo_mcp_connector_status() from public, anon;
revoke all on function public.nexo_mcp_claim(uuid, uuid) from public, anon;
revoke all on function public.nexo_mcp_enqueue_v3(uuid, text, jsonb, text, integer) from public, anon, authenticated;
revoke all on function public.nexo_push_targets(uuid) from public, anon, authenticated;
revoke all on function public.nexo_push_forget(uuid, text) from public, anon, authenticated;
revoke all on function public.nexo_mcp_token_state(text) from public, anon, authenticated;
grant execute on function public.nexo_push_register(uuid, uuid, text) to authenticated;
grant execute on function public.nexo_mcp_queue_status(uuid) to authenticated;
grant execute on function public.nexo_mcp_connector_status() to authenticated;
grant execute on function public.nexo_mcp_claim(uuid, uuid) to authenticated;
grant execute on function public.nexo_mcp_enqueue_v3(uuid, text, jsonb, text, integer) to service_role;
grant execute on function public.nexo_push_targets(uuid) to service_role;
grant execute on function public.nexo_push_forget(uuid, text) to service_role;
grant execute on function public.nexo_mcp_token_state(text) to service_role;

notify pgrst, 'reload schema';
