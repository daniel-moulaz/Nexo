import 'dart:io';

import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/screens/balance_check_screen.dart';
import 'package:nexo/services/balance_check.dart';
import 'package:nexo/services/pluggy_inbox.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Remote implements PluggyRemote {
  _Remote(this.rows);
  List<BankAccountSnapshot> rows;
  final links = <String, String?>{};
  @override
  Future<List<BankAccountSnapshot>> accounts() async => rows;
  @override
  Future<void> link(String accountId, String? nexoAccountId) async {
    links[accountId] = nexoAccountId;
    rows = [
      for (final r in rows)
        r.accountId == accountId
            ? BankAccountSnapshot(
                accountId: r.accountId,
                bank: r.bank,
                type: r.type,
                name: r.name,
                currency: r.currency,
                balanceCents: r.balanceCents,
                bankUpdatedAt: r.bankUpdatedAt,
                nexoAccountId: nexoAccountId)
            : r
    ];
  }

  @override
  Future<List<PluggyItem>> refresh({bool force = false}) async => const [];
  @override
  Future<List<PluggyItem>> items() async => const [];
  @override
  Future<void> addItem(String itemId, String label) async {}
  @override
  Future<void> removeItem(String itemId) async {}
  @override
  Future<List<Map<String, dynamic>>> suggestions(int sinceMs) async => const [];
  @override
  Future<void> decide(List<Map<String, Object?>> decisions) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppProvider app;

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-balance-');
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, 'db'));
    app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.categories = await DBHelper.getCategories();
    await app.addAccount(Account(
        id: 'mp',
        name: 'Conta principal',
        type: 'bank',
        balance: 10,
        currency: 'BRL',
        colorValue: 0));
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('link, compare and adjust neutrally in one tap', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final remote = _Remote([
      BankAccountSnapshot(
          accountId: 'p-mp',
          bank: 'Mercado Pago',
          type: 'BANK',
          name: 'Conta',
          currency: 'BRL',
          balanceCents: -3300,
          bankUpdatedAt: DateTime.now().subtract(const Duration(hours: 1)))
    ]);
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BalanceCheckScreen(remote: remote))));
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Mercado Pago'), findsOneWidget);
    expect(find.text('Ajustar o Nexo (neutro)'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conta principal').last);
    await settle();
    expect(remote.links['p-mp'], 'mp');
    expect(find.textContaining('Diferença'), findsOneWidget);

    await tester.tap(find.text('Ajustar o Nexo (neutro)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('não conta como gasto'), findsOneWidget);
    await tester.tap(find.text('Ajustar'));
    await settle();
    final mp = (await tester.runAsync(DBHelper.getAccounts))!
        .firstWhere((a) => a.id == 'mp');
    expect(mp.balance, closeTo(-33, 1e-9));
    expect((await tester.runAsync(DBHelper.getTransactions))!, isEmpty,
        reason: 'a neutral adjustment is neither spending nor income');
    expect(find.text('Bate com o banco'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('every bank in the main account: one total, one adjust',
      (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final at = DateTime.now().subtract(const Duration(hours: 1));
    BankAccountSnapshot bank(String id, String name, int cents) =>
        BankAccountSnapshot(
            accountId: id,
            bank: name,
            type: 'BANK',
            name: 'Conta',
            currency: 'BRL',
            balanceCents: cents,
            nexoAccountId: 'mp',
            bankUpdatedAt: at);
    final remote = _Remote([
      bank('p-nu', 'Nubank', 10000),
      bank('p-in', 'Inter', 5000),
      bank('p-btg', 'BTG', -1000),
    ]);
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BalanceCheckScreen(remote: remote))));
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.text('Conta principal · soma de 3 contas'), findsOneWidget);
    expect(find.textContaining('Somada com mais 2 conta(s)'), findsNWidgets(3));
    expect(find.text('Ajustar o Nexo (neutro)'), findsOneWidget);

    await tester.tap(find.text('Ajustar o Nexo (neutro)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajustar'));
    await settle();
    final mp = (await tester.runAsync(DBHelper.getAccounts))!
        .firstWhere((a) => a.id == 'mp');
    expect(mp.balance, closeTo(140, 1e-9));
    expect((await tester.runAsync(DBHelper.getTransactions))!, isEmpty);
    expect(find.text('Bate com o banco'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
