-- Nexo: latest balance and card limit of each Open Finance account, and when
-- the bank data was refreshed, so the app can say "dados do banco até…" and
-- compare the bank balance with the Nexo balance. Account numbers, owner
-- names and tax numbers are never stored. Each bank account can be linked to
-- a Nexo account (the link is the same on every device). Nothing here moves
-- money: adjusting a balance is always confirmed in the app.
begin;

alter table nexo_pluggy_private.items add column if not exists bank_updated_at timestamptz;

create table if not exists nexo_pluggy_private.accounts (
  owner_id uuid not null,
  item_id text not null,
  account_id text not null check (account_id ~ '^[0-9A-Za-z-]{1,64}$'),
  type text not null check (type in ('BANK', 'CREDIT')),
  subtype text not null default '' check (length(subtype) <= 40),
  name text not null check (length(name) between 1 and 60),
  currency text not null default 'BRL' check (length(currency) = 3),
  balance_cents bigint,
  credit_limit_cents bigint,
  available_cents bigint,
  minimum_payment_cents bigint,
  close_date date,
  due_date date,
  nexo_account_id text check (nexo_account_id is null or length(nexo_account_id) between 1 and 128),
  fetched_at timestamptz not null default now(),
  primary key (owner_id, account_id),
  foreign key (owner_id, item_id) references nexo_pluggy_private.items(owner_id, item_id) on delete cascade
);
alter table nexo_pluggy_private.accounts enable row level security;

-- Called by pluggy-sync (service role) after reading an item.
create or replace function public.nexo_pluggy_store_accounts(
  p_owner uuid, p_item_id text, p_bank_updated_at timestamptz, p_accounts jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare v_row jsonb;
begin
  if not exists(select 1 from nexo_pluggy_private.items
      where owner_id = p_owner and item_id = p_item_id) then
    raise exception using errcode = '42501', message = 'item_unavailable';
  end if;
  if p_accounts is null or jsonb_typeof(p_accounts) <> 'array' or jsonb_array_length(p_accounts) > 50 then
    raise exception using errcode = '22023', message = 'invalid_accounts';
  end if;
  update nexo_pluggy_private.items set bank_updated_at = coalesce(p_bank_updated_at, bank_updated_at)
    where owner_id = p_owner and item_id = p_item_id;
  for v_row in select * from jsonb_array_elements(p_accounts) loop
    insert into nexo_pluggy_private.accounts(owner_id, item_id, account_id, type, subtype, name,
        currency, balance_cents, credit_limit_cents, available_cents, minimum_payment_cents,
        close_date, due_date, fetched_at)
      values (p_owner, p_item_id, v_row->>'account_id', v_row->>'type', coalesce(v_row->>'subtype', ''),
        v_row->>'name', coalesce(v_row->>'currency', 'BRL'),
        (v_row->>'balance_cents')::bigint, (v_row->>'credit_limit_cents')::bigint,
        (v_row->>'available_cents')::bigint, (v_row->>'minimum_payment_cents')::bigint,
        (v_row->>'close_date')::date, (v_row->>'due_date')::date, now())
    on conflict (owner_id, account_id) do update set
      item_id = excluded.item_id, type = excluded.type, subtype = excluded.subtype,
      name = excluded.name, currency = excluded.currency, balance_cents = excluded.balance_cents,
      credit_limit_cents = excluded.credit_limit_cents, available_cents = excluded.available_cents,
      minimum_payment_cents = excluded.minimum_payment_cents, close_date = excluded.close_date,
      due_date = excluded.due_date, fetched_at = now();
      -- nexo_account_id (the person's link) is kept.
  end loop;
end;
$$;

-- The person's accounts, with the item label and when the bank was read.
create or replace function public.nexo_pluggy_accounts()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'account_id', a.account_id, 'item_id', a.item_id, 'bank', i.label,
      'type', a.type, 'subtype', a.subtype, 'name', a.name, 'currency', a.currency,
      'balance_cents', a.balance_cents, 'credit_limit_cents', a.credit_limit_cents,
      'available_cents', a.available_cents, 'minimum_payment_cents', a.minimum_payment_cents,
      'close_date', a.close_date, 'due_date', a.due_date,
      'nexo_account_id', a.nexo_account_id,
      'bank_updated_at', i.bank_updated_at, 'fetched_at', a.fetched_at)
    order by i.created_at, a.type, a.name)
    from nexo_pluggy_private.accounts a
    join nexo_pluggy_private.items i on i.owner_id = a.owner_id and i.item_id = a.item_id
    where a.owner_id = v_user), '[]'::jsonb);
end;
$$;

create or replace function public.nexo_pluggy_link_account(p_account_id text, p_nexo_account_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_nexo_account_id is not null and length(p_nexo_account_id) not between 1 and 128 then
    raise exception using errcode = '22023', message = 'invalid_account';
  end if;
  update nexo_pluggy_private.accounts set nexo_account_id = p_nexo_account_id
    where owner_id = v_user and account_id = p_account_id;
  if not found then
    raise exception using errcode = '22023', message = 'account_unavailable';
  end if;
end;
$$;

-- Items also tell when the bank data was refreshed.
create or replace function public.nexo_pluggy_items()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'item_id', item_id, 'label', label, 'health', health,
      'last_fetch_at', last_fetch_at, 'bank_updated_at', bank_updated_at) order by created_at)
    from nexo_pluggy_private.items where owner_id = v_user), '[]'::jsonb);
end;
$$;

revoke all on function public.nexo_pluggy_store_accounts(uuid, text, timestamptz, jsonb) from public, anon, authenticated;
grant execute on function public.nexo_pluggy_store_accounts(uuid, text, timestamptz, jsonb) to service_role;
revoke all on function public.nexo_pluggy_accounts() from public, anon;
grant execute on function public.nexo_pluggy_accounts() to authenticated;
revoke all on function public.nexo_pluggy_link_account(text, text) from public, anon;
grant execute on function public.nexo_pluggy_link_account(text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
