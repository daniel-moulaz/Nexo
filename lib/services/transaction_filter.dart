import '../models/models.dart';
import 'finance_rules.dart';
import 'transaction_metadata_service.dart';

class TransactionFilter {
  String? accountId, categoryId, status, source, expenseClass;
  DateTime? from, to;
  double? minimum, maximum;
  bool installmentsOnly = false;
  TransactionFilter copy() => TransactionFilter()
    ..accountId = accountId
    ..categoryId = categoryId
    ..status = status
    ..source = source
    ..expenseClass = expenseClass
    ..from = from
    ..to = to
    ..minimum = minimum
    ..maximum = maximum
    ..installmentsOnly = installmentsOnly;
  bool matches(AppTransaction tx, TransactionMetadata meta) {
    final date = DateTime(tx.date.year, tx.date.month, tx.date.day);
    return (accountId == null || tx.accountId == accountId) &&
        (categoryId == null || tx.categoryId == categoryId) &&
        (status == null || meta.status == status) &&
        (expenseClass == null || meta.expenseClass == expenseClass) &&
        (source == null || meta.source == source) &&
        (from == null || !date.isBefore(from!)) &&
        (to == null || !date.isAfter(to!)) &&
        (minimum == null || tx.amount >= minimum!) &&
        (maximum == null || tx.amount <= maximum!) &&
        (!installmentsOnly || (meta.installmentTotal ?? 0) > 1);
  }

  static bool matchesType(
          AppTransaction tx, TransactionMetadata meta, String type) =>
      type == 'all' ||
      (type == 'neutral'
          ? FinanceRules.isNeutral(tx, meta)
          : tx.type == type && !FinanceRules.isNeutral(tx, meta));
}
