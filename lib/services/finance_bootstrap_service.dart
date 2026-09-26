import '../models/models.dart';
import '../providers/app_provider.dart';
import 'finance_rules.dart';
import 'transaction_metadata_service.dart';

class FinanceBootstrapService {
  static const _names = <String, (String original, String pt)> {
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

  static Future<void> apply(AppProvider app) async {
    for (final category in List<AppCategory>.from(app.categories)) {
      final pair = _names[category.id];
      if (pair == null) continue;
      final original = pair.$1;
      final desired = pair.$2;
      if (category.name != original) continue;
      await app.updateCategory(category.copyWith(name: desired));
    }

    for (final account in List<Account>.from(app.accounts)) {
      if (account.name == 'Main Account') {
        await app.updateAccount(account.copyWith(name: 'Conta principal'));
      } else if (account.name == 'Credit Card') {
        await app.updateAccount(account.copyWith(name: 'Cartão de crédito'));
      }
    }

    for (final tx in app.transactions) {
      if (!FinanceRules.isImplicitNeutral(tx)) continue;
      final current = await TransactionMetadataService.instance.getFor(tx.id);
      if (current.excludeFromSpending) continue;
      await TransactionMetadataService.instance.save(
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
        ),
      );
    }
  }
}
