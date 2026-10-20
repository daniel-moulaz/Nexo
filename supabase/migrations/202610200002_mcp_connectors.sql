-- Nexo MCP connectors: read-only access for an AI assistant to ONE dataset of
-- its owner. Tokens are shown once and stored only as SHA-256. Data is read
-- by service-role-only functions used by the nexo-mcp Edge Function.
begin;

create schema nexo_mcp_private;
revoke all on schema nexo_mcp_private from public, anon, authenticated;

create table nexo_mcp_private.connectors (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  dataset_id uuid not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  label text not null check (length(label) between 1 and 60),
  scope text not null default 'read' check (scope = 'read'),
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz,
  foreign key (dataset_id, owner_id)
    references nexo_sync_lab_private.datasets(id, owner_id)
);
create table nexo_mcp_private.audit (
  id bigint generated always as identity primary key,
  connector_id uuid not null references nexo_mcp_private.connectors(id),
  owner_id uuid not null,
  tool text not null check (length(tool) between 1 and 64),
  ok boolean not null,
  created_at timestamptz not null default now()
);
create index on nexo_mcp_private.audit (connector_id, created_at);

alter table nexo_mcp_private.connectors enable row level security;
alter table nexo_mcp_private.audit enable row level security;
create policy owner_read on nexo_mcp_private.connectors for select
  to authenticated using (owner_id = (select auth.uid()));
create policy owner_read on nexo_mcp_private.audit for select
  to authenticated using (owner_id = (select auth.uid()));
revoke all on all tables in schema nexo_mcp_private from public, anon, authenticated;

-- ── Called by the signed-in person (app) ───────────────────────────────────
create function public.nexo_mcp_create_connector(p_dataset_id uuid, p_label text)
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
  -- 244 random bits from two strong v4 UUIDs; only the hash is stored.
  v_token := 'nexo_mcp_' || replace(gen_random_uuid()::text, '-', '')
    || replace(gen_random_uuid()::text, '-', '');
  insert into nexo_mcp_private.connectors(owner_id, dataset_id, token_hash, label)
    values (v_user, p_dataset_id, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), trim(p_label))
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'label', trim(p_label), 'token', v_token);
end;
$$;

create function public.nexo_mcp_list_connectors()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'label', label, 'dataset_id', dataset_id, 'created_at', created_at,
      'last_used_at', last_used_at, 'revoked_at', revoked_at) order by created_at)
    from nexo_mcp_private.connectors where owner_id = v_user), '[]'::jsonb);
end;
$$;

create function public.nexo_mcp_revoke_connector(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update nexo_mcp_private.connectors set revoked_at = coalesce(revoked_at, now())
    where id = p_id and owner_id = v_user;
  if not found then
    raise exception using errcode = '42501', message = 'connector_unavailable';
  end if;
end;
$$;

-- ── Called only by the Edge Function (service_role) ───────────────────────
create function public.nexo_mcp_authenticate(p_token_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_row nexo_mcp_private.connectors%rowtype;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return null; end if;
  update nexo_mcp_private.connectors set last_used_at = now()
    where token_hash = p_token_hash and revoked_at is null
    returning * into v_row;
  if not found then return null; end if;
  return jsonb_build_object('id', v_row.id, 'owner_id', v_row.owner_id,
    'dataset_id', v_row.dataset_id, 'scope', v_row.scope);
end;
$$;

create function public.nexo_mcp_ledger(p_connector_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_row nexo_mcp_private.connectors%rowtype;
begin
  select * into v_row from nexo_mcp_private.connectors
    where id = p_connector_id and revoked_at is null;
  if not found then
    raise exception using errcode = '42501', message = 'connector_unavailable';
  end if;
  return jsonb_build_object(
    'entities', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'value', value))
      from nexo_sync_lab_private.entities
      where dataset_id = v_row.dataset_id and owner_id = v_row.owner_id
        and value is not null and deleted_at is null
        and kind in ('accounts', 'categories', 'transactions', 'transaction_metadata',
          'recurring_payments', 'investments', 'investment_operations')), '[]'::jsonb),
    'balances', coalesce((select jsonb_agg(jsonb_build_object('account_id', account_id, 'micros', micros))
      from nexo_sync_lab_private.balances
      where dataset_id = v_row.dataset_id and owner_id = v_row.owner_id), '[]'::jsonb));
end;
$$;

create function public.nexo_mcp_audit(p_connector_id uuid, p_tool text, p_ok boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into nexo_mcp_private.audit(connector_id, owner_id, tool, ok)
    select id, owner_id, left(p_tool, 64), coalesce(p_ok, false)
    from nexo_mcp_private.connectors where id = p_connector_id;
end;
$$;

revoke all on function public.nexo_mcp_create_connector(uuid, text) from public, anon, authenticated;
revoke all on function public.nexo_mcp_list_connectors() from public, anon, authenticated;
revoke all on function public.nexo_mcp_revoke_connector(uuid) from public, anon, authenticated;
revoke all on function public.nexo_mcp_authenticate(text) from public, anon, authenticated;
revoke all on function public.nexo_mcp_ledger(uuid) from public, anon, authenticated;
revoke all on function public.nexo_mcp_audit(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.nexo_mcp_create_connector(uuid, text) to authenticated;
grant execute on function public.nexo_mcp_list_connectors() to authenticated;
grant execute on function public.nexo_mcp_revoke_connector(uuid) to authenticated;
grant execute on function public.nexo_mcp_authenticate(text) to service_role;
grant execute on function public.nexo_mcp_ledger(uuid) to service_role;
grant execute on function public.nexo_mcp_audit(uuid, text, boolean) to service_role;

notify pgrst, 'reload schema';
commit;
