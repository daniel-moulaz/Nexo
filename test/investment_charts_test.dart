import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexo/investments/investment_history.dart';
import 'package:nexo/investments/investment_quotes.dart';
import 'package:nexo/investments/investment_models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/widgets/investment_price_chart.dart';
import 'package:nexo/widgets/portfolio_charts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final at = DateTime.utc(2026, 10, 19);
  Map<String, Object?> point(int days, double? price) => {
        'date':
            at.subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000,
        'adjustedClose': price,
        'close': 99999,
      };
  test(
      'historical parser sorts, deduplicates and never mixes unadjusted prices',
      () {
    final history = PriceHistory.parse(
        [point(1, 12), point(40, 10), point(2, null), point(1, 12)], at);
    expect(history.points.map((p) => p.price), [10, 12]);
    expect(history.window(30).length, 1);
    expect(history.window(90).length, 2);
    expect(() => PriceHistory.parse([point(1, 12), point(1, 13)], at),
        throwsFormatException);
    expect(
        () => PriceHistory.parse([point(-5, 12)], at), throwsFormatException);
    expect(() => PriceHistory.parse([point(1, double.infinity)], at),
        throwsFormatException);
  });
  test('historical request uses bounded daily window and validates identity',
      () async {
    final api = InvestmentHistory(
        clientFactory: () => MockClient((r) async {
              expect(r.url.host, 'brapi.dev');
              expect(r.url.path, '/api/v2/stocks/historical');
              expect(r.url.queryParameters, {
                'symbols': 'PETR4',
                'range': '3mo',
                'interval': '1d',
                'sortOrder': 'asc'
              });
              expect(r.followRedirects, false);
              expect(r.headers['Authorization'], 'Bearer synthetic');
              expect(r.body, isEmpty);
              return http.Response(
                  jsonEncode({
                    'results': [
                      {
                        'symbol': 'PETR4',
                        'requestedSymbol': 'PETR4',
                        'changed': false,
                        'data': {
                          'usedInterval': '1d',
                          'historicalDataPrice': [point(1, 12), point(2, 10)]
                        }
                      }
                    ]
                  }),
                  200);
            }));
    expect((await api.fetch('PETR4', token: 'synthetic')).points.length, 2);
    for (final status in [400, 403, 429, 500, 302]) {
      await expectLater(
          InvestmentHistory(
                  clientFactory: () => MockClient(
                      (_) async => http.Response('private error', status)))
              .fetch('PETR4'),
          throwsA(isA<QuoteFailure>()));
    }
    final wrong = InvestmentHistory(
        clientFactory: () => MockClient((_) async => http.Response(
            jsonEncode({
              'results': [
                {'symbol': 'OTHER', 'requestedSymbol': 'PETR4', 'changed': true}
              ]
            }),
            200)));
    await expectLater(wrong.fetch('PETR4'), throwsA(isA<QuoteFailure>()));
  });
  test('cached history survives offline and limits repeated requests',
      () async {
    final history = PriceHistory.parse([point(2, 10), point(1, 12)], at);
    await InvestmentHistory.save('PETR4', history);
    expect((await InvestmentHistory.cached('PETR4'))!.points.last.price, 12);
    expect(await InvestmentHistory.claim('PETR4'), true);
    expect(await InvestmentHistory.claim('PETR4'), false);
    expect(await InvestmentHistory.claim('VALE3'), true);
  });
  test('queue serializes operations and continues after failure', () async {
    final gate = Completer<void>();
    final order = <int>[];
    final first = InvestmentApiQueue.run<void>(() async {
      order.add(1);
      await gate.future;
      throw const QuoteFailure('synthetic');
    });
    final handled = first.catchError((_) {});
    final second = InvestmentApiQueue.run(() async {
      order.add(2);
      return 2;
    });
    await Future<void>.delayed(Duration.zero);
    expect(order, [1]);
    gate.complete();
    await handled;
    expect(await second, 2);
    expect(order, [1, 2]);
  });
  List<InvestmentPosition> positions() => [
        for (var i = 0; i < 2; i++)
          InvestmentPosition(
              Investment(
                  id: 'a$i',
                  name: 'Ativo $i',
                  ticker: 'TEST$i',
                  assetClass: 'Ações',
                  priceMicros: (i == 0 ? 12 : 8) * investmentScale,
                  priceAt: at),
              [
                InvestmentOperation(
                    id: 'o$i',
                    investmentId: 'a$i',
                    kind: 'buy',
                    quantity: 10 * investmentScale,
                    cents: 10000,
                    date: at,
                    createdAt: at),
                InvestmentOperation(
                    id: 'p$i',
                    investmentId: 'a$i',
                    kind: 'income',
                    quantity: 0,
                    cents: 500,
                    date: DateTime.now().subtract(const Duration(days: 1)),
                    createdAt: at)
              ])
      ];
  for (final width in [320.0, 412.0, 1280.0]) {
    testWidgets('portfolio charts interactive and private $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppProvider();
      String? opened;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: PortfolioCharts(
                          positions: positions(),
                          onAsset: (id) => opened = id))))));
      await tester.pumpAndSettle();
      expect(find.byType(PieChart), findsOneWidget);
      await tester.tap(find.text('TEST0'));
      await tester.pumpAndSettle();
      expect(opened, 'a0');
      await tester.tap(find.text('Resultado'));
      await tester.pumpAndSettle();
      final bars = tester.widget<BarChart>(find.byType(BarChart));
      expect(bars.data.minY, lessThan(0));
      expect(bars.data.barGroups.map((g) => g.barRods.single.toY), [20, -20]);
      await tester.tap(find.text('Proventos'));
      await tester.pumpAndSettle();
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.textContaining('Total registrado:'), findsOneWidget);
      app.settings.hideBalance = true;
      app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(BarChart), findsNothing);
      expect(find.textContaining('R\$'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'cached price line and periods work without network or fake points',
      (tester) async {
    await InvestmentHistory.save('PETR4',
        PriceHistory.parse([point(70, 10), point(15, 11), point(1, 12)], at));
    final app = AppProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: InvestmentPriceChart(ticker: 'PETR4'))))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .single
            .spots
            .length,
        3);
    await tester.tap(find.text('1 mês'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .single
            .spots
            .length,
        2);
    app.settings.hideBalance = true;
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('R\$'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
