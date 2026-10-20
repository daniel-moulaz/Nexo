-- Nexo: protocol 2 for the isolated synthetic lab. Never import real data.
-- Adds commutative balance effects, read requirements and a balance
-- projection. Protocol-1 payloads keep working unchanged.
begin;

create table nexo_sync_lab_private.balances (
  dataset_id uuid not null,
  owner_id uuid not null,
  account_id text not null check (length(account_id) between 1 and 256),
  micros bigint not null,
  primary key (dataset_id, account_id),
  foreign key (dataset_id, owner_id)
    references nexo_sync_lab_private.datasets(id, owner_id)
);
alter table nexo_sync_lab_private.balances enable row level security;
create policy owner_read on nexo_sync_lab_private.balances for select
  to authenticated using (owner_id = (select auth.uid()));
revoke all on nexo_sync_lab_private.balances from public, anon, authenticated;

create or replace function public.nexo_sync_lab_push(p_payload text, p_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_op jsonb;
  v_protocol int;
  v_dataset_id uuid;
  v_epoch uuid;
  v_device_id uuid;
  v_id uuid;
  v_time timestamptz;
  v_dataset nexo_sync_lab_private.datasets%rowtype;
  v_previous nexo_sync_lab_private.requests%rowtype;
  v_edit jsonb;
  v_effect jsonb;
  v_need jsonb;
  v_entity nexo_sync_lab_private.entities%rowtype;
  v_effects jsonb := '[]'::jsonb;
  v_requires jsonb := '[]'::jsonb;
  v_remote jsonb := '[]'::jsonb;
  v_mismatch boolean := false;
  v_result jsonb;
  v_revision bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_payload is null or octet_length(p_payload) > 1048576 or p_hash is null
      or p_hash <> encode(sha256(convert_to(p_payload, 'UTF8')), 'hex') then
    raise exception using errcode = '22023', message = 'invalid_payload_hash';
  end if;
  begin
    v_op := p_payload::jsonb;
    if jsonb_typeof(v_op) is distinct from 'object'
        or coalesce((v_op->'protocol') not in ('1'::jsonb, '2'::jsonb), true) then
      raise exception 'header';
    end if;
    v_protocol := (v_op->>'protocol')::int;
    v_dataset_id := (v_op->>'dataset_id')::uuid;
    v_epoch := (v_op->>'epoch')::uuid;
    v_device_id := (v_op->>'device_id')::uuid;
    v_id := (v_op->>'id')::uuid;
    v_time := (v_op->>'created_at')::timestamptz;
    if v_dataset_id is null or v_epoch is null or v_device_id is null
        or v_id is null or v_time is null or not isfinite(v_time) then
      raise exception 'header';
    end if;
    -- Version 1 cannot smuggle version-2 fields into the hashed payload.
    if v_protocol = 1 and (v_op ? 'effects' or v_op ? 'requires' or v_op ? 'label') then
      raise exception 'header';
    end if;
    if v_protocol = 2 and v_op ? 'label' and (jsonb_typeof(v_op->'label') is distinct from 'string'
        or length(v_op->>'label') not between 1 and 64) then
      raise exception 'header';
    end if;
  exception when others then
    raise exception using errcode = '22023', message = 'invalid_operation_header';
  end;
  if jsonb_typeof(v_op->'edits') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'invalid_edits';
  end if;
  if v_protocol = 2 then
    if jsonb_typeof(v_op->'effects') is distinct from 'array' then
      raise exception using errcode = '22023', message = 'invalid_effects';
    end if;
    if jsonb_typeof(v_op->'requires') is distinct from 'array' then
      raise exception using errcode = '22023', message = 'invalid_requires';
    end if;
    v_effects := v_op->'effects';
    v_requires := v_op->'requires';
  end if;
  if jsonb_array_length(v_op->'edits') > 10000
      or jsonb_array_length(v_effects) > 10000
      or jsonb_array_length(v_requires) > 10000
      or (jsonb_array_length(v_op->'edits') = 0 and
          (v_protocol = 1 or jsonb_array_length(v_effects) = 0)) then
    raise exception using errcode = '22023', message = 'invalid_edit_count';
  end if;
  for v_edit in select value from jsonb_array_elements(v_op->'edits') loop
    if jsonb_typeof(v_edit) is distinct from 'object'
        or jsonb_typeof(v_edit->'kind') is distinct from 'string'
        or jsonb_typeof(v_edit->'id') is distinct from 'string'
        or length(v_edit->>'kind') not between 1 and 256
        or length(v_edit->>'id') not between 1 and 256
        or jsonb_typeof(v_edit->'base_revision') is distinct from 'number'
        or (v_edit->>'base_revision') !~ '^(0|[1-9][0-9]{0,14})$'
        or not (v_edit ? 'value')
        or jsonb_typeof(v_edit->'value') not in ('object', 'null') then
      raise exception using errcode = '22023', message = 'invalid_edit';
    end if;
    if v_edit->'value' = 'null'::jsonb and v_edit->>'base_revision' = '0' then
      raise exception using errcode = '22023', message = 'delete_missing_entity';
    end if;
  end loop;
  for v_effect in select value from jsonb_array_elements(v_effects) loop
    if jsonb_typeof(v_effect) is distinct from 'object'
        or jsonb_typeof(v_effect->'account') is distinct from 'string'
        or length(v_effect->>'account') not between 1 and 256
        or jsonb_typeof(v_effect->'delta_micros') is distinct from 'number'
        or (v_effect->>'delta_micros') !~ '^-?[1-9][0-9]{0,15}$'
        or abs((v_effect->>'delta_micros')::numeric) > 9000000000000000 then
      raise exception using errcode = '22023', message = 'invalid_effect';
    end if;
  end loop;
  for v_need in select value from jsonb_array_elements(v_requires) loop
    if jsonb_typeof(v_need) is distinct from 'object'
        or jsonb_typeof(v_need->'kind') is distinct from 'string'
        or jsonb_typeof(v_need->'id') is distinct from 'string'
        or length(v_need->>'kind') not between 1 and 256
        or length(v_need->>'id') not between 1 and 256
        or jsonb_typeof(v_need->'revision') is distinct from 'number'
        or (v_need->>'revision') !~ '^(0|[1-9][0-9]{0,14})$' then
      raise exception using errcode = '22023', message = 'invalid_requirement';
    end if;
  end loop;
  -- An entity is either written or required, once.
  if (select count(distinct k) from (
        select jsonb_build_array(e->'kind', e->'id') as k
          from jsonb_array_elements(v_op->'edits') e
        union all
        select jsonb_build_array(r->'kind', r->'id')
          from jsonb_array_elements(v_requires) r) keys)
      <> jsonb_array_length(v_op->'edits') + jsonb_array_length(v_requires) then
    raise exception using errcode = '22023', message = 'duplicate_entity';
  end if;
  if (select count(distinct x->>'account') from jsonb_array_elements(v_effects) x)
      <> jsonb_array_length(v_effects) then
    raise exception using errcode = '22023', message = 'duplicate_effect';
  end if;
  select * into v_dataset from nexo_sync_lab_private.datasets
    where id = v_dataset_id and owner_id = v_user for update;
  if not found then
    raise exception using errcode = '42501', message = 'dataset_unavailable';
  end if;
  if v_dataset.epoch <> v_epoch then
    raise exception using errcode = '22023', message = 'epoch_mismatch';
  end if;
  if not exists(select 1 from nexo_sync_lab_private.devices where
      dataset_id = v_dataset_id and id = v_device_id and revoked_at is null) then
    raise exception using errcode = '42501', message = 'device_unavailable';
  end if;
  select * into v_previous from nexo_sync_lab_private.requests
    where dataset_id = v_dataset_id and id = v_id;
  if found then
    if v_previous.hash <> p_hash or v_previous.payload <> p_payload then
      raise exception using errcode = '22023', message = 'operation_id_reused';
    end if;
    return v_previous.result;
  end if;
  for v_edit in
      select jsonb_build_object('kind', e->'kind', 'id', e->'id',
        'expected', e->'base_revision') from jsonb_array_elements(v_op->'edits') e
      union all
      select jsonb_build_object('kind', r->'kind', 'id', r->'id',
        'expected', r->'revision') from jsonb_array_elements(v_requires) r loop
    v_entity := null;
    select * into v_entity from nexo_sync_lab_private.entities where
      dataset_id = v_dataset_id and kind = v_edit->>'kind' and id = v_edit->>'id';
    if coalesce(v_entity.revision, 0) <> (v_edit->>'expected')::bigint then
      v_mismatch := true;
    end if;
    v_remote := v_remote || jsonb_build_array(jsonb_build_object(
      'kind', v_edit->>'kind', 'id', v_edit->>'id',
      'revision', coalesce(v_entity.revision, 0), 'value', v_entity.value));
  end loop;
  if v_mismatch then
    v_result := jsonb_build_object('status', 'conflict', 'remote', v_remote);
    insert into nexo_sync_lab_private.requests
      (dataset_id, owner_id, id, hash, payload, result)
      values (v_dataset_id, v_user, v_id, p_hash, p_payload, v_result);
    return v_result;
  end if;
  for v_edit in select value from jsonb_array_elements(v_op->'edits') loop
    insert into nexo_sync_lab_private.entities
      (dataset_id, owner_id, kind, id, revision, value, updated_at, deleted_at, device_id)
      values (v_dataset_id, v_user, v_edit->>'kind', v_edit->>'id',
        (v_edit->>'base_revision')::bigint + 1, nullif(v_edit->'value', 'null'::jsonb),
        v_time, case when v_edit->'value' = 'null'::jsonb then now() end, v_device_id)
      on conflict (dataset_id, kind, id) do update set
        revision = excluded.revision, value = excluded.value,
        updated_at = excluded.updated_at, deleted_at = excluded.deleted_at,
        device_id = excluded.device_id;
  end loop;
  for v_effect in select value from jsonb_array_elements(v_effects) loop
    insert into nexo_sync_lab_private.balances(dataset_id, owner_id, account_id, micros)
      values (v_dataset_id, v_user, v_effect->>'account', (v_effect->>'delta_micros')::bigint)
      on conflict (dataset_id, account_id) do update
        set micros = nexo_sync_lab_private.balances.micros + excluded.micros;
  end loop;
  update nexo_sync_lab_private.datasets set revision = revision + 1
    where id = v_dataset_id returning revision into v_revision;
  v_result := jsonb_build_object('status', 'accepted', 'revision', v_revision,
    'payload', p_payload, 'hash', p_hash);
  insert into nexo_sync_lab_private.requests
    (dataset_id, owner_id, id, hash, payload, result, server_revision)
    values (v_dataset_id, v_user, v_id, p_hash, p_payload, v_result, v_revision);
  return v_result;
end;
$$;

revoke all on function public.nexo_sync_lab_push(text, text)
  from public, anon, authenticated;
grant execute on function public.nexo_sync_lab_push(text, text) to authenticated;

comment on table nexo_sync_lab_private.balances is
  'Protocol 2 balance projection (sum of effects). Synthetic lab only.';
notify pgrst, 'reload schema';
commit;
