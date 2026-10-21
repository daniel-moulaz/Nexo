import '../database/db_helper.dart';
import '../investments/investment_models.dart';
import '../investments/investment_repository.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/loan_ledger.dart';

/// Assistant requests for the rest of the app: accounts and balance
/// adjustments, categories, goals, investments, loans, money lent, assets and
/// the wishlist. Each one goes through the same provider or ledger call as
/// the screens; creations use ids fixed by the request, so a request applied
/// twice changes nothing.
class AssistantMoreCommands {
  AssistantMoreCommands(this.app, {InvestmentRepository? investments})
      : investments = investments ?? InvestmentRepository();
  final AppProvider app;
  final InvestmentRepository investments;

  static double _reais(Object? cents) => (cents as num).toInt() / 100;
  static DateTime _day(Object? iso) {
    final d = DateTime.parse(iso as String);
    return DateTime(d.year, d.month, d.day, 12);
  }

  static const _palette = [
    0xFF6366F1,
    0xFF14B8A6,
    0xFFF59E0B,
    0xFFEC4899,
    0xFF22C55E,
    0xFF3B82F6,
    0xFFEF4444,
    0xFF8B5CF6,
  ];

  Account _account(Object? id) =>
      app.accountById(id as String? ?? '') ??
      (throw StateError('A conta não existe mais no Nexo.'));

