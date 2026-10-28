import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexo/services/market_indices.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 28, 9);

  http.Client fake(
          {bool ipcaDown = false, bool offline = false, List<String>? hits}) =>
      MockClient((request) async {
        hits?.add(request.url.toString());
        if (offline) throw http.ClientException('offline');
        final u = request.url.toString();
        if (u.contains('bcdata.sgs.433')) {
          if (ipcaDown) return http.Response('oops', 500);
          // 13 months: the oldest must be dropped from the 12-month compound.
          final rows = [
            for (var i = 0; i < 13; i++)
              {
                'data': '01/${(i % 12) + 1}/2026',
                'valor': i == 0 ? '9,00' : '0,50'
              }
          ];
          return http.Response(jsonEncode(rows), 200);
        }
        if (u.contains('bcdata.sgs.432')) {
          return http.Response(
              jsonEncode([
                {'data': '27/10/2026', 'valor': '15.00'}
              ]),
              200);
        }
        if (u.contains('CotacaoDolarDia')) {
          // Sunday and Saturday come back empty; Friday has the rate.
          if (u.contains("'10-28-2026'") || u.contains("'10-27-2026'")) {
            return http.Response(jsonEncode({'value': []}), 200);
          }
          return http.Response(
              jsonEncode({
                'value': [
                  {'cotacaoCompra': 5.40, 'cotacaoVenda': 5.4123}
                ]
              }),
              200);
        }
        return http.Response('not found', 404);
      });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'reads the three indices, compounds 12 months, walks back to a business day',
      () async {
    final hits = <String>[];
    final r = await MarketIndices(
        clientFactory: () => fake(hits: hits), now: () => now).read();
    expect(r, isNotNull);
    expect(r!.ipca12m, closeTo(6.17, .01)); // (1.005^12 - 1) * 100
    expect(r.selic, 15.0);
    expect(r.ptax, 5.4123);
    expect(hits.where((h) => h.contains('CotacaoDolarDia')).length, 3);
  });

  test('a fresh cache is served without the network; force refreshes',
      () async {
    final hits = <String>[];
    final m =
        MarketIndices(clientFactory: () => fake(hits: hits), now: () => now);
    await m.read();
    final before = hits.length;
    await m.read();
    expect(hits.length, before, reason: 'cached');
    await m.read(force: true);
    expect(hits.length, greaterThan(before));
  });

  test('one index failing keeps the others and its own last value', () async {
    SharedPreferences.setMockInitialValues({
      'nexo_market_indices': jsonEncode({
        'ipca12m': 4.5,
        'selic': 14.0,
        'ptax': 5.2,
        'at': now.subtract(const Duration(days: 2)).toIso8601String()
      })
    });
    final r = await MarketIndices(
        clientFactory: () => fake(ipcaDown: true), now: () => now).read();
    expect(r!.ipca12m, 4.5, reason: 'last good value');
    expect(r.selic, 15.0);
    expect(r.ptax, 5.4123);
  });

  test('offline returns what was cached, or null, never throws', () async {
    expect(
        await MarketIndices(
            clientFactory: () => fake(offline: true), now: () => now).read(),
        isNull);
    SharedPreferences.setMockInitialValues({
      'nexo_market_indices': jsonEncode({
        'ipca12m': 4.5,
        'selic': 14.0,
        'ptax': 5.2,
        'at': now.subtract(const Duration(days: 2)).toIso8601String()
      })
    });
    final r = await MarketIndices(
        clientFactory: () => fake(offline: true), now: () => now).read();
    expect(r!.ptax, 5.2);
  });
}
