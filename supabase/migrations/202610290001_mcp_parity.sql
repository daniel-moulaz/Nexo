-- Nexo: the assistant reaches everything the app does (29/10/2026).
--
-- * Request kinds are checked by shape, not by a fixed list. Each device
--   reports which kinds it applies (capabilities), and enqueueing still
--   refuses a kind no reporting device knows. A new app action therefore
--   needs no migration.
-- * Idempotency: a request carries an optional key; the same key returns the
--   first request. Without a key, the same kind and arguments within ten
--   minutes (a retried call) return the first request too; the time a call
--   was made (`created_at` in the arguments) does not make it different.
-- * Order: a device claims a request only while no other request of the
--   dataset is being applied, so requests are applied one at a time, oldest
--   first (an adjustment never races a pending sale on another device).
-- * Undo: the app keeps in the result what the request changed. Undoing is
--   another request; the owner's device marks the original as undone.
-- * Devices report their own settings, and the ledger mirror carries the
--   shared settings and what each device can apply.
-- * The assistant reads Open Finance balances and official card invoices
--   (bank × Nexo) and links a bank account to a Nexo account.
-- No table is dropped and no existing row changes.
begin;

alter table nexo_mcp_private.commands drop constraint commands_kind_check;
alter table nexo_mcp_private.commands add constraint commands_kind_check
  check (kind ~ '^[a-z]+\.[a-z_]+$' and length(kind) <= 60);
alter table nexo_mcp_private.commands drop constraint commands_args_check;
alter table nexo_mcp_private.commands add constraint commands_args_check
  check (octet_length(args::text) <= 262144);
alter table nexo_mcp_private.commands add column if not exists idempotency_key text
  check (idempotency_key is null or length(idempotency_key) between 1 and 120);
create unique index if not exists commands_idempotency
  on nexo_mcp_private.commands(owner_id, idempotency_key)
  where idempotency_key is not null;

alter table nexo_mcp_private.capabilities add column if not exists settings jsonb
  check (settings is null or octet_length(settings::text) <= 16384);

-- ── Edge Function (service role) ────────────────────────────────────────
create or replace function public.nexo_mcp_enqueue_v2(
  p_connector_id uuid, p_kind text, p_args jsonb, p_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row nexo_mcp_private.connectors%rowtype;
  v_old nexo_mcp_private.commands%rowtype;
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
  if p_key is not null then
    select * into v_old from nexo_mcp_private.commands
      where owner_id = v_row.owner_id and idempotency_key = p_key;
    if found then
      if v_old.kind <> p_kind or v_old.args <> p_args then
        raise exception using errcode = '22023', message = 'idempotency_key_reused';
      end if;
      return jsonb_build_object('id', v_old.id, 'status', v_old.status, 'deduplicated', true);
    end if;
  else
    select * into v_old from nexo_mcp_private.commands
      where owner_id = v_row.owner_id and dataset_id = v_row.dataset_id
        and kind = p_kind and (args - 'created_at') = (p_args - 'created_at')
        and status <> 'rejected'
        and created_at > now() - interval '10 minutes'
      order by created_at desc limit 1;
    if found then
      return jsonb_build_object('id', v_old.id, 'status', v_old.status, 'deduplicated', true);
    end if;
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
  begin
    insert into nexo_mcp_private.commands(owner_id, dataset_id, connector_id, kind, args, idempotency_key)
      values (v_row.owner_id, v_row.dataset_id, v_row.id, p_kind, p_args, p_key)
      returning id into v_id;
  exception when unique_violation then
    -- The same key arrived twice at the same time: the first one wins.
    select * into v_old from nexo_mcp_private.commands
      where owner_id = v_row.owner_id and idempotency_key = p_key;
    return jsonb_build_object('id', v_old.id, 'status', v_old.status, 'deduplicated', true);
  end;
  return jsonb_build_object('id', v_id, 'status', 'pending', 'deduplicated', false);
end;
$$;

-- The connector's recent requests (what the assistant did), newest first.
create or replace function public.nexo_mcp_recent(p_connector_id uuid, p_limit integer)
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(page.item order by page.created desc), '[]'::jsonb)
  from (select c.created_at as created, jsonb_build_object('id', c.id, 'kind', c.kind,
      'status', c.status, 'created_at', c.created_at, 'finished_at', c.finished_at,
      'message', c.result->>'message', 'reason', c.result->>'reason',
      'undoable', c.status = 'done' and c.result ? 'undo'
        and not (c.result ? 'undone_at')
        and coalesce(c.result->'undo'->>'too_large', 'false') <> 'true',
      'undone_at', c.result->>'undone_at') as item
    from nexo_mcp_private.commands c
    join nexo_mcp_private.connectors k
      on k.id = p_connector_id and k.revoked_at is null and k.owner_id = c.owner_id
    where c.dataset_id = k.dataset_id
    order by c.created_at desc
    limit greatest(1, least(coalesce(p_limit, 30), 200))) page;
