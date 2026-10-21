-- Nexo: the assistant can do what the person does in the app: accounts and
-- balance adjustments, deleting unused categories, goals, investments, loans,
-- money lent, assets and the wishlist. Still requests only: a device applies
-- each one with the app's own rules. It also reads loans, money lent, assets
-- and the wishlist to answer about them.
begin;
alter table nexo_mcp_private.commands drop constraint commands_kind_check;
alter table nexo_mcp_private.commands add constraint commands_kind_check
  check (kind in ('transaction.add', 'transfer.add', 'transaction.update',
    'transaction.delete', 'transaction.settle', 'suggestion.confirm',
    'recurring.pay', 'recurring.skip', 'recurring.add', 'recurring.update',
    'recurring.delete', 'budget.set', 'budget.delete', 'category.add',
    'category.update', 'goal.move', 'invoice.pay', 'account.add',
    'account.update', 'account.adjust', 'account.delete', 'category.delete',
    'goal.add', 'goal.update', 'goal.delete', 'investment.add',
    'investment.operation', 'investment.price', 'loan.pay', 'loan.skip',
    'lended.add', 'lended.settle', 'asset.add', 'asset.update', 'asset.delete',
    'wishlist.add', 'wishlist.update', 'wishlist.delete'));

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
          'lended_people', 'assets', 'wishlist')), '[]'::jsonb),
    'balances', coalesce((select jsonb_agg(jsonb_build_object('account_id', account_id, 'micros', micros))
      from nexo_sync_lab_private.balances
      where dataset_id = v_row.dataset_id and owner_id = v_row.owner_id), '[]'::jsonb));
end;
$$;

notify pgrst, 'reload schema';
commit;
