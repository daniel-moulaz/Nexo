import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/investments/investment_repository.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/services/budget_insights.dart';
import 'package:nexo/services/envelopes.dart';
import 'package:nexo/services/finance_rules.dart';
import 'package:nexo/services/import_rules_service.dart';
import 'package:nexo/sync/assistant_commands.dart';
import 'package:nexo/sync/ledger_capture.dart';
import 'package:nexo/sync/ledger_sync.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Server queue stand-in (claim in order, finish once, undo data kept).
class _Queue implements AssistantRemote {
  final pending = <AssistantCommand>[];
  final finished = <String, (String, Map<String, Object?>)>{};
  final undone = <String>[];

  void add(String id, String kind, Map<String, dynamic> args) =>
      pending.add(AssistantCommand(id, kind, args,
          createdAt: DateTime.utc(2026, 10, 29, 12)));

  @override
  Future<AssistantCommand?> claim(String datasetId, String deviceId) async =>
      pending.isEmpty ? null : pending.removeAt(0);

  @override
  Future<void> finish(
          String id, String status, Map<String, Object?> result) async =>
      finished[id] = (status, result);

  @override
  Future<void> report(String datasetId, String deviceId, String version,
      List<String> kinds, Map<String, Object?> settings) async {}

  @override
  Future<void> markUndone(String id, String by) async => undone.add(id);

  @override
  Future<List<AssistantHistoryItem>> history(String datasetId,
          {int limit = 50}) async =>
      const [];

  @override
  Future<Map<String, Object?>?> undoData(String id) async {
    // As the server keeps it: JSON, then read back.
    final undo = finished[id]?.$2['undo'];
    return undo == null
        ? null
        : (jsonDecode(jsonEncode(undo)) as Map).cast<String, Object?>();
  }
}

