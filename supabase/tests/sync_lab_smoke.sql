-- Run as project administrator in the SQL Editor. All sample writes roll back.
-- Fake subjects test DB authorization; this does NOT test an actual Auth login.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
do $$
declare
  ds uuid := '10000000-0000-4000-8000-000000000001';
  ep uuid := '10000000-0000-4000-8000-000000000002';
  dev uuid := '10000000-0000-4000-8000-000000000003';
  payload text; digest text; result jsonb; rejected boolean := false;
begin
  result := public.nexo_sync_lab_create(ds, ep, dev, true);
  if result->>'synthetic_only' <> 'true' then raise exception 'smoke_create_failed'; end if;
  payload := jsonb_build_object('protocol', 1, 'id', '10000000-0000-4000-8000-000000000004',
    'dataset_id', ds, 'epoch', ep, 'device_id', dev, 'created_at', '2026-10-16T12:00:00.000Z',
    'edits', jsonb_build_array(
      jsonb_build_object('kind', 'account', 'id', 'bank-test', 'base_revision', 0, 'value', jsonb_build_object('balance', 1000)),
      jsonb_build_object('kind', 'account', 'id', 'reserve-test', 'base_revision', 0, 'value', jsonb_build_object('balance', 0))
    ))::text;
  digest := encode(sha256(convert_to(payload, 'UTF8')), 'hex');
  result := public.nexo_sync_lab_push(payload, digest);
  if result->>'revision' <> '1' or result->>'status' <> 'accepted' then raise exception 'smoke_push_failed'; end if;
  if public.nexo_sync_lab_push(payload, digest) <> result then raise exception 'smoke_retry_failed'; end if;
  payload := jsonb_set(payload::jsonb, '{id}', '"10000000-0000-4000-8000-000000000005"')::text;
  if public.nexo_sync_lab_push(payload, encode(sha256(convert_to(payload, 'UTF8')), 'hex'))->>'status' <> 'conflict' then
    raise exception 'smoke_conflict_failed'; end if;
  if jsonb_array_length(public.nexo_sync_lab_pull(ds, ep, dev, 0, 100)) <> 1 then raise exception 'smoke_pull_failed'; end if;
  perform set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
  begin perform public.nexo_sync_lab_pull(ds, ep, dev, 0, 100);
  exception when insufficient_privilege then rejected := true; end;
  if not rejected then raise exception 'smoke_cross_user_leak'; end if;
  rejected := false;
  begin perform public.nexo_sync_lab_create(ds, ep, dev, true);
  exception when insufficient_privilege then rejected := true; end;
  if not rejected then raise exception 'smoke_owner_takeover'; end if;
  perform set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  perform public.nexo_sync_lab_revoke_device(ds, dev);
  rejected := false;
  begin perform public.nexo_sync_lab_pull(ds, ep, dev, 0, 100);
  exception when insufficient_privilege then rejected := true; end;
  if not rejected then raise exception 'smoke_revocation_failed'; end if;
end;
$$;
reset role;
rollback;

select 'synthetic_smoke_passed' as validation,
  (select count(*) from nexo_sync_lab_private.datasets) as persisted_datasets,
  (select count(*) from nexo_sync_lab_private.entities) as persisted_entities,
  (select count(*) from nexo_sync_lab_private.requests) as persisted_requests,
  (select bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'nexo_sync_lab_private' and relkind = 'r') as all_rls_enabled,
  (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE')) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'nexo_sync_lab_%') as anonymous_blocked;
