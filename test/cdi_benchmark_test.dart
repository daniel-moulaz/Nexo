import 'dart:convert';

import 'package:nexo/investments/cdi_benchmark.dart';
import 'package:nexo/investments/investment_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

InvestmentOperation _op(String id, String kind, int cents, DateTime date,
        {int quantity = 1000000}) =>
    InvestmentOperation(
        id: id,
        investmentId: 'cdb',
        kind: kind,
        quantity: kind == 'income' ? 0 : quantity,
        cents: cents,
        date: date,
        createdAt: date);

InvestmentPosition _position(List<InvestmentOperation> ops, int priceCents) =>
    InvestmentPosition(
        Investment(
            id: 'cdb',
            name: 'CDB de demonstração',
            assetClass: 'Renda fixa',
            priceMicros: priceCents * 10000,
            priceAt: DateTime(2026, 10, 21)),
        ops);

void main() {
  // 1% a business day keeps the arithmetic readable.
  final series = CdiSeries({
    DateTime(2026, 10, 1): 1, // Thu
    DateTime(2026, 10, 2): 1, // Fri
    DateTime(2026, 10, 5): 1, // Mon
  }, from: DateTime(2026, 9, 30));

  test('a day earns its own rate, until the day before the end', () {
    expect(series.factor(DateTime(2026, 10, 1), DateTime(2026, 10, 2)), 1.01);
    expect(series.factor(DateTime(2026, 10, 1), DateTime(2026, 10, 6)),
        closeTo(1.01 * 1.01 * 1.01, 1e-12));
    // A weekend contribution starts on the next business day.
    expect(series.factor(DateTime(2026, 10, 3), DateTime(2026, 10, 6)), 1.01);
  });

  test('same flows at 100% of the CDI, sales and income taken out', () {
    final now = DateTime(2026, 10, 6);
    final p = _position([
      _op('a', 'buy', 100000, DateTime(2026, 10, 1)),
      _op('b', 'buy', 50000, DateTime(2026, 10, 5)),
      _op('c', 'sell', 20000, DateTime(2026, 10, 2), quantity: 500000),
      _op('d', 'income', 1000, DateTime(2026, 10, 5)),
    ], 100000); // 1.5 units at R$ 1.000,00 = R$ 1.500,00
    final r = compareWithCdi([p], series, now)!;
    expect(r.portfolio, 150000);
    final cdi = 100000 * 1.01 * 1.01 * 1.01 +
        50000 * 1.01 -
        20000 * 1.01 * 1.01 -
        1000 * 1.01;
    expect(r.cdi, cdi.round());
    expect(r.difference, 150000 - cdi.round());
    expect(r.since, DateTime(2026, 10, 1));
    expect(r.coveredUntil, DateTime(2026, 10, 5));
  });

  test('no comparison before the series starts or without operations', () {
    final early =
        _position([_op('a', 'buy', 100000, DateTime(2026, 9, 1))], 100000);
    expect(compareWithCdi([early], series, DateTime(2026, 10, 6)), isNull);
    expect(compareWithCdi([], series, DateTime(2026, 10, 6)), isNull);
  });

  group('source', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('long ranges are split, then extended from the cache', () async {
      final table = {
        DateTime(2016, 1, 4): 0.052531,
        DateTime(2026, 10, 19): 0.050788,
        DateTime(2026, 10, 20): 0.050788,
      };
      DateTime parse(String v) {
        final p = v.split('/').map(int.parse).toList();
        return DateTime(p[2], p[1], p[0]);
      }

      final ranges = <String>[];
      final source = CdiSource(
          clientFactory: () => MockClient((request) async {
                final q = request.url.queryParameters;
                ranges.add('${q['dataInicial']}-${q['dataFinal']}');
                final from = parse(q['dataInicial']!),
                    to = parse(q['dataFinal']!);
                final rows = [
                  for (final e in table.entries)
                    if (!e.key.isBefore(from) && !e.key.isAfter(to))
                      {
                        'data':
                            '${e.key.day.toString().padLeft(2, '0')}/${e.key.month.toString().padLeft(2, '0')}/${e.key.year}',
                        'valor': '${e.value}'
                      }
                ];
                // The API answers 404 for a range without business days.
                return rows.isEmpty
                    ? http.Response('', 404)
                    : http.Response(jsonEncode(rows), 200);
              }));
      final s =
          await source.load(DateTime(2016, 1, 2), now: DateTime(2026, 10, 19));
      expect(ranges, [
        '02/01/2016-01/01/2021',
        '02/01/2021-01/01/2026',
        '02/01/2026-19/10/2026'
      ]);
      expect(s!.rates.keys, [DateTime(2016, 1, 4), DateTime(2026, 10, 19)]);
      expect(s.from, DateTime(2016, 1, 2));

      // Fresh for 12 hours: no request.
      ranges.clear();
      await source.load(DateTime(2016, 1, 2), now: DateTime(2026, 10, 19, 6));
      expect(ranges, isEmpty);

      // Later: only what is missing.
      final next =
          await source.load(DateTime(2016, 1, 2), now: DateTime(2026, 10, 21));
      expect(ranges, ['20/10/2026-21/10/2026']);
      expect(next!.rates.length, 3);
      expect(next.from, DateTime(2016, 1, 2));

      // An earlier first operation fetches the whole range again.
      ranges.clear();
      await source.load(DateTime(2015, 6, 1), now: DateTime(2026, 10, 21, 1));
      expect(ranges.first, '01/06/2015-31/05/2020');
    });

    test('a network failure keeps the cached series', () async {
      final ok = CdiSource(
          clientFactory: () => MockClient((_) async => http.Response(
              jsonEncode([
                {'data': '01/10/2026', 'valor': '0.050788'}
              ]),
              200)));
      await ok.load(DateTime(2026, 10, 1), now: DateTime(2026, 10, 2));
      final down = CdiSource(
          clientFactory: () =>
              MockClient((_) async => http.Response('erro', 500)));
      final s =
          await down.load(DateTime(2026, 10, 1), now: DateTime(2026, 10, 10));
      expect(s!.rates, {DateTime(2026, 10, 1): 0.050788});
    });

    test('values that are not a daily rate are refused', () async {
      final bad = CdiSource(
          clientFactory: () => MockClient((_) async => http.Response(
              jsonEncode([
                {'data': '01/10/2026', 'valor': '13.65'}
              ]),
              200)));
      expect(await bad.load(DateTime(2026, 10, 1), now: DateTime(2026, 10, 2)),
          isNull);
    });
  });
}
