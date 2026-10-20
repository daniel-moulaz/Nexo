-- Protocol 2 smoke test. Run as project administrator in the SQL Editor after
-- 202610200001_sync_protocol_v2.sql. Fictitious identities and amounts only;
-- every write rolls back. Simulated claims test DB rules, not an Auth login.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
do $$
declare
  ds uuid := '20000000-0000-4000-8000-000000000001';
  ep uuid := '20000000-0000-4000-8000-000000000002';
  phone uuid := '20000000-0000-4000-8000-000000000003';
  pc uuid := '20000000-0000-4000-8000-000000000004';
  payload text; result jsonb; rejected boolean := false;
begin
  perform public.nexo_sync_lab_create(ds, ep, phone, true);
  perform public.nexo_sync_lab_create(ds, ep, pc, true);

  -- Opening: the account and its starting balance travel together.
  payload := jsonb_build_object('protocol', 2, 'id', '20000000-0000-4000-8000-000000000010',
    'dataset_id', ds, 'epoch', ep, 'device_id', phone, 'created_at', '2026-10-20T12:00:00.000Z',
    'label', 'bootstrap.checkpoint',
    'edits', jsonb_build_array(jsonb_build_object('kind', 'accounts', 'id', 'smoke-bank',
      'base_revision', 0, 'value', jsonb_build_object('name', 'Banco fictício'))),
    'effects', jsonb_build_array(jsonb_build_object('account', 'smoke-bank', 'delta_micros', 1000000000)),
    'requires', '[]'::jsonb)::text;
  result := public.nexo_sync_lab_push(payload, encode(sha256(convert_to(payload, 'UTF8')), 'hex'));
  if result->>'status' <> 'accepted' then raise exception 'smoke_v2_opening_failed'; end if;

  -- Two devices spend from the same account: both must be accepted.
  payload := jsonb_build_object('protocol', 2, 'id', '20000000-0000-4000-8000-000000000011',
    'dataset_id', ds, 'epoch', ep, 'device_id', phone, 'created_at', '2026-10-20T12:01:00.000Z',
    'label', 'transaction.add',
    'edits', jsonb_build_array(jsonb_build_object('kind', 'transactions', 'id', 'smoke-t1',
      'base_revision', 0, 'value', jsonb_build_object('amount', 7.5))),
    'effects', jsonb_build_array(jsonb_build_object('account', 'smoke-bank', 'delta_micros', -7500000)),
    'requires', jsonb_build_array(jsonb_build_object('kind', 'accounts', 'id', 'smoke-bank', 'revision', 1)))::text;
  if public.nexo_sync_lab_push(payload, encode(sha256(convert_to(payload, 'UTF8')), 'hex'))->>'status' <> 'accepted' then
    raise exception 'smoke_v2_phone_spend_failed'; end if;
  payload := jsonb_build_object('protocol', 2, 'id', '20000000-0000-4000-8000-000000000012',
    'dataset_id', ds, 'epoch', ep, 'device_id', pc, 'created_at', '2026-10-20T12:02:00.000Z',
    'label', 'transaction.add',
    'edits', jsonb_build_array(jsonb_build_object('kind', 'transactions', 'id', 'smoke-t2',
      'base_revision', 0, 'value', jsonb_build_object('amount', 0.3))),
    'effects', jsonb_build_array(jsonb_build_object('account', 'smoke-bank', 'delta_micros', -300000)),
    'requires', jsonb_build_array(jsonb_build_object('kind', 'accounts', 'id', 'smoke-bank', 'revision', 1)))::text;
  if public.nexo_sync_lab_push(payload, encode(sha256(convert_to(payload, 'UTF8')), 'hex'))->>'status' <> 'accepted' then
    raise exception 'smoke_v2_concurrent_spend_conflicted'; end if;

  -- The account changes; a spend still relying on revision 1 must conflict.
  payload := jsonb_build_object('protocol', 2, 'id', '20000000-0000-4000-8000-000000000013',
    'dataset_id', ds, 'epoch', ep, 'device_id', phone, 'created_at', '2026-10-20T12:03:00.000Z',
    'edits', jsonb_build_array(jsonb_build_object('kind', 'accounts', 'id', 'smoke-bank',
      'base_revision', 1, 'value', jsonb_build_object('name', 'Banco renomeado'))),
    'effects', '[]'::jsonb, 'requires', '[]'::jsonb)::text;
  if public.nexo_sync_lab_push(payload, encode(sha256(convert_to(payload, 'UTF8')), 'hex'))->>'status' <> 'accepted' then
    raise exception 'smoke_v2_rename_failed'; end if;
  payload := jsonb_build_object('protocol', 2, 'id', '20000000-0000-4000-8000-000000000014',
    'dataset_id', ds, 'epoch', ep, 'device_id', pc, 'created_at', '2026-10-20T12:04:00.000Z',
    'edits', jsonb_build_array(jsonb_build_object('kind', 'transactions', 'id', 'smoke-t3',
      'base_revision', 0, 'value', jsonb_build_object('amount', 1))),
    'effects', jsonb_build_array(jsonb_build_object('account', 'smoke-bank', 'delta_micros', -1000000)),
    'requires', jsonb_build_array(jsonb_build_object('kind', 'accounts', 'id', 'smoke-bank', 'revision', 1)))::text;
  result := public.nexo_sync_lab_push(payload, encode(sha256(convert_to(payload, 'UTF8')), 'hex'));
  if result->>'status' <> 'conflict' or jsonb_array_length(result->'remote') <> 2 then
    raise exception 'smoke_v2_stale_requirement_accepted'; end if;

  -- Malformed effect is refused.
  begin
    payload := jsonb_build_object('protocol', 2, 'id', '20000000-0000-4000-8000-000000000015',
      'dataset_id', ds, 'epoch', ep, 'device_id', pc, 'created_at', '2026-10-20T12:05:00.000Z',
      'edits', '[]'::jsonb, 'requires', '[]'::jsonb,
      'effects', jsonb_build_array(jsonb_build_object('account', 'smoke-bank', 'delta_micros', 0)))::text;
    perform public.nexo_sync_lab_push(payload, encode(sha256(convert_to(payload, 'UTF8')), 'hex'));
  exception when invalid_parameter_value then rejected := true; end;
  if not rejected then raise exception 'smoke_v2_zero_effect_accepted'; end if;

  if jsonb_array_length(public.nexo_sync_lab_pull(ds, ep, pc, 0, 100)) <> 4 then
    raise exception 'smoke_v2_pull_failed'; end if;

  -- Another user cannot read this dataset.
  perform set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
  rejected := false;
  begin perform public.nexo_sync_lab_pull(ds, ep, pc, 0, 100);
  exception when insufficient_privilege then rejected := true; end;
  if not rejected then raise exception 'smoke_v2_cross_user_leak'; end if;
end;
$$;
reset role;
-- Balance projection: 1000 - 7.50 - 0.30, the conflicting spend not applied.
do $$
begin
  if (select micros from nexo_sync_lab_private.balances
      where dataset_id = '20000000-0000-4000-8000-000000000001' and account_id = 'smoke-bank')
      <> 992200000 then
    raise exception 'smoke_v2_balance_projection_wrong';
  end if;
end;
$$;
rollback;

select 'synthetic_v2_smoke_passed' as validation,
  (select count(*) from nexo_sync_lab_private.datasets
    where id = '20000000-0000-4000-8000-000000000001') as persisted_datasets,
  (select count(*) from nexo_sync_lab_private.balances
    where dataset_id = '20000000-0000-4000-8000-000000000001') as persisted_balances,
  (select bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'nexo_sync_lab_private' and relkind = 'r') as all_rls_enabled;
