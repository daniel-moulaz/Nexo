import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import '../providers/app_provider.dart';
import '../sync/ledger_capture.dart';
import 'finance_rules.dart';
import 'transaction_metadata_service.dart';

class FinanceBootstrapService {
  static const _names = <String, (String original, String pt)>{
    'food_exp': ('Food & Dining', 'Alimentação'),
    'transport': ('Transport', 'Transporte'),
    'shopping': ('Shopping', 'Compras'),
    'bills': ('Bills & Utilities', 'Moradia & Contas'),
    'health': ('Health', 'Saúde'),
    'entertainment': ('Entertainment', 'Lazer'),
    'education': ('Education', 'Educação'),
    'other_exp': ('Other', 'Outros'),
    'salary': ('Salary', 'Salário'),
    'freelance': ('Freelance', 'Freelancer'),
    'business': ('Business', 'Negócios'),
    'investment': ('Investment', 'Investimentos'),
    'gift': ('Gift', 'Presentes'),
  };

  /// Deterministic normalization run at every start. Each device derives the
  /// same result from its own data, so it is never journaled for sync (two
  /// devices would otherwise "edit" the same defaults concurrently).
  static Future<void> apply(AppProvider app) async {
    var changed = false;
    await DBHelper.operation('bootstrap.normalize', scope: LedgerScope.derived,
        (txn) async {
      for (final category in app.categories) {
        final pair = _names[category.id];
        if (pair == null || category.name != pair.$1) continue;
        await txn.update('categories', {'name': pair.$2},
            where: 'id = ?', whereArgs: [category.id]);
        changed = true;
      }
      const accountNames = {
        'Main Account': 'Conta principal',
        'Credit Card': 'Cartão de crédito',
      };
      for (final account in app.accounts) {
        final desired = accountNames[account.name];
        if (desired == null) continue;
        await txn.update('accounts', {'name': desired},
            where: 'id = ?', whereArgs: [account.id]);
        changed = true;
      }
      for (final tx in app.transactions) {
        if (!FinanceRules.isImplicitNeutral(tx)) continue;
        final rows = await txn.query('transaction_metadata',
            where: 'transaction_id = ?', whereArgs: [tx.id]);
        final current = rows.isEmpty
            ? TransactionMetadata(transactionId: tx.id)
            : TransactionMetadata.fromMap(rows.single);
        if (current.excludeFromSpending) continue;
        changed = true;
        await txn.insert(
          'transaction_metadata',
          TransactionMetadata(
            transactionId: current.transactionId,
            subcategory: current.subcategory.isEmpty
                ? 'Transferência/Reserva'
                : current.subcategory,
            status: current.status,
            dueDate: current.dueDate,
            expenseClass: current.expenseClass,
            excludeFromSpending: true,
            installmentCurrent: current.installmentCurrent,
            installmentTotal: current.installmentTotal,
            source: current.source,
            affectsBalance: current.affectsBalance,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    if (changed) {
      await app.load();
      TransactionMetadataService.instance.revision.value++;
    }
  }
}
