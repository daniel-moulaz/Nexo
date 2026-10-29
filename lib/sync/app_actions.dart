/// The single list of what the app writes, by the name of its ledger
/// operation (every write of user data runs inside `ledgerTransaction` or
/// `DBHelper.operation` with one of these names), and the assistant tools
/// that do the same through the connector.
///
/// `test/mcp_app_parity_test.dart` reads every operation name in `lib/` and
/// every tool of the server, and fails when a write has no entry here or an
/// entry names a tool that does not exist. A new screen action therefore
/// fails the build until it reaches the connector (or is recorded below as
/// internal, with the reason).
library;

const appWriteActions = <String, List<String>>{
  // Entries and transfers
  'transaction.add': ['add_transaction', 'duplicate_transaction'],
  'transaction.update': ['update_transaction', 'settle_transaction'],
  'transaction.delete': ['delete_transaction'],
  'transaction.restore': ['undo_request'],
  'transaction.bulk_update': ['update_transactions'],
  'transaction.bulk_delete': ['delete_transactions'],
  'transaction.neutralize': ['convert_to_balance_adjustment'],
  'transaction.split': ['split_transaction'],
  'transfer.add': ['add_transfer', 'confirm_suggestion_as_transfer'],
  'metadata.save': ['update_transaction', 'update_transactions'],
  'metadata.delete': ['update_transaction'],
  // Accounts and cards
  'account.create': ['add_account'],
  'account.insert': ['add_account'],
  'account.update': ['update_account', 'adjust_account_balance'],
  'account.delete': ['delete_account'],
  'invoice.pay': ['pay_card_invoice'],
  'invoice.record_payment': ['pay_card_invoice'],
  // Categories, kinds of spending and budgets
  'category.insert': ['add_category'],
  'category.update': [
    'rename_category',
    'update_category',
    'set_category_type'
  ],
  'category.delete': ['delete_category'],
  'category.merge': ['merge_categories'],
  'budget.insert': ['set_budget'],
  'budget.update': ['set_budget', 'update_budget'],
  'budget.delete': ['delete_budget'],
  'setting.update': ['set_setting', 'set_spending_targets'],
  // Goals
  'goal.insert': ['add_goal'],
  'goal.update': ['update_goal'],
  'goal.delete': ['delete_goal'],
  'goal.restore': ['undo_request'],
  'goal.contribute': ['move_goal'],
  'goal.withdraw': ['move_goal'],
  'goal.adjust': ['move_goal'],
  'goal.contribution_insert': ['move_goal'],
  // Recurring
  'recurring.insert': ['add_recurring'],
  'recurring.update': ['update_recurring'],
  'recurring.delete': ['delete_recurring'],
  'recurring.restore': ['undo_request'],
  'recurring.pay': ['pay_recurring'],
  'recurring.skip': ['skip_recurring'],
  'recurring.history_insert': ['pay_recurring', 'skip_recurring'],
  // Investments
  'investment.create': ['add_investment'],
  'investment.record': ['record_investment_operation'],
  'investment.price': ['update_investment_price'],
  'investment.archive': ['archive_investment'],
  'investment.remove_operation': ['delete_investment_operation'],
  'investment.link_cash': ['link_investment_operation'],
  // Loans, money lent, people
  'loan.create': ['add_loan'],
  'loan.update': ['update_loan'],
  'loan.delete': ['delete_loan'],
  'loan.restore': ['undo_request'],
  'loan.pay': ['pay_loan_installment', 'skip_loan_installment'],
  'loan.remove_payment': ['delete_loan_payment'],
  'lended.add': ['add_lended'],
  'lended.update': ['update_lended'],
  'lended.settle': ['settle_lended'],
  'lended.delete': ['delete_lended'],
  'lended.restore': ['undo_request'],
  'lended_person.insert': ['add_lended'],
  'lended_person.update': ['update_person'],
  'lended_person.delete': ['delete_person'],
  'lended_person.restore': ['undo_request'],
  // Assets and wishlist
  'asset.insert': ['add_asset'],
  'asset.update': ['update_asset'],
  'asset.delete': ['delete_asset'],
  'wishlist.insert': ['add_wishlist_item'],
  'wishlist.update': ['update_wishlist_item'],
  'wishlist.delete': ['delete_wishlist_item'],
  // Automatic category rules
  'import_rule.save': ['save_import_rule'],
  'import_rule.delete': ['delete_import_rule'],
  // The assistant's own undo
  'assistant.undo': ['undo_request'],
};

/// Writes that are not a decision a person makes on a screen, and why the
/// connector does not offer them.
const appInternalWrites = <String, String>{
  'sync.apply': 'aplica operações que vieram de outro aparelho',
  'sync.pull': 'grava o que a sincronização recebeu',
  'sync.reapply': 'resolve um conflito de sincronização na tela do aparelho',
  'sync.settle': 'conclui a sincronização',
  'setting.seed':
      'copia para o acervo as configurações que o aparelho já tinha',
  'gold.refresh': 'recalcula contas em ouro pela cotação; nunca é decisão',
  'bootstrap.normalize': 'ajuste automático da abertura do app',
  'backup.restore':
      'substitui o acervo inteiro por um arquivo do aparelho; só pela tela, com o arquivo',
  'import.greenstash': 'importa um arquivo de outro app, escolhido no aparelho',
};

/// App settings changed outside the assistant registry, and why.
const appInternalSettings = <String, String>{
  'languageCode': 'o app é só em português do Brasil',
  'pinnedWidgetAccountIds': 'escolhido no próprio widget da tela inicial',
};