$$;

-- Ledger mirror plus the shared settings and each device's report.
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
          'lended_people', 'assets', 'wishlist', 'card_invoice_payments',
          'import_rules', 'shared_settings')), '[]'::jsonb),
    'balances', coalesce((select jsonb_agg(jsonb_build_object('account_id', account_id, 'micros', micros))
      from nexo_sync_lab_private.balances
      where dataset_id = v_row.dataset_id and owner_id = v_row.owner_id), '[]'::jsonb),
    'devices', coalesce((select jsonb_agg(jsonb_build_object('app_version', c.app_version,
        'kinds', to_jsonb(c.kinds), 'settings', c.settings, 'seen_at', c.seen_at)
        order by c.seen_at desc)
      from nexo_mcp_private.capabilities c
      where c.owner_id = v_row.owner_id and c.dataset_id = v_row.dataset_id
        and c.seen_at > now() - interval '30 days'), '[]'::jsonb));
end;
$$;

-- Open Finance accounts with the official card invoices, for "saldo do
-- banco × Nexo" and the bank's invoice next to the Nexo one.
create or replace function public.nexo_mcp_bank_accounts(p_connector_id uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'account_id', a.account_id, 'bank', i.label, 'type', a.type, 'subtype', a.subtype,
      'name', a.name, 'currency', a.currency, 'balance_cents', a.balance_cents,
      'credit_limit_cents', a.credit_limit_cents, 'available_cents', a.available_cents,
      'minimum_payment_cents', a.minimum_payment_cents, 'close_date', a.close_date,
      'due_date', a.due_date, 'nexo_account_id', a.nexo_account_id,
      'bank_updated_at', i.bank_updated_at,
      'bills', coalesce((select jsonb_agg(jsonb_build_object('due_date', b.due_date,
          'close_date', b.close_date, 'total_cents', b.total_cents,
          'minimum_cents', b.minimum_cents, 'paid_cents', b.paid_cents) order by b.due_date desc)
        from nexo_pluggy_private.bills b
        where b.owner_id = a.owner_id and b.account_id = a.account_id), '[]'::jsonb))
    order by i.created_at, a.type, a.name), '[]'::jsonb)
  from nexo_pluggy_private.accounts a
  join nexo_pluggy_private.items i on i.owner_id = a.owner_id and i.item_id = a.item_id
  join nexo_mcp_private.connectors k
    on k.id = p_connector_id and k.revoked_at is null and k.owner_id = a.owner_id;
$$;

