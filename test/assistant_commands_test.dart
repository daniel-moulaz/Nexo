import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/sync/assistant_commands.dart';
import 'package:expensy/sync/assistant_more_commands.dart';
import 'package:expensy/investments/investment_repository.dart';
import 'package:expensy/models/transaction_metadata.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Server queue stand-in with the claim/finish rules of the migration.
class _Queue implements AssistantRemote {
  final pending = <AssistantCommand>[];
  final finished = <String, (String, Map<String, Object?>)>{};

  void add(String id, String kind, Map<String, dynamic> args) =>
      pending.add(AssistantCommand(id, kind, args));

  @override
  Future<AssistantCommand?> claim(String datasetId, String deviceId) async =>
      pending.isEmpty ? null : pending.removeAt(0);

  @override
  Future<void> finish(
          String id, String status, Map<String, Object?> result) async =>
      finished[id] = (status, result);

  final reports = <List<String>>[];
  @override
  Future<void> report(String datasetId, String deviceId, String version,
          List<String> kinds) async =>
      reports.add(kinds);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Queue queue;
  late AppProvider app;
  late AssistantCommands assistant;

  Future<double> balance(String id) async =>
      (await DBHelper.getAccounts()).firstWhere((a) => a.id == id).balance;

  Future<void> run() =>
      assistant.run(datasetId: 'd', deviceId: 'device').then((_) {});

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-assistant-');
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, 'db'));
    app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.categories = await DBHelper.getCategories();
    for (final (id, balance) in [('bank', 1000.0), ('card', 0.0)]) {
      await app.addAccount(Account(
          id: id,
          name: id == 'bank' ? 'Banco fictício' : 'Carteira fictícia',
          type: 'bank',
          balance: balance,
          currency: 'BRL',
          colorValue: 0));
    }
    queue = _Queue();
    assistant = AssistantCommands(queue, app);
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> expense([int cents = 3290]) => {
        'type': 'expense',
        'amount_cents': cents,
        'description': 'iFood',
        'account_id': 'bank',
        'category_id': 'food_exp',
        'date': '2026-10-20',
        'note': '',
      };

  test('a request becomes one transaction with the app rules', () async {
    queue.add('r1', 'transaction.add', expense());
    await run();
    expect(queue.finished['r1']!.$1, 'done');
    expect(await balance('bank'), closeTo(967.1, 1e-9));
    final t = (await DBHelper.getTransactions()).single;
    expect(t.id, 'assistant:r1');
    expect(t.date, DateTime(2026, 10, 20, 12));
  });

  test('a request offered again is never applied twice', () async {
    queue.add('r1', 'transaction.add', expense());
    await run();
    // The device stopped before the server heard back: offered again.
    queue.add('r1', 'transaction.add', expense());
    await run();
    expect((await DBHelper.getTransactions()).length, 1);
    expect(await balance('bank'), closeTo(967.1, 1e-9));
    expect(queue.finished['r1']!.$1, 'done');
  });

  test('transfer keeps the total; correction and deletion adjust balance',
      () async {
    queue.add('t', 'transfer.add', {
      'from_account_id': 'bank',
      'to_account_id': 'card',
      'amount_cents': 30000,
      'date': '2026-10-20',
      'note': 'reserva',
    });
    queue.add('e', 'transaction.add', expense());
    await run();
    expect(await balance('bank') + await balance('card'), closeTo(967.1, 1e-9));
    queue.add('u', 'transaction.update',
        {'id': 'assistant:e', 'amount_cents': 5000, 'category_id': 'shopping'});
    await run();
    expect(queue.finished['u']!.$1, 'done');
    expect(await balance('bank'), closeTo(650, 1e-9));
    final fixed = (await DBHelper.getTransactions())
        .firstWhere((t) => t.id == 'assistant:e');
    expect(fixed.categoryId, 'shopping');
    expect(fixed.description, 'iFood', reason: 'untouched fields stay');
    queue.add('d', 'transaction.delete', {'id': 'assistant:e'});
    queue.add('d2', 'transaction.delete', {'id': 'assistant:e'});
    await run();
    expect(await balance('bank'), closeTo(700, 1e-9));
    expect(queue.finished['d2']!.$2['message'], 'Já não existia.');
  });

  test('what the app refuses is reported, nothing changes', () async {
    queue.add('a', 'transaction.add', {...expense(), 'account_id': 'gone'});
    queue.add('c', 'transaction.add', {...expense(), 'category_id': 'gone'});
    queue.add('u', 'transaction.update', {'id': 'missing', 'amount_cents': 1});
    queue.add('x', 'money.send', {});
    await run();
    for (final id in ['a', 'c', 'u', 'x']) {
      expect(queue.finished[id]!.$1, 'rejected', reason: id);
      expect(queue.finished[id]!.$2['reason'], isNotEmpty);
    }
    expect(await DBHelper.getTransactions(), isEmpty);
    expect(await balance('bank'), 1000);
  });

  test('an Open Finance suggestion is confirmed through the inbox', () async {
    await (await DBHelper.database).insert('notification_suggestions', {
      'id': 'pluggy:s1',
      'app_id': 'pluggy',
      'amount_cents': 4590,
      'description': 'Mercado fictício',
      'kind': 'expense',
      'medium': 'bank',
      'occurred_at': DateTime.now()
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch,
    });
    queue.add('s', 'suggestion.confirm',
        {'id': 'pluggy:s1', 'account_id': 'bank', 'category_id': 'food_exp'});
    queue.add('s2', 'suggestion.confirm',
        {'id': 'pluggy:s1', 'account_id': 'bank', 'category_id': 'food_exp'});
    await run();
    expect(queue.finished['s']!.$1, 'done');
    expect(queue.finished['s2']!.$2['message'], 'Já estava confirmada.');
    expect(
        (await DBHelper.getTransactions()).single.id, 'notification:pluggy:s1');
    expect(await balance('bank'), closeTo(954.1, 1e-9));
    final row = (await (await DBHelper.database).query(
            'notification_suggestions',
            where: 'id = ?',
            whereArgs: ['pluggy:s1']))
        .single;
    expect(row['status'], 'confirmed');
  });

  test('a recurring bill is settled with its real amount, once', () async {
    final due = DateTime.now();
    final day = DateTime(due.year, due.month, due.day);
    await app.addRecurring(RecurringPayment(
        id: 'luz',
        name: 'Água, luz e internet',
        accountId: 'bank',
        categoryId: 'bills',
        amount: 190,
        freqVal: 1,
        freqUnit: 'months',
        startDate: day,
        nextDate: day));
    final iso = day.toIso8601String().substring(0, 10);
    queue.add('p', 'recurring.pay',
        {'id': 'luz', 'expected_date': iso, 'amount_cents': 19815});
    // Asked twice (e.g. Claude retried): the forecast moved on, so the
    // second request is refused instead of paying next month.
    queue.add('p2', 'recurring.pay',
        {'id': 'luz', 'expected_date': iso, 'amount_cents': 19815});
    await run();
    expect(queue.finished['p']!.$1, 'done');
    expect(queue.finished['p2']!.$1, 'rejected');
    final paid = (await DBHelper.getTransactions()).single;
    expect(paid.amount, 198.15);
    expect(paid.id, startsWith('recurring:luz:'));
    expect(await balance('bank'), closeTo(801.85, 1e-9));
    expect(app.recurring.single.nextDate.month, (day.month % 12) + 1);
  });

  test('skip, budgets, categories and settling a pending entry', () async {
    final day = DateTime.now();
    await app.addRecurring(RecurringPayment(
        id: 'gym',
        name: 'Academia',
        accountId: 'bank',
        categoryId: 'health',
        amount: 99,
        freqVal: 1,
        freqUnit: 'months',
        startDate: day,
        nextDate: DateTime(day.year, day.month, day.day)));
    queue.add('s', 'recurring.skip', {'id': 'gym'});
    queue.add('b', 'budget.set', {
      'category_id': 'food_exp',
      'amount_cents': 50000,
      'period': 'monthly'
    });
    queue.add('b2', 'budget.set', {
      'category_id': 'food_exp',
      'amount_cents': 60000,
      'period': 'monthly'
    });
    queue.add('c', 'category.add', {'name': 'Pets', 'type': 'expense'});
    queue.add('c2', 'category.add', {'name': 'pets', 'type': 'expense'});
    await run();
    expect(queue.finished['s']!.$1, 'done');
    expect(await DBHelper.getTransactions(), isEmpty,
        reason: 'skip records nothing');
    expect(app.budgets.single.amount, 600,
        reason: 'set updates, not duplicates');
    expect(app.categories.where((c) => c.name.toLowerCase() == 'pets'),
        hasLength(1));

    await app.addTransaction(
        AppTransaction(
            id: 'boleto',
            type: 'expense',
            amount: 80,
            description: 'Boleto',
            accountId: 'bank',
            categoryId: 'bills',
            date: DateTime.now()),
        metadata: const TransactionMetadata(
            transactionId: 'boleto', status: 'pending'));
    expect(await balance('bank'), 1000, reason: 'pending does not debit');
    queue.add('t', 'transaction.settle', {'id': 'boleto'});
    await run();
    expect(queue.finished['t']!.$1, 'done');
    expect(await balance('bank'), 920);
  });

  test('goals move money between account and reserve; invoices are transfers',
      () async {
    await app.addSavingsGoal(SavingsGoal(
        id: 'g',
        name: 'Reserva',
        targetAmount: 5000,
        currency: 'BRL',
        colorValue: 0));
    queue.add('d', 'goal.move', {
      'goal_id': 'g',
      'account_id': 'bank',
      'amount_cents': 20000,
      'direction': 'deposit',
      'note': ''
    });
    await run();
    expect(queue.finished['d']!.$1, 'done');
    expect(await balance('bank'), 800);

    await app.addAccount(Account(
        id: 'cc',
        name: 'Cartão fictício',
        type: 'credit',
        balance: 0,
        currency: 'BRL',
        colorValue: 0,
        statementDay: 10,
        dueDay: 20));
    app.accounts = await DBHelper.getAccounts();
    await app.addTransaction(AppTransaction(
        id: 'compra',
        type: 'expense',
        amount: 150,
        description: 'Compra',
        accountId: 'cc',
        categoryId: 'shopping',
        date: DateTime.now()));
    final spentBefore = (await DBHelper.getTransactions())
        .where((t) => t.type == 'expense')
        .length;
    queue.add('f', 'invoice.pay', {
      'card_id': 'cc',
      'from_account_id': 'bank',
      'invoice': 'current',
    });
    await run();
    expect(queue.finished['f']!.$1, 'done', reason: '${queue.finished['f']}');
    expect(await balance('bank'), 650);
    expect(await balance('cc'), closeTo(0, 1e-9));
    final card = (await DBHelper.getTransactions())
        .where((t) => t.type == 'expense' && t.accountId == 'cc')
        .length;
    expect(card, 1, reason: 'paying the invoice is not a new expense');
    expect(spentBefore, greaterThan(0));
  });

  group('everything else the app does', () {
    late AssistantMoreCommands more;
    setUp(() => more = AssistantMoreCommands(app));

    test('a balance adjustment is neither spending nor income', () async {
      queue.add('adj', 'account.adjust',
          {'id': 'bank', 'expected_cents': 100000, 'balance_cents': 106726});
      // Asked again after it was applied: the balance already matches.
      queue.add('adj2', 'account.adjust',
          {'id': 'bank', 'expected_cents': 100000, 'balance_cents': 106726});
      // From a balance that is no longer the real one: refused.
      queue.add('adj3', 'account.adjust',
          {'id': 'bank', 'expected_cents': 100000, 'balance_cents': 90000});
      await run();
      expect(queue.finished['adj']!.$1, 'done');
      expect(queue.finished['adj2']!.$1, 'done');
      expect(queue.finished['adj3']!.$1, 'rejected');
      expect(await balance('bank'), closeTo(1067.26, 1e-9));
      expect(await DBHelper.getTransactions(), isEmpty);
    });

    test('accounts and categories: create, change, delete only if unused',
        () async {
      await more.handle('c1', 'account.add', {
        'name': 'Cartão fictício',
        'type': 'credit',
        'balance_cents': 0,
        'statement_day': 3,
        'due_day': 10,
        'credit_limit_cents': 500000,
      });
      // Applied twice (marker lost): still one account.
      await more.handle('c1', 'account.add', {
        'name': 'Cartão fictício',
        'type': 'credit',
        'balance_cents': 0,
      });
      final card = app.accounts.where((a) => a.name == 'Cartão fictício');
      expect(card, hasLength(1));
      expect(card.single.dueDay, 10);
      await more.handle('u', 'account.update',
          {'id': card.single.id, 'name': 'Cartão renomeado', 'due_day': 15});
      expect(app.accountById(card.single.id)!.name, 'Cartão renomeado');
      expect(app.accountById(card.single.id)!.dueDay, 15);
      expect(app.accountById(card.single.id)!.statementDay, 3);

      queue.add('t', 'transaction.add', expense());
      await run();
      await expectLater(more.handle('d', 'account.delete', {'id': 'bank'}),
          throwsA(isA<FormatException>()));
      await more.handle('d2', 'account.delete', {'id': card.single.id});
      expect(app.accountById(card.single.id), isNull);

      await expectLater(
          more.handle('cd', 'category.delete', {'id': 'food_exp'}),
          throwsA(isA<StateError>()));
      final unused = app.categories.firstWhere(
          (c) => !app.transactions.any((t) => t.categoryId == c.id));
      await more.handle('cd2', 'category.delete', {'id': unused.id});
      expect(app.categories.any((c) => c.id == unused.id), isFalse);
    });

    test('goals, assets, wishlist and money lent', () async {
      await more.handle('g', 'goal.add', {
        'name': 'Viagem',
        'target_cents': 300000,
        'target_date': '2027-06-01'
      });
      await more.handle('g', 'goal.add', {'name': 'Viagem', 'target_cents': 1});
      expect(app.savingsGoals, hasLength(1));
      final goal = app.savingsGoals.single;
      await more
          .handle('gu', 'goal.update', {'id': goal.id, 'target_cents': 350000});
      expect(app.savingsGoals.single.targetAmount, 3500);
      await app.contributeToGoal(
          goalId: goal.id, fromAccountId: 'bank', amount: 100);
      await expectLater(more.handle('gd', 'goal.delete', {'id': goal.id}),
          throwsA(isA<StateError>()));

      await more.handle('a', 'asset.add',
          {'name': 'Carro', 'value_cents': 4500000, 'notes': ''});
      await more.handle('a', 'asset.add', {'name': 'Carro', 'value_cents': 1});
      expect(app.assets, hasLength(1));
      await more.handle('au', 'asset.update',
          {'id': app.assets.single.id, 'value_cents': 4000000});
      expect(app.assets.single.value, 40000);
      await more.handle('ad', 'asset.delete', {'id': app.assets.single.id});
      expect(app.assets, isEmpty);

      await more.handle('w', 'wishlist.add',
          {'name': 'Fone', 'price_cents': 59990, 'priority': 'high'});
      await more.handle('wu', 'wishlist.update',
          {'id': app.wishlist.single.id, 'purchased': true});
      expect(app.wishlist.single.isPurchased, isTrue);
      await more
          .handle('wd', 'wishlist.delete', {'id': app.wishlist.single.id});
      expect(app.wishlist, isEmpty);

      final before = await balance('bank');
      await more.handle('l', 'lended.add', {
        'person': 'Pessoa fictícia',
        'type': 'lent',
        'amount_cents': 5000,
        'account_id': 'bank',
        'date': '2026-10-20',
      });
      await more.handle('l', 'lended.add', {
        'person': 'Pessoa fictícia',
        'type': 'lent',
        'amount_cents': 5000,
        'account_id': 'bank',
        'date': '2026-10-20',
      });
      expect(app.lendedPeople, hasLength(1));
      expect(app.lended, hasLength(1));
      expect(await balance('bank'), closeTo(before - 50, 1e-9));
      await more.handle('ls', 'lended.settle', {'id': app.lended.single.id});
      await more.handle('ls', 'lended.settle', {'id': app.lended.single.id});
      expect(await balance('bank'), closeTo(before, 1e-9));
    });

    test('investments: buy with cash, a retried sale counts once, price',
        () async {
      await more.handle('i', 'investment.add', {
        'name': 'CDB fictício',
        'asset_class': 'Renda fixa',
        'quantity_micros': 1000000,
        'cents': 20000,
        'date': '2026-10-01',
        'cash_account_id': 'bank',
      });
      expect(await balance('bank'), closeTo(800, 1e-9));
      final sale = {
        'investment_id': 'assistant-inv:i',
        'kind': 'sell',
        'quantity_micros': 500000,
        'cents': 11000,
        'date': '2026-10-10',
        'cash_account_id': 'bank',
        'created_at': '2026-10-21T10:00:00.000Z',
      };
      await more.handle('s', 'investment.operation', sale);
      await more.handle('s', 'investment.operation', sale);
      expect(await balance('bank'), closeTo(910, 1e-9));
      await more.handle('p', 'investment.price',
          {'investment_id': 'assistant-inv:i', 'price_cents': 24000});
      final position = (await InvestmentRepository().load()).single;
      expect(position.quantity, 500000);
      expect(position.value, 12000);
    });

    test('a loan installment is paid once, or skipped', () async {
      await app.addLoan(Loan(
          id: 'loan',
          name: 'Empréstimo fictício',
          principal: 1200,
          currency: 'BRL',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2027, 1, 1)));
      final before = await balance('bank');
      await more.handle('lp', 'loan.pay',
          {'id': 'loan', 'amount_cents': 10000, 'account_id': 'bank'});
      await more.handle('lp', 'loan.pay',
          {'id': 'loan', 'amount_cents': 10000, 'account_id': 'bank'});
      expect(app.loanPayments, hasLength(1));
      expect(await balance('bank'), closeTo(before - 100, 1e-9));
      await more.handle('sk', 'loan.skip', {'id': 'loan'});
      expect(app.loanPayments, hasLength(2));
      expect(await balance('bank'), closeTo(before - 100, 1e-9));
    });
  });

  test('the app knows exactly the server list, and every kind is handled',
      () async {
    final sql = File('supabase/migrations/202610210005_mcp_all_actions.sql')
        .readAsStringSync()
        .split('create or replace')
        .first;
    final server = RegExp(r"'([a-z]+\.[a-z_]+)'")
        .allMatches(sql)
        .map((m) => m.group(1)!)
        .toSet();
    expect(AssistantCommands.supportedKinds.toSet(), server);
    PackageInfo.setMockInitialValues(
        appName: 'Nexo',
        packageName: 'com.ma.expensy',
        version: '1.11.0',
        buildNumber: '36',
        buildSignature: '');
    for (final kind in AssistantCommands.supportedKinds) {
      queue.add('k-$kind', kind, {});
    }
    while (queue.pending.isNotEmpty) {
      await run(); // at most 20 per round
    }
    expect(queue.reports.single, AssistantCommands.supportedKinds);
    for (final kind in AssistantCommands.supportedKinds) {
      final (status, result) = queue.finished['k-$kind']!;
      // Empty arguments are refused, but never as an unknown request.
      expect(result['reason'], isNot('Pedido desconhecido.'), reason: kind);
      expect(status, isNotEmpty);
    }
  });
}
