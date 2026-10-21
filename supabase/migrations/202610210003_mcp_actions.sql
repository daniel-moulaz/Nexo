-- Nexo: requests from the AI assistant (Claude) to change the ledger.
-- The server never writes financial data itself: it queues a request, a
-- device of the owner claims it, applies it with the app's own rules, syncs,
-- and records the outcome. Reviewing Open Finance suggestions is the only
-- direct change (it moves no money).
begin;

alter table nexo_mcp_private.connectors drop constraint connectors_scope_check;
alter table nexo_mcp_private.connectors add constraint connectors_scope_check
  check (scope in ('read', 'write'));

create table nexo_mcp_private.commands (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  dataset_id uuid not null,
  connector_id uuid not null references nexo_mcp_private.connectors(id),
  kind text not null check (kind in ('transaction.add', 'transfer.add',
    'transaction.update', 'transaction.delete', 'suggestion.confirm')),
  args jsonb not null check (octet_length(args::text) <= 8192),
  status text not null default 'pending'
    check (status in ('pending', 'applying', 'done', 'rejected')),
  result jsonb,
  device_id uuid,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  finished_at timestamptz
);
create index commands_queue on nexo_mcp_private.commands(owner_id, dataset_id, status, created_at);
alter table nexo_mcp_private.commands enable row level security;
create policy owner_read on nexo_mcp_private.commands for select
  to authenticated using (owner_id = (select auth.uid()));
revoke all on nexo_mcp_private.commands from public, anon, authenticated;

-- New connectors may request changes; older ones stay read-only.
create or replace function public.nexo_mcp_create_connector(p_dataset_id uuid, p_label text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_token text;
  v_id uuid;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_label is null or length(trim(p_label)) not between 1 and 60 then
    raise exception using errcode = '22023', message = 'invalid_label';
  end if;
  if not exists (select 1 from nexo_sync_lab_private.datasets
      where id = p_dataset_id and owner_id = v_user) then
    raise exception using errcode = '42501', message = 'dataset_unavailable';
  end if;
  if (select count(*) from nexo_mcp_private.connectors
      where owner_id = v_user and revoked_at is null) >= 5 then
    raise exception using errcode = '22023', message = 'too_many_connectors';
  end if;
  v_token := 'nexo_mcp_' || replace(gen_random_uuid()::text, '-', '')
    || replace(gen_random_uuid()::text, '-', '');
  insert into nexo_mcp_private.connectors(owner_id, dataset_id, token_hash, label, scope)
    values (v_user, p_dataset_id, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
      trim(p_label), 'write')
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'label', trim(p_label), 'token', v_token);
end;
$$;

-- ── Edge Function (service role) ────────────────────────────────────────
create function public.nexo_mcp_enqueue(p_connector_id uuid, p_kind text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row nexo_mcp_private.connectors%rowtype;
  v_id uuid;
begin
  select * into v_row from nexo_mcp_private.connectors
    where id = p_connector_id and revoked_at is null;
  if not found then
    raise exception using errcode = '42501', message = 'connector_unavailable';
  end if;
  if v_row.scope <> 'write' then
    raise exception using errcode = '42501', message = 'read_only_connector';
  end if;
  if (select count(*) from nexo_mcp_private.commands
      where owner_id = v_row.owner_id and status in ('pending', 'applying')) >= 100 then
    raise exception using errcode = '22023', message = 'too_many_pending';
  end if;
  insert into nexo_mcp_private.commands(owner_id, dataset_id, connector_id, kind, args)
    values (v_row.owner_id, v_row.dataset_id, v_row.id, p_kind, p_args)
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'status', 'pending');
end;
$$;

create function public.nexo_mcp_command(p_connector_id uuid, p_id uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'kind', c.kind, 'status', c.status,
    'result', c.result, 'created_at', c.created_at, 'finished_at', c.finished_at)
  from nexo_mcp_private.commands c join nexo_mcp_private.connectors k
    on k.id = p_connector_id and k.revoked_at is null and k.owner_id = c.owner_id
  where c.id = p_id;
$$;