-- Links a bank account to a Nexo account (the screen's "vincular"); moves no
-- money, so it is applied here, like ignoring suggestions.
create or replace function public.nexo_mcp_link_bank_account(
  p_connector_id uuid, p_account_id text, p_nexo_account_id text)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_row nexo_mcp_private.connectors%rowtype;
  v_count integer;
begin
  select * into v_row from nexo_mcp_private.connectors
    where id = p_connector_id and revoked_at is null;
  if not found or v_row.scope <> 'write' then
    raise exception using errcode = '42501', message = 'read_only_connector';
  end if;
  if p_nexo_account_id is not null and length(p_nexo_account_id) not between 1 and 128 then
    raise exception using errcode = '22023', message = 'invalid_account';
  end if;
  update nexo_pluggy_private.accounts set nexo_account_id = p_nexo_account_id
    where owner_id = v_row.owner_id and account_id = p_account_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ── App (signed-in person, one of their devices) ───────────────────────
-- One request at a time per dataset, oldest first. A request left half-done
-- by a device that stopped is offered again after five minutes; devices
-- make applying idempotent.
create or replace function public.nexo_mcp_claim(p_dataset_id uuid, p_device_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_row nexo_mcp_private.commands%rowtype;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('nexo_mcp_claim:' || p_dataset_id::text, 0));
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
  update nexo_mcp_private.commands set status = 'applying', device_id = p_device_id,
      claimed_at = now()
    where id = v_row.id;
  return jsonb_build_object('id', v_row.id, 'kind', v_row.kind, 'args', v_row.args,
    'created_at', v_row.created_at);
end;
$$;

create or replace function public.nexo_mcp_report_device(
  p_dataset_id uuid, p_device_id uuid, p_version text, p_kinds text[], p_settings jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_version is null or length(p_version) not between 1 and 40
      or p_kinds is null or cardinality(p_kinds) not between 1 and 200
      or exists (select 1 from unnest(p_kinds) k where k !~ '^[a-z]+\.[a-z_]+$')
      or (p_settings is not null and (jsonb_typeof(p_settings) <> 'object'
        or octet_length(p_settings::text) > 16384)) then
    raise exception using errcode = '22023', message = 'invalid_capabilities';
  end if;
  insert into nexo_mcp_private.capabilities(owner_id, dataset_id, device_id, app_version, kinds, settings, seen_at)
    values (v_user, p_dataset_id, p_device_id, p_version, p_kinds, p_settings, now())
  on conflict (owner_id, dataset_id, device_id) do update
    set app_version = excluded.app_version, kinds = excluded.kinds,
      settings = excluded.settings, seen_at = now();
end;
$$;

-- Requests of this dataset for the app's "Feito pelo Claude" list.
create or replace function public.nexo_mcp_history(p_dataset_id uuid, p_limit integer)
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(page.item order by page.created desc), '[]'::jsonb)
  from (select c.created_at as created, jsonb_build_object('id', c.id, 'kind', c.kind,
      'status', c.status, 'created_at', c.created_at, 'finished_at', c.finished_at,
      'connector', k.label, 'message', c.result->>'message', 'reason', c.result->>'reason',
      'undoable', c.status = 'done' and c.result ? 'undo'
        and not (c.result ? 'undone_at')
        and coalesce(c.result->'undo'->>'too_large', 'false') <> 'true',
      'undone_at', c.result->>'undone_at') as item
    from nexo_mcp_private.commands c
    join nexo_mcp_private.connectors k on k.id = c.connector_id
    where c.owner_id = (select auth.uid()) and c.dataset_id = p_dataset_id
    order by c.created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))) page;
$$;

-- What a request changed, for undoing it from the app.
create or replace function public.nexo_mcp_undo_data(p_id uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select c.result->'undo' from nexo_mcp_private.commands c
  where c.id = p_id and c.owner_id = (select auth.uid()) and c.status = 'done'
    and not (c.result ? 'undone_at');
$$;

create or replace function public.nexo_mcp_mark_undone(p_id uuid, p_by uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  update nexo_mcp_private.commands
    set result = coalesce(result, '{}'::jsonb)
      || jsonb_build_object('undone_at', now(), 'undone_by', p_by)
    where id = p_id and owner_id = v_user and status = 'done'
      and not (coalesce(result, '{}'::jsonb) ? 'undone_at');
end;
$$;

revoke all on function public.nexo_mcp_enqueue_v2(uuid, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.nexo_mcp_recent(uuid, integer) from public, anon, authenticated;
revoke all on function public.nexo_mcp_report_device(uuid, uuid, text, text[], jsonb) from public, anon;
revoke all on function public.nexo_mcp_history(uuid, integer) from public, anon;
revoke all on function public.nexo_mcp_undo_data(uuid) from public, anon;
revoke all on function public.nexo_mcp_mark_undone(uuid, uuid) from public, anon;
revoke all on function public.nexo_mcp_bank_accounts(uuid) from public, anon, authenticated;
revoke all on function public.nexo_mcp_link_bank_account(uuid, text, text) from public, anon, authenticated;
grant execute on function public.nexo_mcp_bank_accounts(uuid) to service_role;
grant execute on function public.nexo_mcp_link_bank_account(uuid, text, text) to service_role;
grant execute on function public.nexo_mcp_enqueue_v2(uuid, text, jsonb, text) to service_role;
grant execute on function public.nexo_mcp_recent(uuid, integer) to service_role;
grant execute on function public.nexo_mcp_report_device(uuid, uuid, text, text[], jsonb) to authenticated;
grant execute on function public.nexo_mcp_history(uuid, integer) to authenticated;
grant execute on function public.nexo_mcp_undo_data(uuid) to authenticated;
grant execute on function public.nexo_mcp_mark_undone(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
