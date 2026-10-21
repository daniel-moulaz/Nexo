-- Nexo: Pluggy (Meu Pluggy) connections and reviewable suggestions.
-- A suggestion never becomes money by itself: the app turns it into a
-- transaction only after the person reviews it. The bank refreshing its data
-- never rewrites a decision already taken. Pluggy secrets stay in Edge
-- Function secrets; nothing here stores them.
begin;

create schema nexo_pluggy_private;
revoke all on schema nexo_pluggy_private from public, anon, authenticated;

create table nexo_pluggy_private.items (
  owner_id uuid not null,
  item_id text not null check (item_id ~ '^[0-9A-Za-z-]{8,64}$'),
  label text not null check (length(label) between 1 and 60),
  health jsonb,
  last_fetch_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (owner_id, item_id)
);
create table nexo_pluggy_private.suggestions (
  owner_id uuid not null,
  external_id text not null check (external_id ~ '^pluggy:[0-9A-Za-z-]{1,64}$'),
  item_id text not null,
  account_external_id text not null,
  amount_cents bigint not null check (amount_cents between 1 and 100000000000),
  kind text not null check (kind in ('income', 'expense', 'refund', 'transfer')),
  medium text not null check (medium in ('bank', 'credit')),
  description text not null check (length(description) between 1 and 80),
  occurred_at bigint not null,
  settled boolean not null,
  installment text,
  source_updated_at text not null,
  review text not null default 'pending'
    check (review in ('pending', 'confirmed', 'ignored')),
  transaction_id text,
  -- The bank changed amount, kind or date after the person decided.
  changed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (owner_id, external_id),
  foreign key (owner_id, item_id) references nexo_pluggy_private.items(owner_id, item_id)
    on delete cascade
);
create index suggestions_recent on nexo_pluggy_private.suggestions(owner_id, occurred_at);

alter table nexo_pluggy_private.items enable row level security;
alter table nexo_pluggy_private.suggestions enable row level security;
create policy owner_read on nexo_pluggy_private.items for select
  to authenticated using (owner_id = (select auth.uid()));
create policy owner_read on nexo_pluggy_private.suggestions for select
  to authenticated using (owner_id = (select auth.uid()));
revoke all on all tables in schema nexo_pluggy_private from public, anon, authenticated;

-- ── App (signed-in person) ──────────────────────────────────────────────
create function public.nexo_pluggy_add_item(p_item_id text, p_label text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_item_id is null or p_item_id !~ '^[0-9A-Za-z-]{8,64}$' then
    raise exception using errcode = '22023', message = 'invalid_item';
  end if;
  if p_label is null or length(trim(p_label)) not between 1 and 60 then
    raise exception using errcode = '22023', message = 'invalid_label';
  end if;
  if (select count(*) from nexo_pluggy_private.items where owner_id = v_user) >= 5
      and not exists(select 1 from nexo_pluggy_private.items
        where owner_id = v_user and item_id = p_item_id) then
    raise exception using errcode = '22023', message = 'too_many_items';
  end if;
  insert into nexo_pluggy_private.items(owner_id, item_id, label)
    values (v_user, p_item_id, trim(p_label))
    on conflict (owner_id, item_id) do update set label = excluded.label;
end;
$$;

-- Removing a connection drops its suggestions; transactions already
-- registered in the app stay untouched.
create function public.nexo_pluggy_remove_item(p_item_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  delete from nexo_pluggy_private.items where owner_id = v_user and item_id = p_item_id;
end;
$$;

create function public.nexo_pluggy_items()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'item_id', item_id, 'label', label, 'health', health,
      'last_fetch_at', last_fetch_at) order by created_at)
    from nexo_pluggy_private.items where owner_id = v_user), '[]'::jsonb);
end;
$$;

-- Suggestions that happened since p_since_ms (pending and decided), so every
-- device can clear what another device already resolved.
create function public.nexo_pluggy_suggestions(p_since_ms bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_since_ms is null or p_since_ms < 0 then
    raise exception using errcode = '22023', message = 'invalid_page';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', external_id, 'item_id', item_id, 'amount_cents', amount_cents,
      'kind', kind, 'medium', medium, 'description', description,
      'occurred_at', occurred_at, 'settled', settled,
      'installment', installment, 'review', review, 'changed', changed)
      order by occurred_at desc)
    from (select * from nexo_pluggy_private.suggestions
      where owner_id = v_user and occurred_at >= p_since_ms
      order by occurred_at desc limit 2000) s), '[]'::jsonb);
end;
$$;

