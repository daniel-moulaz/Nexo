-- Nexo: isolated protocol lab. Never import a real financial dataset here.
-- Apply once to the dedicated project; the transaction fails closed on reapply.
begin;

create schema nexo_sync_lab_private;
revoke all on schema nexo_sync_lab_private from public, anon, authenticated;

create table nexo_sync_lab_private.datasets (
  id uuid primary key,
  owner_id uuid not null,
  epoch uuid not null,
  revision bigint not null default 0 check (revision >= 0),
  synthetic_only boolean not null check (synthetic_only),
  created_at timestamptz not null default now(),
  unique (id, owner_id)
);
create table nexo_sync_lab_private.devices (
  dataset_id uuid not null,
  owner_id uuid not null,
  id uuid not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (dataset_id, id),
  foreign key (dataset_id, owner_id)
    references nexo_sync_lab_private.datasets(id, owner_id)
);
create table nexo_sync_lab_private.entities (
  dataset_id uuid not null,
  owner_id uuid not null,
  kind text not null check (length(kind) between 1 and 256),
  id text not null check (length(id) between 1 and 256),
  revision bigint not null check (revision > 0),
  value jsonb,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  device_id uuid not null,
  primary key (dataset_id, kind, id),
  foreign key (dataset_id, owner_id)
    references nexo_sync_lab_private.datasets(id, owner_id),
  foreign key (dataset_id, device_id)
    references nexo_sync_lab_private.devices(dataset_id, id)
);
create table nexo_sync_lab_private.requests (
  dataset_id uuid not null,
  owner_id uuid not null,
  id uuid not null,
  hash text not null check (hash ~ '^[0-9a-f]{64}$'),
  payload text not null check (octet_length(payload) <= 1048576),
  result jsonb not null,
  server_revision bigint,
  created_at timestamptz not null default now(),
  primary key (dataset_id, id),
  unique (dataset_id, server_revision),
  foreign key (dataset_id, owner_id)
    references nexo_sync_lab_private.datasets(id, owner_id)
);

alter table nexo_sync_lab_private.datasets enable row level security;
alter table nexo_sync_lab_private.devices enable row level security;
alter table nexo_sync_lab_private.entities enable row level security;
alter table nexo_sync_lab_private.requests enable row level security;
create policy owner_read on nexo_sync_lab_private.datasets for select
  to authenticated using (owner_id = (select auth.uid()));
create policy owner_read on nexo_sync_lab_private.devices for select
  to authenticated using (owner_id = (select auth.uid()));
create policy owner_read on nexo_sync_lab_private.entities for select
  to authenticated using (owner_id = (select auth.uid()));
create policy owner_read on nexo_sync_lab_private.requests for select
  to authenticated using (owner_id = (select auth.uid()));
-- No direct client grants or mutation policies. Only the four scoped RPCs.
revoke all on all tables in schema nexo_sync_lab_private
  from public, anon, authenticated;

create function public.nexo_sync_lab_create(
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

create function public.nexo_sync_lab_push(p_payload text, p_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_op jsonb;
  v_dataset_id uuid;
  v_epoch uuid;
  v_device_id uuid;
  v_id uuid;
  v_time timestamptz;
  v_dataset nexo_sync_lab_private.datasets%rowtype;
  v_previous nexo_sync_lab_private.requests%rowtype;
  v_edit jsonb;
  v_entity nexo_sync_lab_private.entities%rowtype;
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
        or (v_op->'protocol') is distinct from '1'::jsonb then
      raise exception 'header';
    end if;
    v_dataset_id := (v_op->>'dataset_id')::uuid;
    v_epoch := (v_op->>'epoch')::uuid;
    v_device_id := (v_op->>'device_id')::uuid;
    v_id := (v_op->>'id')::uuid;
    v_time := (v_op->>'created_at')::timestamptz;
    if v_dataset_id is null or v_epoch is null or v_device_id is null
        or v_id is null or v_time is null or not isfinite(v_time) then
      raise exception 'header';
    end if;
  exception when others then
    raise exception using errcode = '22023', message = 'invalid_operation_header';
  end;
  if jsonb_typeof(v_op->'edits') is distinct from 'array' then
    raise exception using errcode = '22023', message = 'invalid_edits';
  end if;
  if jsonb_array_length(v_op->'edits') not between 1 and 10000 then
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
  if (select count(distinct jsonb_build_array(e->'kind', e->'id'))
      from jsonb_array_elements(v_op->'edits') e)
      <> jsonb_array_length(v_op->'edits') then
    raise exception using errcode = '22023', message = 'duplicate_entity';
  end if;
  -- Serialize commits per dataset, never use a sequence as a pull cursor.
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
  for v_edit in select value from jsonb_array_elements(v_op->'edits') loop
    select * into v_entity from nexo_sync_lab_private.entities where
      dataset_id = v_dataset_id and kind = v_edit->>'kind' and id = v_edit->>'id';
    if coalesce(v_entity.revision, 0) <> (v_edit->>'base_revision')::bigint then
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

create function public.nexo_sync_lab_pull(
  p_dataset_id uuid, p_epoch uuid, p_device_id uuid,
  p_after bigint, p_limit integer default 100
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_dataset nexo_sync_lab_private.datasets%rowtype;
  v_page jsonb;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_after is null or p_after < 0 or p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'invalid_page';
  end if;
  select * into v_dataset from nexo_sync_lab_private.datasets
    where id = p_dataset_id and owner_id = v_user;
  if not found then
    raise exception using errcode = '42501', message = 'dataset_unavailable';
  end if;
  if p_epoch is null or v_dataset.epoch <> p_epoch or p_after > v_dataset.revision then
    raise exception using errcode = '22023', message = 'epoch_or_cursor_mismatch';
  end if;
  if not exists(select 1 from nexo_sync_lab_private.devices where
      dataset_id = p_dataset_id and id = p_device_id and revoked_at is null) then
    raise exception using errcode = '42501', message = 'device_unavailable';
  end if;
  select coalesce(jsonb_agg(page.result order by page.server_revision), '[]'::jsonb)
    into v_page from (select result, server_revision from nexo_sync_lab_private.requests
      where dataset_id = p_dataset_id and server_revision > p_after
      order by server_revision limit p_limit) page;
  return v_page;
end;
$$;

create function public.nexo_sync_lab_revoke_device(p_dataset_id uuid, p_device_id uuid)
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
  update nexo_sync_lab_private.devices set revoked_at = coalesce(revoked_at, now())
    where dataset_id = p_dataset_id and id = p_device_id;
end;
$$;

revoke all on function public.nexo_sync_lab_create(uuid, uuid, uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.nexo_sync_lab_push(text, text)
  from public, anon, authenticated;
revoke all on function public.nexo_sync_lab_pull(uuid, uuid, uuid, bigint, integer)
  from public, anon, authenticated;
revoke all on function public.nexo_sync_lab_revoke_device(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.nexo_sync_lab_create(uuid, uuid, uuid, boolean) to authenticated;
grant execute on function public.nexo_sync_lab_push(text, text) to authenticated;
grant execute on function public.nexo_sync_lab_pull(uuid, uuid, uuid, bigint, integer) to authenticated;
grant execute on function public.nexo_sync_lab_revoke_device(uuid, uuid) to authenticated;

comment on schema nexo_sync_lab_private is
  'Nexo protocol 1 synthetic lab. Not integrated with production financial data.';
notify pgrst, 'reload schema';
commit;
