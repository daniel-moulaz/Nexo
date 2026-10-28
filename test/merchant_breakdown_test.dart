import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/services/merchant_breakdown.dart';

void main() {
  AppTransaction tx(String id, String desc, double v, int day,
          {String type = 'expense', String cat = 'food'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: v,
          description: desc,
          accountId: 'a',
          categoryId: cat,
          date: DateTime(2026, 10, day),
          currency: 'BRL');

  test(
      'groups by place ignoring numbers, skips neutral and pending, biggest first',
      () {
    final lines = merchantBreakdown(
        transactions: [
          tx('1', 'Mercado Bom 123', 50, 2),
          tx('2', 'MERCADO BOM 456', 70, 9, cat: 'home'),
          tx('3', 'mercado bom', 30, 20),
          tx('4', 'Uber', 200, 5, cat: 'transport'),
          tx('5', 'Pix para mim', 999, 6),
          tx('6', 'Boleto futuro', 500, 7),
          tx('7', 'Salário', 3000, 1, type: 'income'),
          tx('8', 'Fora do mês', 80, 31),
        ],
        metadata: {
          '5': const TransactionMetadata(
              transactionId: '5', excludeFromSpending: true),
          '6': const TransactionMetadata(transactionId: '6', status: 'pending'),
        },
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        amount: (t) => t.amount);
    expect(lines.map((l) => l.name), ['Uber', 'Mercado Bom 123']);
    expect(lines[1].total, 150);
    expect(lines[1].count, 3);
    expect(lines[1].categoryId, 'food');
    expect(lines[0].categoryId, 'transport');
  });
}
