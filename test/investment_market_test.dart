import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexo/investments/investment_quotes.dart';
import 'package:nexo/investments/investment_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('quote enriches market data without additional requests', () async {
    var calls = 0;
    final api = InvestmentQuotes(
        clientFactory: () => MockClient((request) async {
              calls++;
              return http.Response(
                  jsonEncode({
                    'results': [
                      {
                        'symbol': 'PETR4',
                        'requestedSymbol': 'PETR4',
                        'changed': false,
                        'data': {
                          'currency': 'BRL',
                          'regularMarketPrice': 30,
                          'regularMarketTime': '2026-01-02T15:00:00Z',
                          'regularMarketChangePercent': -2.5,
                          'regularMarketDayLow': 29,
                          'regularMarketVolume': 1000,
                          'logourl': 'https://icons.brapi.dev/icons/PETR4.svg',
                          'marketCap': null
                        }
                      }
                    ]
                  }),
                  200);
            }));
    final quote = await api.fetch('PETR4');
    expect(calls, 1);
    expect(quote.priceMicros, 30000000);
    expect(quote.market!.value('regularMarketChangePercent'), -2.5);
    expect(quote.market!.value('marketCap'), isNull);
    expect(quote.market!.logo, 'https://icons.brapi.dev/icons/PETR4.svg');
  });
  test('optional malformed fields and untrusted logo URLs are discarded', () {
    for (final url in [
      'http://icons.brapi.dev/icons/A.svg',
      'https://attacker.example/A.svg',
      'https://icons.brapi.dev@attacker.example/A.svg',
      'file:///secret',
      'https://icons.brapi.dev/icons/A.svg?token=secret',
      'https://icons.brapi.dev:444/icons/A.svg'
    ]) {
      final market = MarketSnapshot.parse({
        'logourl': url,
        'regularMarketDayLow': -1,
        'marketCap': double.infinity,
        'regularMarketChange': 'invalid'
      }, DateTime(2026));
      expect(market.fields, isEmpty, reason: url);
    }
  });
  test('offline cache preserves data and rejects older snapshots', () async {
    final newer = MarketSnapshot.parse(
        {'regularMarketChangePercent': 3}, DateTime(2026, 2));
    await MarketCache.save('PETR4', newer);
    await MarketCache.save(
        'PETR4',
        MarketSnapshot.parse(
            {'regularMarketChangePercent': -9}, DateTime(2026)));
    final restored = await MarketCache.read('PETR4');
    expect(restored!.value('regularMarketChangePercent'), 3);
    expect(restored.date, newer.date.toUtc());
    expect(await MarketCache.read('OTHER'), isNull);
  });
  test('only listed Brazilian exchange classes allow stock endpoint', () {
    for (final type in investmentClasses) {
      final asset = Investment(
          id: 'test',
          name: 'Test',
          assetClass: type,
          ticker: 'TEST11',
          priceMicros: 0,
          priceAt: DateTime(2026));
      expect(asset.canQuote, ['Ações', 'FIIs', 'ETFs'].contains(type));
    }
  });
}
