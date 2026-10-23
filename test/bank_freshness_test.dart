import 'package:expensy/services/pluggy_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 21, 0, 24);
  PluggyItem item(String label, DateTime? at) =>
      PluggyItem('id-$label', label, 'ok', 'Conectado.', bankUpdatedAt: at);

  test('session case: at 00:24 the day did not arrive yet; say so', () {
    final items = [
      item('Nubank', DateTime(2026, 10, 20, 6)),
      item('Inter', DateTime(2026, 10, 21, 0, 10)),
      item('BTG', null),
    ];
    expect(todayMissing(items, now), contains('Nubank'));
    expect(todayMissing(items, now), isNot(contains('Inter')));
    expect(todayMissing(items, now), contains('uma vez por dia'));
    expect(bankDataUntil(items.first), 'Dados do banco até 20/10 às 06:00');
    expect(bankDataUntil(items.last),
        'Data dos dados do banco ainda não informada');
  });

  test('everything up to date, or unknown: no warning', () {
    expect(todayMissing([item('Inter', DateTime(2026, 10, 21, 0, 10))], now),
        isNull);
    expect(todayMissing([item('BTG', null)], now), isNull);
  });

  test('server rows carry the bank time', () {
    final i = PluggyItem.fromJson({
      'item_id': 'x',
      'label': 'Nubank',
      'health': {'state': 'ok', 'message': 'Conectado.'},
      'bank_updated_at': '2026-10-20T09:00:00+00:00',
    });
    expect(i.bankUpdatedAt!.toUtc(), DateTime.utc(2026, 10, 20, 9));
    expect(PluggyItem.fromJson({'item_id': 'y', 'label': 'B'}).bankUpdatedAt,
        isNull);
  });
}