  /// Null when [kind] is not one of these requests.
  Future<Map<String, Object?>?> handle(
      String commandId, String kind, Map<String, dynamic> a) async {
    switch (kind) {
      case 'account.add':
        final id = 'assistant-acc:$commandId';
        if (app.accountById(id) != null) {
          return {'account_id': id, 'message': 'Já estava cadastrada.'};
        }
        final type = a['type'] as String;
        await app.addAccount(Account(
            id: id,
            name: (a['name'] as String).trim(),
            type: type,
            balance: _reais(a['balance_cents'] ?? 0),
            currency: a['currency'] as String? ?? app.settings.currency,
            colorValue: _palette[app.accounts.length % _palette.length],
            statementDay: type == 'credit' ? a['statement_day'] as int? : null,
            dueDay: type == 'credit' ? a['due_day'] as int? : null,
            creditLimit: type == 'credit' && a['credit_limit_cents'] != null
                ? _reais(a['credit_limit_cents'])
                : null));
        return {'account_id': id, 'message': 'Conta criada.'};
      case 'account.update':
        final acc = _account(a['id']);
        final credit = acc.type == 'credit';
        await app.updateAccount(
            acc.copyWith(
                name: (a['name'] as String?)?.trim(),
                statementDay: credit ? a['statement_day'] as int? : null,
                dueDay: credit ? a['due_day'] as int? : null,
                creditLimit: credit && a['credit_limit_cents'] != null
                    ? _reais(a['credit_limit_cents'])
                    : null,
                excludeFromTotal: a['exclude_from_total'] as bool?),
            original: acc);
        return {'account_id': acc.id, 'message': 'Conta alterada.'};
      case 'account.adjust':
        // Same as typing the real balance in the account screen: not
        // spending nor income. Only from the balance the assistant saw.
        final acc = _account(a['id']);
        final target = _reais(a['balance_cents']);
        if ((acc.balance - target).abs() < .005) {
          return {'account_id': acc.id, 'message': 'O saldo já era esse.'};
        }
        if ((acc.balance - _reais(a['expected_cents'])).abs() >= .005) {
          throw StateError(
              'O saldo de ${acc.name} mudou desde a consulta. Consulte de novo.');
        }
        await app.updateAccount(acc.copyWith(balance: target), original: acc);
        return {'account_id': acc.id, 'message': 'Saldo ajustado.'};
      case 'account.delete':
        final id = a['id'] as String;
        if (app.accountById(id) == null) {
          return {'account_id': id, 'message': 'Já não existia.'};
        }
        await app.deleteAccount(id);
        return {'account_id': id, 'message': 'Conta excluída.'};
      case 'category.delete':
        final id = a['id'] as String;
        if (!app.categories.any((c) => c.id == id)) {
          return {'category_id': id, 'message': 'Já não existia.'};
        }
        // Never leaves entries, recurring items or budgets without category.
        if (app.transactions.any((t) => t.categoryId == id) ||
            app.recurring.any((r) => r.categoryId == id) ||
            app.budgets.any((b) => b.categoryId == id)) {
          throw StateError(
              'A categoria está em uso. Mude os lançamentos dela antes de excluir.');
        }
        await app.deleteCategory(id);
        return {'category_id': id, 'message': 'Categoria excluída.'};
      case 'goal.add':
        final id = 'assistant-goal:$commandId';
        if (app.savingsGoals.any((g) => g.id == id)) {
          return {'goal_id': id, 'message': 'Já estava cadastrado.'};
        }
        await app.addSavingsGoal(SavingsGoal(
            id: id,
            name: (a['name'] as String).trim(),
            targetAmount: _reais(a['target_cents']),
            currency: app.settings.currency,
            targetDate:
                a['target_date'] == null ? null : _day(a['target_date']),
            colorValue: _palette[app.savingsGoals.length % _palette.length]));
        return {'goal_id': id, 'message': 'Objetivo criado.'};
      case 'goal.update':
        final g = app.savingsGoals.where((g) => g.id == a['id']).firstOrNull ??
            (throw StateError('O objetivo não existe mais.'));
        await app.updateSavingsGoal(g.copyWith(
            name: (a['name'] as String?)?.trim(),
            targetAmount:
                a['target_cents'] == null ? null : _reais(a['target_cents']),
            targetDate:
                a['target_date'] == null ? null : _day(a['target_date'])));
        return {'goal_id': g.id, 'message': 'Objetivo alterado.'};
      case 'goal.delete':
        final id = a['id'] as String;
        final g = app.savingsGoals.where((g) => g.id == id).firstOrNull;
        if (g == null) return {'goal_id': id, 'message': 'Já não existia.'};
        if (g.currentAmount > .005) {
          throw StateError(
              'O objetivo ainda guarda dinheiro. Retire o valor para uma conta antes de excluir.');
        }
        await app.deleteSavingsGoal(id);
        return {'goal_id': id, 'message': 'Objetivo excluído.'};
      case 'investment.add':
        final id = 'assistant-inv:$commandId';
        if ((await investments.load()).any((p) => p.investment.id == id)) {
          return {'investment_id': id, 'message': 'Já estava cadastrado.'};
        }
        final date = _day(a['date']);
        final cents = (a['cents'] as num).toInt();
        final quantity = (a['quantity_micros'] as num).toInt();
        await investments.create(
            Investment(
                id: id,
                name: (a['name'] as String).trim(),
                assetClass: a['asset_class'] as String,
                ticker: (a['ticker'] as String? ?? '').toUpperCase(),
                institution: a['institution'] as String? ?? '',
                priceMicros: roundedRatio(cents, 10000 * investmentScale,
                    quantity), // cents per unit → micros
                priceAt: date,
                priceSource: 'entrada'),
            InvestmentOperation(
                id: 'assistant-invop:$commandId',
                investmentId: id,
                kind: a['cash_account_id'] == null ? 'opening' : 'buy',
                quantity: quantity,
                cents: cents,
                date: date,
                createdAt: DateTime.now(),
                cashAccountId: a['cash_account_id'] as String?));
        await app.refreshInvestmentCash();
        return {'investment_id': id, 'message': 'Investimento cadastrado.'};
      case 'investment.operation':
        final kindOp = a['kind'] as String;
        await investments.record(InvestmentOperation(
            id: 'assistant-invop:$commandId',
            investmentId: a['investment_id'] as String,
            kind: kindOp,
            quantity:
                kindOp == 'income' ? 0 : (a['quantity_micros'] as num).toInt(),
            cents: (a['cents'] as num).toInt(),
            date: _day(a['date']),
            // Same time for a retried request: record() compares rows.
            createdAt: DateTime.parse(a['created_at'] as String),
            cashAccountId: a['cash_account_id'] as String?));
        await app.refreshInvestmentCash();
        return {'message': 'Operação registrada.'};
      case 'investment.price':
        await investments.price(
            a['investment_id'] as String,
            (a['price_cents'] as num).toInt() * 10000,
            a['date'] == null ? DateTime.now() : _day(a['date']),
            'manual');
        return {'message': 'Preço atualizado.'};
      case 'loan.pay':
      case 'loan.skip':
        final loan = app.loans.where((l) => l.id == a['id']).firstOrNull ??
            (throw StateError('O empréstimo não existe mais.'));
        final paymentId = 'assistant-loanpay:$commandId';
        if (app.loanPayments.any((p) => p.id == paymentId)) {
          return {'message': 'Já estava registrado.'};
        }
        if (loan.isSettled) throw StateError('Este empréstimo já foi quitado.');
        final skip = kind == 'loan.skip';
        final amount = skip
            ? 0.0
            : a['amount_cents'] == null
                ? loan.monthlyPayment
                : _reais(a['amount_cents']);
        await LoanLedger(await DBHelper.database).pay(LoanPayment(
            id: paymentId,
            loanId: loan.id,
            date: DateTime.now(),
            amount: amount,
            currency: loan.currency,
            accountId: skip
                ? null
                : a['account_id'] == null
                    ? loan.accountId
                    : _account(a['account_id']).id,
            notes: skip ? 'Skipped' : 'Pelo assistente'));
        await app.reloadFromStorage();
        return {
          'message': skip ? 'Parcela pulada.' : 'Parcela paga.',
        };
      case 'lended.add':
        final id = 'assistant-lend:$commandId';
        if (app.lended.any((l) => l.id == id)) {
          return {'lended_id': id, 'message': 'Já estava registrado.'};
        }
        final name = (a['person'] as String).trim();
        var person = app.lendedPeople
            .where((p) => p.name.toLowerCase() == name.toLowerCase())
            .firstOrNull;
        if (person == null) {
          person = LendedPerson(
              id: 'assistant-person:$commandId',
              name: name,
              colorValue: _palette[app.lendedPeople.length % _palette.length]);
          if (!app.lendedPeople.any((p) => p.id == person!.id)) {
            await app.addLendedPerson(person);
          }
        }
        await app.addLended(LendedMoney(
            id: id,
            personId: person.id,
            amount: _reais(a['amount_cents']),
            type: a['type'] as String,
            accountId:
                a['account_id'] == null ? null : _account(a['account_id']).id,
            date: _day(a['date']),
            dueDate: a['due_date'] == null ? null : _day(a['due_date']),
            notes: a['notes'] as String? ?? ''));
        return {'lended_id': id, 'message': 'Registrado.'};
      case 'lended.settle':
        final l = app.lended.where((l) => l.id == a['id']).firstOrNull ??
            (throw StateError('O registro não existe mais.'));
        if (l.isSettled) return {'message': 'Já estava quitado.'};
        await app.settleLended(l);
        return {'message': 'Quitado.'};
      case 'asset.add':
        final id = 'assistant-asset:$commandId';
        if (app.assets.any((x) => x.id == id)) {
          return {'asset_id': id, 'message': 'Já estava cadastrado.'};
        }
        await app.addAsset(AssetItem(
            id: id,
            name: (a['name'] as String).trim(),
            value: _reais(a['value_cents']),
            currency: app.settings.currency,
            notes: a['notes'] as String? ?? ''));
        return {'asset_id': id, 'message': 'Bem cadastrado.'};
      case 'asset.update':
        final x = app.assets.where((x) => x.id == a['id']).firstOrNull ??
            (throw StateError('O bem não existe mais.'));
        await app.updateAsset(x.copyWith(
            name: (a['name'] as String?)?.trim(),
            value: a['value_cents'] == null ? null : _reais(a['value_cents'])));
        return {'asset_id': x.id, 'message': 'Bem alterado.'};
      case 'asset.delete':
        final id = a['id'] as String;
        if (!app.assets.any((x) => x.id == id)) {
          return {'asset_id': id, 'message': 'Já não existia.'};
        }
        await app.deleteAsset(id);
        return {'asset_id': id, 'message': 'Bem excluído.'};
      case 'wishlist.add':
        final id = 'assistant-wish:$commandId';
        if (app.wishlist.any((w) => w.id == id)) {
          return {'wishlist_id': id, 'message': 'Já estava na lista.'};
        }
        await app.addWishlist(WishlistItem(
            id: id,
            name: (a['name'] as String).trim(),
            targetPrice: _reais(a['price_cents']),
            priority: a['priority'] as String? ?? 'medium',
            notes: a['notes'] as String? ?? ''));
        return {'wishlist_id': id, 'message': 'Adicionado à lista.'};
      case 'wishlist.update':
        final w = app.wishlist.where((w) => w.id == a['id']).firstOrNull ??
            (throw StateError('O item não existe mais.'));
        await app.updateWishlist(w.copyWith(
            name: (a['name'] as String?)?.trim(),
            targetPrice:
                a['price_cents'] == null ? null : _reais(a['price_cents']),
            priority: a['priority'] as String?,
            isPurchased: a['purchased'] as bool?));
        return {'wishlist_id': w.id, 'message': 'Item alterado.'};
      case 'wishlist.delete':
        final id = a['id'] as String;
        if (!app.wishlist.any((w) => w.id == id)) {
          return {'wishlist_id': id, 'message': 'Já não existia.'};
        }
        await app.deleteWishlist(id);
        return {'wishlist_id': id, 'message': 'Item removido.'};
    }
    return null;
  }
}
