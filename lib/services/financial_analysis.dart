import '../models/models.dart';
import 'finance_rules.dart';
import 'transaction_metadata_service.dart';

/// Consumption reporting only; cash balances belong to CashForecast.
class AnalysisFilter {
  final DateTime from, to;
  final String? accountId, categoryId, subcategory, type;
  const AnalysisFilter(
      {required this.from,
      required this.to,
      this.accountId,
      this.categoryId,
      this.subcategory,
      this.type});
  bool matches(AppTransaction t, TransactionMetadata m) =>
      !t.date.isBefore(DateTime(from.year, from.month, from.day)) &&
      t.date.isBefore(DateTime(to.year, to.month, to.day + 1)) &&
      (accountId == null || t.accountId == accountId) &&
      (categoryId == null || t.categoryId == categoryId) &&
      (subcategory == null || m.subcategory == subcategory) &&
      (type == null || t.type == type);
  AnalysisFilter period(DateTime start, DateTime end) => AnalysisFilter(
      from: start,
      to: end,
      accountId: accountId,
      categoryId: categoryId,
      subcategory: subcategory,
      type: type);
}

class FinancialAnalysis {
  final List<AppTransaction> realized = [], pending = [];
  final Map<String, double> categories = {}, subcategories = {}, accounts = {};
  double income = 0, expense = 0, refunds = 0, pendingExpense = 0;
  double extraordinary = 0, recurring = 0, transfers = 0;
  double get normal => expense - extraordinary;
  double get variable => expense - recurring;
  double get result => income + refunds - expense;
  List<MapEntry<String, double>> get topCategories =>
      categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  static bool isRefund(AppTransaction t, TransactionMetadata m) =>
      t.type == 'income' &&
      (m.source == 'notification_refund' ||
          t.note == 'Estorno / reembolso revisado');
  FinancialAnalysis(
      {required Iterable<AppTransaction> transactions,
      required Map<String, TransactionMetadata> metadata,
      required AnalysisFilter filter,
      required double Function(AppTransaction) amount}) {
    for (final t in transactions) {
      final m = metadata[t.id] ?? TransactionMetadata(transactionId: t.id);
      if (!filter.matches(t, m)) continue;
      final value = amount(t);
      if (FinanceRules.isNeutral(t, m)) {
        if (!m.isPending &&
            t.type == 'expense' &&
            m.source.startsWith('transfer:')) transfers += value;
        continue;
      }
      if (m.isPending) {
        pending.add(t);
        if (t.type == 'expense') pendingExpense += value;
        continue;
      }
      realized.add(t);
      if (isRefund(t, m)) {
        refunds += value;
        continue;
      }
      if (t.type == 'income') {
        income += value;
        continue;
      }
      if (t.type != 'expense') continue;
      expense += value;
      categories.update(t.categoryId, (v) => v + value, ifAbsent: () => value);
      subcategories.update(m.subcategory, (v) => v + value,
          ifAbsent: () => value);
      accounts.update(t.accountId, (v) => v + value, ifAbsent: () => value);
      if (m.expenseClass == 'extraordinary') extraordinary += value;
      if (m.source == 'recurring' || t.id.startsWith('recurring:'))
        recurring += value;
    }
  }
  double? changeFrom(FinancialAnalysis previous) => previous.expense == 0
      ? null
      : (expense - previous.expense) / previous.expense * 100;
  static AnalysisFilter month(DateTime month, DateTime now) => AnalysisFilter(
      from: DateTime(month.year, month.month),
      to: month.year == now.year && month.month == now.month
          ? DateTime(now.year, now.month, now.day)
          : DateTime(month.year, month.month + 1, 0));
  static AnalysisFilter previousMonth(AnalysisFilter current,
      {required bool partial}) {
    final start = DateTime(current.from.year, current.from.month - 1);
    final last = DateTime(current.from.year, current.from.month, 0);
    return current.period(
        start,
        partial
            ? DateTime(
                start.year, start.month, current.to.day.clamp(1, last.day))
            : last);
  }
}
