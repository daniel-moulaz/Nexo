-- Nexo: each device tells which assistant requests it knows how to apply, so
-- a request no installed app understands is refused when Claude asks
-- ("atualize o app") instead of waiting and coming back "Pedido
-- desconhecido". Devices that never reported (older apps) keep the old
-- behavior. The ledger mirror also carries card invoice payments, so the
-- assistant can tell what is left of each invoice.
begin;

create table if not exists nexo_mcp_private.capabilities (
  owner_id uuid not null,
  dataset_id uuid not null,
  device_id uuid not null,
  app_version text not null check (length(app_version) between 1 and 40),
  kinds text[] not null check (cardinality(kinds) between 1 and 200),
  seen_at timestamptz not null default now(),
  primary key (owner_id, dataset_id, device_id)
);
alter table nexo_mcp_private.capabilities enable row level security;

create or replace function public.nexo_mcp_report_capabilities(
  p_dataset_id uuid, p_device_id uuid, p_version text, p_kinds text[])
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_version is null or length(p_version) not between 1 and 40
      or p_kinds is null or cardinality(p_kinds) not between 1 and 200
      or exists (select 1 from unnest(p_kinds) k where k !~ '^[a-z]+\.[a-z_]+$') then
    raise exception using errcode = '22023', message = 'invalid_capabilities';
  end if;
  insert into nexo_mcp_private.capabilities(owner_id, dataset_id, device_id, app_version, kinds, seen_at)
    values (v_user, p_dataset_id, p_device_id, p_version, p_kinds, now())
  on conflict (owner_id, dataset_id, device_id) do update
    set app_version = excluded.app_version, kinds = excluded.kinds, seen_at = now();
end;
$$;

create or replace function public.nexo_mcp_enqueue(p_connector_id uuid, p_kind text, p_args jsonb)
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
  -- Only refuse when some device reported and none of them knows the kind.
  if exists (select 1 from nexo_mcp_private.capabilities c
        where c.owner_id = v_row.owner_id and c.dataset_id = v_row.dataset_id
          and c.seen_at > now() - interval '30 days')
      and not exists (select 1 from nexo_mcp_private.capabilities c
        where c.owner_id = v_row.owner_id and c.dataset_id = v_row.dataset_id
          and c.seen_at > now() - interval '30 days' and p_kind = any(c.kinds)) then
    raise exception using errcode = '22023', message = 'kind_unsupported';
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

create or replace function public.nexo_mcp_ledger(p_connector_id uuid)
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
          'recurring_payments', 'recurring_history', 'investments',
          'investment_operations', 'budgets', 'savings_goals',
          'savings_contributions', 'loans', 'loan_payments', 'lended_money',
          'lended_people', 'assets', 'wishlist', 'card_invoice_payments')), '[]'::jsonb),
    'balances', coalesce((select jsonb_agg(jsonb_build_object('account_id', account_id, 'micros', micros))
      from nexo_sync_lab_private.balances
      where dataset_id = v_row.dataset_id and owner_id = v_row.owner_id), '[]'::jsonb));
end;
$$;

revoke all on function public.nexo_mcp_report_capabilities(uuid, uuid, text, text[]) from public, anon;
grant execute on function public.nexo_mcp_report_capabilities(uuid, uuid, text, text[]) to authenticated;

notify pgrst, 'reload schema';
commit;
