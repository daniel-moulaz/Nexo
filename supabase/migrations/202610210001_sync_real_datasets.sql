-- Nexo: lets the owner keep one real dataset next to the synthetic lab ones,
-- with the same RLS, RPC-only access and protocol 2 rules. Real and synthetic
-- datasets never mix: each device opens only the kind it asked for.
begin;

alter table nexo_sync_lab_private.datasets
  drop constraint datasets_synthetic_only_check;
-- One real dataset per person: activating twice must not split the history.
create unique index datasets_one_real_per_owner
  on nexo_sync_lab_private.datasets(owner_id) where not synthetic_only;

-- Creates (first device) or opens (later devices) a dataset of the given
-- kind and registers this device in it.
create function public.nexo_sync_open(
  p_dataset_id uuid, p_epoch uuid, p_device_id uuid, p_real boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_dataset nexo_sync_lab_private.datasets%rowtype;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_dataset_id is null or p_epoch is null or p_device_id is null
      or p_real is null then
    raise exception using errcode = '22023', message = 'invalid_dataset';
  end if;
  if p_real and not exists(select 1 from nexo_sync_lab_private.datasets
      where id = p_dataset_id) and exists(select 1 from nexo_sync_lab_private.datasets
      where owner_id = v_user and not synthetic_only) then
    raise exception using errcode = '23505', message = 'real_dataset_exists';
  end if;
  insert into nexo_sync_lab_private.datasets(id, owner_id, epoch, synthetic_only)
    values (p_dataset_id, v_user, p_epoch, not p_real) on conflict (id) do nothing;
  select * into v_dataset from nexo_sync_lab_private.datasets
    where id = p_dataset_id and owner_id = v_user for update;
  if not found then
    raise exception using errcode = '42501', message = 'dataset_unavailable';
  end if;
  if v_dataset.epoch <> p_epoch then
    raise exception using errcode = '22023', message = 'epoch_mismatch';
  end if;
  if v_dataset.synthetic_only = p_real then
    raise exception using errcode = '22023', message = 'dataset_kind_mismatch';
  end if;
  if exists(select 1 from nexo_sync_lab_private.devices where
      dataset_id = p_dataset_id and id = p_device_id and revoked_at is not null) then
    raise exception using errcode = '42501', message = 'device_unavailable';
  end if;
  insert into nexo_sync_lab_private.devices(dataset_id, owner_id, id)
    values (p_dataset_id, v_user, p_device_id) on conflict do nothing;
  return jsonb_build_object('protocol', 2, 'dataset_id', p_dataset_id,
    'epoch', p_epoch, 'revision', v_dataset.revision, 'real', p_real);
end;
$$;

-- The lab entry point keeps its contract but can no longer register a
-- device into a real dataset.
create or replace function public.nexo_sync_lab_create(
  p_dataset_id uuid, p_epoch uuid, p_device_id uuid,
  p_synthetic_only boolean default false
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_dataset nexo_sync_lab_private.datasets%rowtype;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_synthetic_only is distinct from true or p_dataset_id is null
      or p_epoch is null or p_device_id is null then
    raise exception using errcode = '22023', message = 'synthetic_lab_required';
  end if;
  insert into nexo_sync_lab_private.datasets(id, owner_id, epoch, synthetic_only)
    values (p_dataset_id, v_user, p_epoch, true) on conflict (id) do nothing;
  select * into v_dataset from nexo_sync_lab_private.datasets
    where id = p_dataset_id and owner_id = v_user for update;
  if not found then
    raise exception using errcode = '42501', message = 'dataset_unavailable';
  end if;
  if not v_dataset.synthetic_only then
    raise exception using errcode = '22023', message = 'dataset_kind_mismatch';
  end if;
  if v_dataset.epoch <> p_epoch then
    raise exception using errcode = '22023', message = 'epoch_mismatch';
  end if;
  if exists(select 1 from nexo_sync_lab_private.devices where
      dataset_id = p_dataset_id and id = p_device_id and revoked_at is not null) then
    raise exception using errcode = '42501', message = 'device_unavailable';
  end if;
  insert into nexo_sync_lab_private.devices(dataset_id, owner_id, id)
    values (p_dataset_id, v_user, p_device_id) on conflict do nothing;
  return jsonb_build_object('protocol', 1, 'dataset_id', p_dataset_id,
    'epoch', p_epoch, 'revision', v_dataset.revision, 'synthetic_only', true);
end;
$$;

create function public.nexo_sync_list_datasets(p_real boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', d.id, 'epoch', d.epoch, 'label', d.label, 'revision', d.revision,
      'created_at', d.created_at, 'real', not d.synthetic_only,
      'devices', (select count(*) from nexo_sync_lab_private.devices v
        where v.dataset_id = d.id and v.revoked_at is null))
      order by d.created_at desc)
    from nexo_sync_lab_private.datasets d
    where d.owner_id = v_user and d.label is not null
      and d.synthetic_only = not coalesce(p_real, false)), '[]'::jsonb);
end;
$$;

-- Removes the server copy of one dataset of the caller. Devices keep their
-- local data; they stop syncing because the dataset no longer exists.
create function public.nexo_sync_delete_dataset(p_dataset_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  perform 1 from nexo_sync_lab_private.datasets
    where id = p_dataset_id and owner_id = v_user for update;
  if not found then
    raise exception using errcode = '42501', message = 'dataset_unavailable';
  end if;
  if to_regclass('nexo_mcp_private.connectors') is not null then
    execute 'delete from nexo_mcp_private.audit where connector_id in
      (select id from nexo_mcp_private.connectors where dataset_id = $1)'
      using p_dataset_id;
    execute 'delete from nexo_mcp_private.connectors where dataset_id = $1'
      using p_dataset_id;
  end if;
  delete from nexo_sync_lab_private.balances where dataset_id = p_dataset_id;
  delete from nexo_sync_lab_private.requests where dataset_id = p_dataset_id;
  delete from nexo_sync_lab_private.entities where dataset_id = p_dataset_id;
  delete from nexo_sync_lab_private.devices where dataset_id = p_dataset_id;
  delete from nexo_sync_lab_private.datasets where id = p_dataset_id;
end;
$$;

revoke all on function public.nexo_sync_open(uuid, uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.nexo_sync_list_datasets(boolean) from public, anon, authenticated;
revoke all on function public.nexo_sync_delete_dataset(uuid) from public, anon, authenticated;
grant execute on function public.nexo_sync_open(uuid, uuid, uuid, boolean) to authenticated;
grant execute on function public.nexo_sync_list_datasets(boolean) to authenticated;
grant execute on function public.nexo_sync_delete_dataset(uuid) to authenticated;

comment on schema nexo_sync_lab_private is
  'Nexo sync store: synthetic lab datasets and at most one real dataset per owner.';

notify pgrst, 'reload schema';
commit;