// Synthetic ledgers only, in temporary folders.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Queue queue;
  late AppProvider app;
  late AssistantCommands assistant;
  var n = 0;

  Future<double> balance(String id) async =>
      (await DBHelper.getAccounts()).firstWhere((a) => a.id == id).balance;

  /// As on a synced device: every operation is journaled (needed to undo).
  Future<void> capture() async =>
      LedgerCapture.install(await DBHelper.database);

  Future<(String, Map<String, Object?>)> send(
      String kind, Map<String, dynamic> args,
      {String? id}) async {
    final cid = id ?? 'req-${n++}';
    queue.add(cid, kind, args);
    await assistant.run(datasetId: 'd', deviceId: 'device');
    return queue.finished[cid]!;
  }

  /// Undo through the queue, with the data as it comes back from JSON.
  Future<(String, Map<String, Object?>)> undo(String requestId) async =>
      send('request.undo', {
        'request_id': requestId,
        'undo': await queue.undoData(requestId),
      });

  Future<TransactionMetadata> metaOf(String id) async =>
      TransactionMetadata.fromMap((await (await DBHelper.database).query(
              'transaction_metadata',
              where: 'transaction_id = ?',
              whereArgs: [id]))
          .single);

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-parity-');
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, 'db'));
    app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.categories = await DBHelper.getCategories();
    await app.addAccount(Account(
        id: 'bank',
        name: 'Conta fictícia',
        type: 'bank',
        balance: 1000,
        currency: 'BRL',
        colorValue: 0));
    await app.addAccount(Account(
        id: 'nu',
        name: 'Cartão fictício',
        type: 'credit',
        balance: 0,
        currency: 'BRL',
        colorValue: 0,
        statementDay: 19,
        dueDay: 26,
        creditLimit: 650));
    queue = _Queue();
    assistant = AssistantCommands(queue, app);
    n = 0;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  AppTransaction expense(String id, double amount,
          {String account = 'bank',
          String category = 'food_exp',
          DateTime? date}) =>
      AppTransaction(
          id: id,
          type: 'expense',
          amount: amount,
          description: id,
          accountId: account,
          categoryId: category,
          date: date ?? DateTime(2026, 10, 15, 12),
          currency: 'BRL');

  test('Classificar and Ajustar (por tipo de gasto), then undone', () async {
    await capture();
    await app.seedSharedSettings(); // what a synced device does first
    final (refused, why) = await send('category.envelope', {
      'assignments': [
        {'id': 'food_exp', 'envelope': 'fixed'},
        {'id': 'salary', 'envelope': 'fixed'},
      ]
    });
    expect(refused, 'rejected');
    expect(why['reason'], contains('receita'));
    expect(
        app.categories.firstWhere((c) => c.id == 'food_exp').envelope, isNull,
        reason: 'nothing applied when one item is refused');

    final (done, _) = await send(
        'category.envelope',
        {
          'assignments': [
            {'id': 'food_exp', 'envelope': 'fixed'},
            {'id': 'entertainment', 'envelope': 'pleasures'},
          ]
        },
        id: 'classify');
    expect(done, 'done');
    expect(
        app.categories.firstWhere((c) => c.id == 'food_exp').envelope, 'fixed');

    const shares = {
      'fixed': 50,
      'comfort': 10,
      'goals': 10,
      'pleasures': 10,
      'knowledge': 5,
      'freedom': 15
    };
    final (set, result) = await send(
        'settings.set',
        {
          'values': {'referenceIncome': 1800, 'envelopeShares': shares}
        },
        id: 'targets');
    expect(set, 'done');
    expect(result['shared'], ['referenceIncome', 'envelopeShares']);
    expect(app.settings.referenceIncome, 1800);
    expect(app.settings.envelopeShares, shares);
    expect((await DBHelper.getSharedSettings()).keys,
        containsAll(['referenceIncome', 'envelopeShares']));

    final (bad, badWhy) = await send('settings.set', {
      'values': {
        'envelopeShares': {...shares, 'fixed': 60}
      }
    });
    expect(bad, 'rejected');
    expect(badWhy['reason'], contains('110%'));

    expect((await undo('targets')).$1, 'done');
    expect(app.settings.referenceIncome, 0, reason: 'back to the default');
    expect(app.settings.envelopeShares, defaultEnvelopeShares);
    expect(queue.undone, ['targets']);
    expect((await undo('classify')).$1, 'done');
    expect(
        app.categories.firstWhere((c) => c.id == 'food_exp').envelope, isNull);
    final (again, againWhy) = await undo('classify');
    expect(again, 'rejected', reason: 'undone once');
    expect(againWhy['reason'], contains('mudou'));
  });

  test('undo works on rows recorded before a column existed', () async {
    await capture();
    // Devices synced before schema 26 recorded categories without
    // `envelope`; found on a copy of a real ledger.
    final db = await DBHelper.database;
    final state = await db.query('sync_entity_state',
        where: 'table_name = ? AND row_key = ?',
        whereArgs: ['categories', 'food_exp']);
    final old = (jsonDecode(state.single['value_json'] as String) as Map)
      ..remove('envelope');
    await db.update('sync_entity_state', {'value_json': jsonEncode(old)},
        where: 'table_name = ? AND row_key = ?',
        whereArgs: ['categories', 'food_exp']);
    await send(
        'category.envelope',
        {
          'assignments': [
            {'id': 'food_exp', 'envelope': 'fixed'}
          ]
        },
        id: 'stale');
    expect((await undo('stale')).$1, 'done');
    expect(
        app.categories.firstWhere((c) => c.id == 'food_exp').envelope, isNull);
  });

  test('full edit of an entry: pending to paid moves the balance once',
      () async {
    await capture();
    await app.addTransaction(expense('light', 150, category: 'bills'),
        metadata: TransactionMetadata(
            transactionId: 'light',
            status: 'pending',
            dueDate: DateTime(2026, 11, 5)));
    expect(await balance('bank'), 1000, reason: 'pending is not paid');
    final (status, _) = await send(
        'transaction.edit',
        {
          'id': 'light',
          'status': 'paid',
          'subcategory': 'Energia',
          'due_date': null,
        },
        id: 'paid');
    expect(status, 'done');
    expect(await balance('bank'), 850);
    final m = await metaOf('light');
    expect([m.status, m.subcategory, m.dueDate], ['paid', 'Energia', null]);

    expect((await undo('paid')).$1, 'done');
    expect(await balance('bank'), 1000);
    expect((await metaOf('light')).status, 'pending');

    final (wrong, why) =
        await send('transaction.edit', {'id': 'light', 'type': 'income'});
    expect(wrong, 'rejected');
    expect(why['reason'], contains('despesa'));

    // "É a renda do mês?": a manual income counts as the recurring salary.
    await app.addRecurring(RecurringPayment(
        id: 'sal',
        name: 'Salário',
        accountId: 'bank',
        categoryId: 'salary',
        amount: 1800,
        paymentType: 'income',
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(2026, 11, 5),
        nextDate: DateTime(2026, 11, 5)));
    await app.addTransaction(AppTransaction(
        id: 'pix',
        type: 'income',
        amount: 1800,
        description: 'Pix do trabalho',
        accountId: 'bank',
        categoryId: 'salary',
        date: DateTime(2026, 10, 5, 12),
        currency: 'BRL'));
    await send('transaction.edit', {'id': 'pix', 'recurring_income_id': 'sal'});
    expect((await metaOf('pix')).source, 'recurring:sal');
    expect(await balance('bank'), 2800, reason: 'only metadata changed');
  });

  test('batch: recategorize, neutral adjustment, delete; transfers stay out',
      () async {
    await capture();
    for (final (id, v, c) in [
      ('a', 10.0, 'food_exp'),
      ('b', 20.0, 'food_exp'),
      ('c', 30.0, 'shopping')
    ]) {
      await app.addTransaction(expense(id, v, category: c));
    }
    await app.addTransfer(fromId: 'bank', toId: 'nu', fromAmount: 100);
    expect(await balance('bank'), 840);

    final (s1, r1) = await send('transaction.bulk_update', {
      'ids': ['a', 'b'],
      'category_id': 'shopping',
      'subcategory': 'Feira',
      'expense_class': 'extraordinary',
    });
    expect([s1, r1['count']], ['done', 2]);
    expect(app.transactions.where((t) => t.categoryId == 'shopping'),
        hasLength(3));
    expect((await metaOf('a')).expenseClass, 'extraordinary');
    expect(await balance('bank'), 840, reason: 'classification only');

    final transfer = app.transactions
        .firstWhere((t) => t.description == 'Transferência enviada');
    final (s2, r2) = await send('transaction.bulk_update', {
      'ids': ['a', transfer.id],
      'category_id': 'food_exp'
    });
    expect(s2, 'rejected');
    expect(r2['reason'], contains('Transferências'));
    expect(
        app.transactions.firstWhere((t) => t.id == 'a').categoryId, 'shopping',
        reason: 'all or nothing');

    // An old balance fix recorded as income becomes a neutral adjustment.
    await app.addTransaction(AppTransaction(
        id: 'fix',
        type: 'income',
        amount: 67.26,
        description: 'Ajuste',
        accountId: 'bank',
        categoryId: 'gift',
        date: DateTime(2026, 10, 8, 12),
        currency: 'BRL'));
    final before = await balance('bank');
    expect(
        (await send('transaction.neutralize', {
          'ids': ['fix']
        }))
            .$1,
        'done');
    expect(await balance('bank'), before, reason: 'the balance stays');
    final fixMeta = await metaOf('fix');
    expect(fixMeta.source, 'opening_balance');
    expect(
        FinanceRules.isNeutral(
            app.transactions.firstWhere((t) => t.id == 'fix'), fixMeta),
        isTrue,
        reason: 'no longer income');

    final (s3, r3) = await send(
        'transaction.bulk_delete',
        {
          'ids': ['a', 'c']
        },
        id: 'wipe');
    expect([s3, r3['count']], ['done', 2]);
    expect(await balance('bank'), closeTo(before + 40, 1e-9));
    expect((await undo('wipe')).$1, 'done');
    expect(await balance('bank'), closeTo(before, 1e-9));
    expect(app.transactions.map((t) => t.id), containsAll(['a', 'c']));
    expect((await metaOf('a')).expenseClass, 'extraordinary',
        reason: 'metadata comes back too');
  });

  test('create like the form: pending with due date, installments, once',
      () async {
    final water = {
      'type': 'expense',
      'amount_cents': 9000,
      'description': 'Água',
      'account_id': 'bank',
      'category_id': 'bills',
      'date': '2026-10-29',
      'note': '',
      'status': 'pending',
      'due_date': '2026-11-10',
      'subcategory': 'Água',
    };
    final (s1, r1) = await send('transaction.create', water, id: 'water');
    expect(s1, 'done');
    expect(await balance('bank'), 1000, reason: 'pending does not leave');
    final m = await metaOf(r1['transaction_id'] as String);
    expect([m.status, m.subcategory, m.dueDate, m.source],
        ['pending', 'Água', DateTime(2026, 11, 10, 12), 'assistant']);
    // The same request offered again (lost answer) records nothing new.
    queue.add('water', 'transaction.create', water);
    await assistant.run(datasetId: 'd', deviceId: 'device');
    expect(
        app.transactions.where((t) => t.description == 'Água'), hasLength(1));

    final (s2, r2) = await send('transaction.create', {
      'type': 'expense',
      'amount_cents': 120000,
      'description': 'Notebook',
      'account_id': 'nu',
      'category_id': 'shopping',
      'date': '2026-10-29',
      'installments': 10,
    });
    expect([s2, r2['message']], ['done', 'Lançado em 10 parcelas.']);
    expect(app.transactions.where((t) => t.description == 'Notebook'),
        hasLength(10));
    expect(await balance('nu'), closeTo(-1200, 1e-9));
    final (s3, _) = await send('transaction.create', {
      'type': 'income',
      'amount_cents': 100,
      'description': 'x',
      'account_id': 'bank',
      'category_id': 'food_exp',
      'date': '2026-10-29',
    });
    expect(s3, 'rejected');
  });

  test('split into installments keeps the total, on the bank and the card',
      () async {
    await capture();
    await app.addTransaction(expense('tv', 1000));
    final (s1, _) = await send(
        'transaction.split', {'id': 'tv', 'installments': 3},
        id: 'split');
    expect(s1, 'done');
    final parts = (await DBHelper.getTransactions())
        .where((t) => t.id.startsWith('tv'))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    expect(parts.map((t) => t.amount), [333.34, 333.33, 333.33]);
    expect(parts[2].date, DateTime(2026, 12, 15));
    expect((await metaOf('tv:installment:2')).status, 'pending');
    expect(await balance('bank'), closeTo(666.66, 1e-9),
        reason: 'only the first installment left the bank');

    await app.addTransaction(expense('phone', 100, account: 'nu'));
    await send('transaction.split', {'id': 'phone', 'installments': 3});
    expect(await balance('nu'), closeTo(-100, 1e-9),
        reason: 'on the card the debt stays the same');
    expect((await metaOf('phone:installment:3')).status, 'paid');
    final (again, why) =
        await send('transaction.split', {'id': 'phone', 'installments': 2});
    expect(again, 'rejected');
    expect(why['reason'], contains('parcela'));

    expect((await undo('split')).$1, 'done');
    expect(await balance('bank'), closeTo(0, 1e-9));
    expect(app.transactions.where((t) => t.id.startsWith('tv:')), isEmpty);
    expect(app.transactions.firstWhere((t) => t.id == 'tv').amount, 1000);
  });

  test('merge categories moves entries, recurring and budget; undone',
      () async {
    await capture();
    await app.addTransaction(expense('course', 200, category: 'education'));
    await app.addRecurring(RecurringPayment(
        id: 'school',
        name: 'Escola',
        accountId: 'bank',
        categoryId: 'education',
        amount: 300,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(2026, 11, 10),
        nextDate: DateTime(2026, 11, 10)));
    await app.addBudget(Budget(
        id: 'b-edu',
        categoryId: 'education',
        amount: 500,
        period: 'monthly',
        createdAt: DateTime(2026, 9, 1)));
    final (status, result) = await send(
        'category.merge', {'from_id': 'education', 'into_id': 'other_exp'},
        id: 'merge');
    expect(status, 'done');
    expect(result['message'], contains('1 lançamento'));
    expect(app.categories.any((c) => c.id == 'education'), isFalse);
    expect(app.transactions.single.categoryId, 'other_exp');
    expect(app.recurring.single.categoryId, 'other_exp');
    expect(app.budgets.single.categoryId, 'other_exp');
    expect(await balance('bank'), 800, reason: 'no money moved');

    expect((await undo('merge')).$1, 'done');
    expect(app.categories.any((c) => c.id == 'education'), isTrue);
    expect(app.transactions.single.categoryId, 'education');
    expect(app.recurring.single.categoryId, 'education');
    expect(app.budgets.single.categoryId, 'education');

    final (wrong, _) = await send(
        'category.merge', {'from_id': 'education', 'into_id': 'salary'});
    expect(wrong, 'rejected');
  });

  test('budget in full or proportional in the month it starts', () async {
    final now = DateTime.now();
    final (s1, r1) = await send('budget.save', {
      'category_id': 'food_exp',
      'amount_cents': 40000,
      'period': 'monthly'
    });
    expect(s1, 'done');
    final b = app.budgets.single;
    expect(r1['limit_now'], closeTo(budgetWindow(b, now).limit, .001),
        reason: 'a new budget counts from today, as in the screen');
    await send('budget.save', {
      'id': b.id,
      'category_id': 'food_exp',
      'amount_cents': 40000,
      'full_period': true
    });
    expect(app.budgetLimit(app.budgets.single), 400);
    expect(app.budgets.single.createdAt, DateTime(now.year, now.month));
    await send('budget.save', {
      'id': b.id,
      'category_id': 'food_exp',
      'amount_cents': 40000,
      'full_period': false
    });
    expect(app.budgets.single.createdAt.day, now.day);
    await app.updateSetting('weekStart', 'sunday');
    await send('budget.save', {
      'category_id': 'shopping',
      'amount_cents': 10000,
      'period': 'weekly',
      'full_period': true
    });
    final weekly = app.budgets.firstWhere((x) => x.categoryId == 'shopping');
    expect(weekly.createdAt.weekday, DateTime.sunday);
    expect(app.budgetLimit(weekly), 100);
    final (wrong, _) = await send(
        'budget.save', {'category_id': 'salary', 'amount_cents': 100});
    expect(wrong, 'rejected');
  });

  test('card details: payment account, minimum, limit; refused on a bank',
      () async {
    final (s1, _) = await send('account.edit', {
      'id': 'nu',
      'linked_account_id': 'bank',
      'min_payment_cents': 6500,
      'reminder_enabled': false,
      'credit_limit_cents': 80000,
    });
    expect(s1, 'done');
    final nu = app.accountById('nu')!;
    expect([nu.linkedAccountId, nu.minPaymentAmount, nu.creditLimit],
        ['bank', 65, 800]);
    expect([nu.statementDay, nu.dueDay], [19, 26], reason: 'kept');
    await send('account.edit', {'id': 'nu', 'credit_limit_cents': null});
    expect(app.accountById('nu')!.creditLimit, isNull);
    expect((await send('account.edit', {'id': 'bank', 'due_day': 10})).$1,
        'rejected');
    expect(
        (await send('account.edit', {'id': 'nu', 'linked_account_id': 'nu'}))
            .$1,
        'rejected');
    expect(await balance('bank'), 1000, reason: 'details never move money');
  });

  test('goal only on paper: no account moves; completion; undone', () async {
    await capture();
    await app.addSavingsGoal(SavingsGoal(
        id: 'trip',
        name: 'Viagem',
        targetAmount: 1000,
        currency: 'BRL',
        colorValue: 0));
    await app.contributeToGoal(
        goalId: 'trip', fromAccountId: 'bank', amount: 300);
    expect(await balance('bank'), 700);
    final (s1, _) = await send('goal.adjust',
        {'goal_id': 'trip', 'amount_cents': 10000, 'direction': 'withdraw'},
        id: 'paper');
    expect(s1, 'done');
    expect(app.savingsGoals.single.currentAmount, 200);
    expect(await balance('bank'), 700, reason: 'the reserve was bookkeeping');
    expect(app.savingsContributions.where((c) => c.accountId.isEmpty),
        hasLength(1));
    expect(
        (await send('goal.adjust', {
          'goal_id': 'trip',
          'amount_cents': 90000,
          'direction': 'withdraw'
        }))
            .$1,
        'rejected');
    await send('goal.edit', {'id': 'trip', 'completed': true});
    expect(app.savingsGoals.single.isCompleted, isTrue);
    await send('goal.edit', {'id': 'trip', 'completed': false});
    expect(app.savingsGoals.single.isCompleted, isFalse);
    expect((await undo('paper')).$1, 'done');
    expect(app.savingsGoals.single.currentAmount, 300);
  });

  test('recurring details: frequency, end, kind, notes', () async {
    await app.addRecurring(RecurringPayment(
        id: 'net',
        name: 'Internet',
        accountId: 'bank',
        categoryId: 'bills',
        amount: 99.9,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(2026, 11, 10),
        nextDate: DateTime(2026, 11, 10),
        endDate: DateTime(2027, 11, 10)));
    final (s1, _) = await send('recurring.edit', {
      'id': 'net',
      'freq_unit': 'years',
      'end_date': null,
      'notes': 'plano anual',
      'amount_cents': 109900,
    });
    expect(s1, 'done');
    final r = app.recurring.single;
    expect([r.freqUnit, r.endDate, r.notes, r.amount],
        ['years', null, 'plano anual', 1099]);
    expect(
        (await send('recurring.edit', {'id': 'net', 'kind': 'installment'})).$1,
        'rejected',
        reason: 'an installment plan needs an end');
  });

  test('loans, money lent, people and category rules', () async {
    final (s1, r1) = await send('loan.add', {
      'name': 'Notebook',
      'principal_cents': 100000,
      'start_date': '2026-11-01',
      'end_date': '2027-11-01',
      'transfer_account_id': 'bank',
      'account_id': 'bank',
    });
    expect(s1, 'done');
    expect(await balance('bank'), 2000, reason: 'the loan money arrived');
    final loanId = r1['loan_id'] as String;
    await send('loan.edit', {'id': loanId, 'name': 'Notebook novo'});
    expect(app.loans.single.name, 'Notebook novo');
    await send('loan.pay', {'id': loanId, 'amount_cents': 10000});
    expect(await balance('bank'), 1900);
    await send('loan.unpay', {'payment_id': app.loanPayments.single.id});
    expect(await balance('bank'), 2000);
    await send('loan.delete', {'id': loanId});
    expect(app.loans, isEmpty);
    expect(await balance('bank'), 1000);

    await send('lended.add', {
      'person': 'Pessoa fictícia',
      'type': 'lent',
      'amount_cents': 5000,
      'account_id': 'bank',
      'date': '2026-10-20',
    });
    final lent = app.lended.single;
    await send('lended.edit', {'id': lent.id, 'amount_cents': 6000});
    expect(await balance('bank'), 940);
    expect((await send('person.delete', {'id': lent.personId})).$1, 'rejected',
        reason: 'money still open with this person');
    await send('person.edit', {'id': lent.personId, 'name': 'Outro nome'});
    expect(app.lendedPeople.single.name, 'Outro nome');
    await send('lended.delete', {'id': lent.id});
    expect(await balance('bank'), 1000);
    await send('person.delete', {'id': lent.personId});
    expect(app.lendedPeople, isEmpty);

    final (s2, r2) = await send('rule.save',
        {'pattern': 'IFOOD', 'type': 'expense', 'category_id': 'food_exp'});
    expect(s2, 'done');
    expect((await ImportRulesService.load()).single.pattern, 'IFOOD');
    await send('rule.delete', {'id': r2['rule_id']});
    expect(await ImportRulesService.load(), isEmpty);
  });

  test('investments: archive only when closed, remove and link operations',
      () async {
    await send(
        'investment.add',
        {
          'name': 'CDB fictício',
          'asset_class': 'Renda fixa',
          'quantity_micros': 1000000,
          'cents': 20000,
          'date': '2026-10-01',
          'cash_account_id': 'bank',
        },
        id: 'inv');
    expect(await balance('bank'), 800);
    expect((await send('investment.archive', {'id': 'assistant-inv:inv'})).$1,
        'rejected',
        reason: 'the position is still open');
    await send('investment.unrecord', {'operation_id': 'assistant-invop:inv'});
    expect(await balance('bank'), 1000, reason: 'the cash came back');
    final (s1, _) = await send(
        'investment.archive', {'id': 'assistant-inv:inv', 'archived': true});
    expect(s1, 'done');

    await send(
        'investment.add',
        {
          'name': 'Posição antiga',
          'asset_class': 'Ações',
          'quantity_micros': 2000000,
          'cents': 5000,
          'date': '2026-01-10',
        },
        id: 'old');
    expect(await balance('bank'), 1000,
        reason: 'an old position moves no cash');
    await send('investment.link',
        {'operation_id': 'assistant-invop:old', 'account_id': 'bank'});
    expect(await balance('bank'), 950);
    final positions = await InvestmentRepository().load();
    expect(positions.where((p) => !p.investment.archived), hasLength(1));
  });

  test('undo is refused when something changed after; account comes back',
      () async {
    await capture();
    final (s1, _) = await send(
        'transaction.add',
        {
          'type': 'expense',
          'amount_cents': 3290,
          'description': 'iFood',
          'account_id': 'bank',
          'category_id': 'food_exp',
          'date': '2026-10-20',
        },
        id: 'buy');
    expect(s1, 'done');
    final t = app.transactions.single;
    await app.updateTransaction(t.copyWith(amount: 40), t);
    final (refused, why) = await undo('buy');
    expect(refused, 'rejected');
    expect(why['reason'], contains('mudou depois'));
    expect(app.transactions.single.amount, 40, reason: 'nothing undone');
    expect(await balance('bank'), 960);

    await send('account.add',
        {'name': 'Carteira', 'type': 'cash', 'balance_cents': 5000},
        id: 'wallet');
    await send('account.delete', {'id': 'assistant-acc:wallet'}, id: 'drop');
    expect(app.accountById('assistant-acc:wallet'), isNull);
    expect((await undo('drop')).$1, 'done');
    expect(await balance('assistant-acc:wallet'), 50,
        reason: 'the account and its money come back');
    expect((await undo('wallet')).$1, 'done');
    expect(app.accountById('assistant-acc:wallet'), isNull);
  });

  test('without sync on the device, nothing pretends to be undoable', () async {
    final (s1, r1) = await send('category.edit',
        {'id': 'food_exp', 'name': 'Comida', 'color': 0xFF1E88E5, 'icon': 13},
        id: 'edit');
    expect(s1, 'done');
    final c = app.categories.firstWhere((c) => c.id == 'food_exp');
    expect([c.name, c.colorValue, c.iconCodePoint], ['Comida', 0xFF1E88E5, 13]);
    expect(r1.containsKey('undo'), isFalse);
    final (s2, r2) = await send('request.undo', {'request_id': 'edit'});
    expect(s2, 'rejected');
    expect(r2['reason'], contains('não guardou'));
  });

  group('shared settings', () {
    test('seeded once, then the ledger wins; a joining device takes them',
        () async {
      app.settings.referenceIncome = 1800;
      await app.seedSharedSettings();
      expect(
          jsonDecode((await DBHelper.getSharedSettings())['referenceIncome']!),
          1800);
      // Another device changed it (a synced row): the app follows.
      await DBHelper.saveSharedSettings({'weekStart': 'sunday'}, 'sync.test');
      await app.reloadFromStorage();
      expect(app.settings.weekStart, 'sunday');
      expect(app.settings.referenceIncome, 1800);

      // A device that joins drops its own copy; the dataset brings them.
      final db = await DBHelper.database;
      await db.delete('accounts');
      await LedgerSync.joinDataset(db,
          datasetId: 'dataset-1', epoch: 'epoch-1', deviceId: 'pc');
      expect(await DBHelper.getSharedSettings(), isEmpty);
    });

    test('schema 27 from 26 keeps data; capture covers the new table',
        () async {
      await app.addTransaction(expense('keep', 12));
      final db = await DBHelper.database;
      await capture();
      // Simulate a device synced before schema 27.
      for (final t in ['ins', 'upd', 'del']) {
        await db.execute('DROP TRIGGER sync_capture_shared_settings_$t');
      }
      await db.execute('DROP TABLE shared_settings');
      await db.execute('PRAGMA user_version = 26');
      await DBHelper.close();
      await DBHelper.database; // upgrade + triggers
      expect((await DBHelper.getTransactions()).single.id, 'keep');
      expect(await balance('bank'), 988);
      final journal = (await DBHelper.database).query('sync_journal');
      final before = (await journal).length;
      await DBHelper.saveSharedSettings(
          {'weekStart': 'sunday'}, 'setting.update');
      final ops = await (await DBHelper.database).query('sync_journal');
      expect(ops.length, before + 1);
      expect(ops.last['payload'] as String, contains('shared_settings'));
    });

    test('backups carry them; older backups still restore', () async {
      await DBHelper.saveSharedSettings(
          {'referenceIncome': 1800}, 'setting.update');
      final data = await DBHelper.exportAll();
      expect(
          (data['shared_settings'] as List).single['key'], 'referenceIncome');
      final roundTrip =
          (jsonDecode(jsonEncode(data)) as Map).cast<String, dynamic>();
      await DBHelper.importAll(roundTrip);
      expect((await DBHelper.getSharedSettings()).keys, ['referenceIncome']);

      final old = Map<String, dynamic>.from(roundTrip)
        ..remove('shared_settings')
        ..['version'] = 26;
      DBHelper.validateBackup(old);
      final missing = Map<String, dynamic>.from(roundTrip)
        ..remove('shared_settings');
      expect(() => DBHelper.validateBackup(missing), throwsFormatException);
    });
  });
}