create function public.nexo_mcp_suggestions(p_connector_id uuid, p_limit integer)
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(page.item order by (page.item->>'occurred_at')::bigint desc), '[]'::jsonb)
  from (select jsonb_build_object('id', s.external_id, 'bank', i.label,
      'amount_cents', s.amount_cents, 'kind', s.kind, 'medium', s.medium,
      'description', s.description, 'occurred_at', s.occurred_at,
      'settled', s.settled, 'installment', s.installment) as item
    from nexo_pluggy_private.suggestions s
    join nexo_pluggy_private.items i on i.owner_id = s.owner_id and i.item_id = s.item_id
    join nexo_mcp_private.connectors k
      on k.id = p_connector_id and k.revoked_at is null and k.owner_id = s.owner_id
    where s.review = 'pending'
    order by s.occurred_at desc
    limit greatest(1, least(coalesce(p_limit, 30), 200))) page;
$$;

-- Ignoring moves no money, so it is applied here; devices drop the
-- suggestion from their inbox on the next refresh.
create function public.nexo_mcp_ignore_suggestions(
  p_connector_id uuid, p_ids text[], p_before_ms bigint
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_row nexo_mcp_private.connectors%rowtype;
  v_count integer;
begin
  select * into v_row from nexo_mcp_private.connectors
    where id = p_connector_id and revoked_at is null;
  if not found or v_row.scope <> 'write' then
    raise exception using errcode = '42501', message = 'read_only_connector';
  end if;
  if (p_ids is null or cardinality(p_ids) = 0) and p_before_ms is null then
    raise exception using errcode = '22023', message = 'invalid_selection';
  end if;
  update nexo_pluggy_private.suggestions set review = 'ignored', updated_at = now()
    where owner_id = v_row.owner_id and review = 'pending'
      and ((p_ids is not null and external_id = any(p_ids))
        or (p_before_ms is not null and occurred_at < p_before_ms));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ── App (signed-in person, one of their devices) ───────────────────────
-- Takes the oldest request of this dataset. A request left half-done by a
-- device that stopped is offered again after five minutes; devices make
-- applying idempotent.
create function public.nexo_mcp_claim(p_dataset_id uuid, p_device_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_row nexo_mcp_private.commands%rowtype;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  select * into v_row from nexo_mcp_private.commands
    where owner_id = v_user and dataset_id = p_dataset_id
      and (status = 'pending'
        or (status = 'applying' and claimed_at < now() - interval '5 minutes'))
    order by created_at limit 1 for update skip locked;
  if not found then return null; end if;
  update nexo_mcp_private.commands set status = 'applying', device_id = p_device_id,
      claimed_at = now()
    where id = v_row.id;
  return jsonb_build_object('id', v_row.id, 'kind', v_row.kind, 'args', v_row.args,
    'created_at', v_row.created_at);
end;
$$;

create function public.nexo_mcp_finish(p_id uuid, p_status text, p_result jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_status not in ('done', 'rejected') then
    raise exception using errcode = '22023', message = 'invalid_status';
  end if;
  update nexo_mcp_private.commands set status = p_status, result = p_result,
      finished_at = now()
    where id = p_id and owner_id = v_user and status in ('applying', 'pending');
end;
$$;

revoke all on function public.nexo_mcp_enqueue(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.nexo_mcp_command(uuid, uuid) from public, anon, authenticated;
revoke all on function public.nexo_mcp_suggestions(uuid, integer) from public, anon, authenticated;
revoke all on function public.nexo_mcp_ignore_suggestions(uuid, text[], bigint) from public, anon, authenticated;
revoke all on function public.nexo_mcp_claim(uuid, uuid) from public, anon, authenticated;
revoke all on function public.nexo_mcp_finish(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.nexo_mcp_enqueue(uuid, text, jsonb) to service_role;
grant execute on function public.nexo_mcp_command(uuid, uuid) to service_role;
grant execute on function public.nexo_mcp_suggestions(uuid, integer) to service_role;
grant execute on function public.nexo_mcp_ignore_suggestions(uuid, text[], bigint) to service_role;
grant execute on function public.nexo_mcp_claim(uuid, uuid) to authenticated;
grant execute on function public.nexo_mcp_finish(uuid, text, jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
