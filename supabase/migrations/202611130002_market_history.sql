-- 1.17.0: daily closes of US stocks kept by the server (see market-quotes).
-- Market data only, no personal data: a ticker and its price per day. Only
-- the market-quotes function (service_role) reads and writes it.

create schema if not exists nexo_market_private;
revoke all on schema nexo_market_private from public, anon, authenticated;

create table if not exists nexo_market_private.daily_closes (
  symbol text not null check (symbol ~ '^[A-Z0-9][A-Z0-9.\-]{0,11}$'),
  day date not null,
  close_micros bigint not null check (close_micros > 0 and close_micros <= 1000000000000),
  source text not null default 'quote' check (source in ('quote', 'backfill')),
  updated_at timestamptz not null default now(),
  primary key (symbol, day)
);
alter table nexo_market_private.daily_closes enable row level security;
revoke all on nexo_market_private.daily_closes from public, anon, authenticated;

create table if not exists nexo_market_private.backfills (
  symbol text primary key,
  done_at timestamptz not null default now()
);
alter table nexo_market_private.backfills enable row level security;
revoke all on nexo_market_private.backfills from public, anon, authenticated;

-- Stores closes. A quote of the day replaces that day's earlier quote; a
-- backfill never overwrites what the quotes recorded.
create or replace function public.nexo_market_store(p_rows jsonb, p_source text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer := 0; v_row jsonb;
begin
  if p_source not in ('quote', 'backfill') or jsonb_typeof(p_rows) <> 'array'
      or jsonb_array_length(p_rows) > 200 then
    raise exception using errcode = '22023', message = 'invalid_closes';
  end if;
  for v_row in select * from jsonb_array_elements(p_rows) loop
    insert into nexo_market_private.daily_closes(symbol, day, close_micros, source)
      values (v_row->>'symbol', (v_row->>'day')::date, (v_row->>'close_micros')::bigint, p_source)
    on conflict (symbol, day) do update
      set close_micros = excluded.close_micros, source = excluded.source, updated_at = now()
      where p_source = 'quote';
    v_count := v_count + 1;
  end loop;
  if p_source = 'backfill' and v_count > 0 then
    insert into nexo_market_private.backfills(symbol)
      select distinct v->>'symbol' from jsonb_array_elements(p_rows) v
    on conflict (symbol) do update set done_at = now();
  end if;
  return v_count;
end;
$$;

-- The last [p_days] days of closes, oldest first, and whether the first
-- fill already happened.
create or replace function public.nexo_market_history(p_symbol text, p_days integer)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'points', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'close_micros', close_micros) order by day)
      from nexo_market_private.daily_closes
      where symbol = p_symbol and day >= current_date - least(greatest(p_days, 1), 400)), '[]'::jsonb),
    'backfilled', exists (select 1 from nexo_market_private.backfills where symbol = p_symbol));
$$;

revoke all on function public.nexo_market_store(jsonb, text) from public, anon, authenticated;
revoke all on function public.nexo_market_history(text, integer) from public, anon, authenticated;
grant execute on function public.nexo_market_store(jsonb, text) to service_role;
grant execute on function public.nexo_market_history(text, integer) to service_role;

notify pgrst, 'reload schema';