-- Decisions taken on a device: pending → confirmed/ignored, ignored → pending
-- (undo). A confirmed suggestion is final. Repeating a decision is harmless.
create function public.nexo_pluggy_decide(p_decisions jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_item jsonb;
  v_changed integer := 0;
  v_count integer;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_decisions is null or jsonb_typeof(p_decisions) <> 'array'
      or jsonb_array_length(p_decisions) > 500 then
    raise exception using errcode = '22023', message = 'invalid_decisions';
  end if;
  for v_item in select * from jsonb_array_elements(p_decisions) loop
    if jsonb_typeof(v_item) <> 'object' or (v_item->>'id') is null
        or (v_item->>'review') not in ('pending', 'confirmed', 'ignored') then
      raise exception using errcode = '22023', message = 'invalid_decisions';
    end if;
    update nexo_pluggy_private.suggestions set
        review = v_item->>'review',
        transaction_id = case when v_item->>'review' = 'confirmed'
          then left(v_item->>'transaction_id', 256) else null end,
        updated_at = now()
      where owner_id = v_user and external_id = v_item->>'id'
        and review <> 'confirmed' and review <> v_item->>'review'
        and (v_item->>'review' <> 'pending' or review = 'ignored');
    get diagnostics v_count = row_count;
    v_changed := v_changed + v_count;
  end loop;
  return v_changed;
end;
$$;

-- ── Edge Function (service role) ────────────────────────────────────────
create function public.nexo_pluggy_owner_items(p_owner uuid)
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('item_id', item_id,
    'label', label, 'last_fetch_at', last_fetch_at) order by created_at), '[]'::jsonb)
  from nexo_pluggy_private.items where owner_id = p_owner;
$$;

create function public.nexo_pluggy_stored(p_owner uuid, p_ids text[])
returns jsonb language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'external_id', external_id, 'account_external_id', account_external_id,
    'item_id', item_id, 'amount_cents', amount_cents, 'kind', kind,
    'medium', medium, 'description', description, 'occurred_at', occurred_at,
    'settled', settled, 'installment', installment,
    'source_updated_at', source_updated_at, 'review', review)), '[]'::jsonb)
  from nexo_pluggy_private.suggestions
  where owner_id = p_owner and external_id = any(p_ids);
$$;

-- Applies the actions computed by the tested merge rules. Guards repeat the
-- rules so a decision taken meanwhile on a device is never overwritten.
create function public.nexo_pluggy_store(
  p_owner uuid, p_item_id text, p_health jsonb, p_rows jsonb
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_row jsonb;
  v_written integer := 0;
  v_count integer;
begin
  if not exists(select 1 from nexo_pluggy_private.items
      where owner_id = p_owner and item_id = p_item_id) then
    raise exception using errcode = '42501', message = 'item_unavailable';
  end if;
  update nexo_pluggy_private.items set health = p_health, last_fetch_at = now()
    where owner_id = p_owner and item_id = p_item_id;
  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if v_row->>'action' = 'insert' then
      insert into nexo_pluggy_private.suggestions(owner_id, external_id, item_id,
          account_external_id, amount_cents, kind, medium, description,
          occurred_at, settled, installment, source_updated_at)
        values (p_owner, v_row->>'external_id', p_item_id,
          v_row->>'account_external_id', (v_row->>'amount_cents')::bigint,
          v_row->>'kind', v_row->>'medium', v_row->>'description',
          (v_row->>'occurred_at')::bigint, (v_row->>'settled')::boolean,
          v_row->>'installment', v_row->>'source_updated_at')
        on conflict (owner_id, external_id) do nothing;
    elsif v_row->>'action' = 'update' then
      update nexo_pluggy_private.suggestions set
          amount_cents = (v_row->>'amount_cents')::bigint, kind = v_row->>'kind',
          medium = v_row->>'medium', description = v_row->>'description',
          occurred_at = (v_row->>'occurred_at')::bigint,
          settled = (v_row->>'settled')::boolean, installment = v_row->>'installment',
          source_updated_at = v_row->>'source_updated_at', updated_at = now()
        where owner_id = p_owner and external_id = v_row->>'external_id'
          and review = 'pending' and source_updated_at < v_row->>'source_updated_at';
    elsif v_row->>'action' = 'flag_changed' then
      update nexo_pluggy_private.suggestions set changed = true,
          source_updated_at = v_row->>'source_updated_at', updated_at = now()
        where owner_id = p_owner and external_id = v_row->>'external_id'
          and review <> 'pending' and source_updated_at < v_row->>'source_updated_at';
    else
      raise exception using errcode = '22023', message = 'invalid_action';
    end if;
    get diagnostics v_count = row_count;
    v_written := v_written + v_count;
  end loop;
  return v_written;
end;
$$;

revoke all on function public.nexo_pluggy_add_item(text, text) from public, anon, authenticated;
revoke all on function public.nexo_pluggy_remove_item(text) from public, anon, authenticated;
revoke all on function public.nexo_pluggy_items() from public, anon, authenticated;
revoke all on function public.nexo_pluggy_suggestions(bigint) from public, anon, authenticated;
revoke all on function public.nexo_pluggy_decide(jsonb) from public, anon, authenticated;
revoke all on function public.nexo_pluggy_owner_items(uuid) from public, anon, authenticated;
revoke all on function public.nexo_pluggy_stored(uuid, text[]) from public, anon, authenticated;
revoke all on function public.nexo_pluggy_store(uuid, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.nexo_pluggy_add_item(text, text) to authenticated;
grant execute on function public.nexo_pluggy_remove_item(text) to authenticated;
grant execute on function public.nexo_pluggy_items() to authenticated;
grant execute on function public.nexo_pluggy_suggestions(bigint) to authenticated;
grant execute on function public.nexo_pluggy_decide(jsonb) to authenticated;
grant execute on function public.nexo_pluggy_owner_items(uuid) to service_role;
grant execute on function public.nexo_pluggy_stored(uuid, text[]) to service_role;
grant execute on function public.nexo_pluggy_store(uuid, text, jsonb, jsonb) to service_role;

notify pgrst, 'reload schema';
commit;
