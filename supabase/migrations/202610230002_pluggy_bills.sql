-- Nexo: official credit card invoices from Open Finance (Pluggy /bills), so
-- the app can check its own invoice (closing-day rule) against the bank's.
-- Only totals, dates and sums of charges and payments are kept: no
-- descriptions or identifiers of payments. Nothing here moves money; the
-- bank invoice is shown for comparison and never becomes an entry.
begin;

create table if not exists nexo_pluggy_private.bills (
  owner_id uuid not null,
  account_id text not null,
  bill_id text not null check (bill_id ~ '^[0-9A-Za-z-]{1,64}$'),
  due_date date not null,
  close_date date,
  total_cents bigint not null,
  minimum_cents bigint,
  charges_cents bigint not null default 0,
  paid_cents bigint not null default 0,
  currency text not null default 'BRL' check (length(currency) = 3),
  fetched_at timestamptz not null default now(),
  primary key (owner_id, bill_id),
  foreign key (owner_id, account_id) references nexo_pluggy_private.accounts(owner_id, account_id) on delete cascade
);
alter table nexo_pluggy_private.bills enable row level security;

-- Called by pluggy-sync (service role) after storing the item's accounts.
-- The bank's list replaces what was kept for that card.
create or replace function public.nexo_pluggy_store_bills(p_owner uuid, p_account_id text, p_bills jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_row jsonb;
begin
  if not exists(select 1 from nexo_pluggy_private.accounts
      where owner_id = p_owner and account_id = p_account_id and type = 'CREDIT') then
    raise exception using errcode = '42501', message = 'account_unavailable';
  end if;
  if p_bills is null or jsonb_typeof(p_bills) <> 'array' or jsonb_array_length(p_bills) > 24 then
    raise exception using errcode = '22023', message = 'invalid_bills';
  end if;
  delete from nexo_pluggy_private.bills b
    where b.owner_id = p_owner and b.account_id = p_account_id
      and not exists(select 1 from jsonb_array_elements(p_bills) x where x->>'bill_id' = b.bill_id);
  for v_row in select * from jsonb_array_elements(p_bills) loop
    insert into nexo_pluggy_private.bills(owner_id, account_id, bill_id, due_date, close_date,
        total_cents, minimum_cents, charges_cents, paid_cents, currency, fetched_at)
      values (p_owner, p_account_id, v_row->>'bill_id', (v_row->>'due_date')::date,
        (v_row->>'close_date')::date, (v_row->>'total_cents')::bigint, (v_row->>'minimum_cents')::bigint,
        coalesce((v_row->>'charges_cents')::bigint, 0), coalesce((v_row->>'paid_cents')::bigint, 0),
        coalesce(v_row->>'currency', 'BRL'), now())
    on conflict (owner_id, bill_id) do update set
      account_id = excluded.account_id, due_date = excluded.due_date, close_date = excluded.close_date,
      total_cents = excluded.total_cents, minimum_cents = excluded.minimum_cents,
      charges_cents = excluded.charges_cents, paid_cents = excluded.paid_cents,
      currency = excluded.currency, fetched_at = now();
  end loop;
end;
$$;

-- The person's accounts now carry the latest invoices of each card.
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
      'bank_updated_at', i.bank_updated_at, 'fetched_at', a.fetched_at,
      'bills', coalesce((select jsonb_agg(jsonb_build_object(
          'bill_id', b.bill_id, 'due_date', b.due_date, 'close_date', b.close_date,
          'total_cents', b.total_cents, 'minimum_cents', b.minimum_cents,
          'charges_cents', b.charges_cents, 'paid_cents', b.paid_cents, 'currency', b.currency)
        order by b.due_date desc)
        from (select * from nexo_pluggy_private.bills
          where owner_id = a.owner_id and account_id = a.account_id
          order by due_date desc limit 12) b), '[]'::jsonb))
    order by i.created_at, a.type, a.name)
    from nexo_pluggy_private.accounts a
    join nexo_pluggy_private.items i on i.owner_id = a.owner_id and i.item_id = a.item_id
    where a.owner_id = v_user), '[]'::jsonb);
end;
$$;

revoke all on function public.nexo_pluggy_store_bills(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.nexo_pluggy_store_bills(uuid, text, jsonb) to service_role;
revoke all on function public.nexo_pluggy_accounts() from public, anon;
grant execute on function public.nexo_pluggy_accounts() to authenticated;

notify pgrst, 'reload schema';
commit;
