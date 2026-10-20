import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/investments/investment_models.dart';
import 'package:expensy/investments/investment_repository.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/services/billing_cycle.dart';
import 'package:expensy/services/import_rules_service.dart';
import 'package:expensy/services/transaction_metadata_service.dart';
import 'package:expensy/sync/ledger_capture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

// Synthetic ledgers only, in temporary folders. Two "devices" share one
// checkpoint copy, then work offline and exchange their journals.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  Future<Database> use(String device) async {
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, device));
    return DBHelper.database;
  }

  Future<AppProvider> provider() async {
    final app = AppProvider();
    app.settings.budgetAlertsEnabled = false;
    app.accounts = await DBHelper.getAccounts();
    app.categories = await DBHelper.getCategories();
    app.transactions = await DBHelper.getTransactions();
    app.recurring = await DBHelper.getRecurring();
    app.lendedPeople = await DBHelper.getLendedPeople();
    app.lended = await DBHelper.getLended();
    app.savingsGoals = await DBHelper.getSavingsGoals();
    app.loans = await DBHelper.getLoans();
    app.assets = await DBHelper.getAssets();
    app.wishlist = await DBHelper.getWishlist();
    app.budgets = await DBHelper.getBudgets();
    return app;
  }

  /// Every synced row; balances compared to the millionth.
  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final db = await DBHelper.database;
    return {
      for (final entry in ledgerTables.entries)
        entry.key: [
          for (final row
              in await db.query(entry.key, orderBy: '${entry.value} ASC'))
            {
              ...row,
              if (entry.key == 'accounts')
                'balance': ((row['balance'] as num) * 1e6).round(),
            }
        ]
    };
  }

  Future<double> balance(String id) async =>
      (await DBHelper.getAccounts()).firstWhere((a) => a.id == id).balance;

  Future<List<LedgerOperation>> journal() async =>
      LedgerCapture.journal(await DBHelper.database);

  Future<void> applyAll(List<LedgerOperation> ops) async {
    final db = await DBHelper.database;
    for (final op in ops) {
      await LedgerCapture.apply(db, op);
    }
  }

  AppTransaction tx(String id, double amount,
          {String account = 'bank', String type = 'expense'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: 'Sintético $id',
          accountId: account,
          categoryId: type == 'expense' ? 'food_exp' : 'salary',
          date: DateTime(2026, 10, 15, 12));

  // Undo closures are async but typed VoidCallback; await their real future.
  Future<void> undo(VoidCallback callback) =>
      (callback as Future<void> Function())();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    // The desktop profile: no scheduled-notification plugin in tests.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-ledger-capture-');
    await use('phone');
    for (final a in [
      Account(
          id: 'bank',
          name: 'Banco sintético',
          type: 'bank',
          balance: 1000,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'cash',
          name: 'Carteira sintética',
          type: 'wallet',
          balance: 0,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'card',
          name: 'Cartão sintético',
          type: 'credit',
          balance: 0,
          currency: 'BRL',
          colorValue: 0,
          statementDay: 20,
          dueDay: 27),
    ]) {
      await DBHelper.insertAccount(a);
    }
    final seed = await provider();
    await seed.addTransaction(tx('shared', 100));
    // Checkpoint: capture installed, then the file is copied to the PC.
    await LedgerCapture.install(await DBHelper.database);
    await DBHelper.close();
    await Directory(p.join(root.path, 'pc')).create();
    await File(p.join(root.path, 'phone', 'expensy.db'))
        .copy(p.join(root.path, 'pc', 'expensy.db'));
    await use('phone');
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('every table is either synced or explicitly device-local', () async {
    final db = await DBHelper.database;
    final tables = (await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .where((n) =>
            !n.startsWith('sqlite_') &&
            !n.startsWith('sync_') &&
            n != 'android_metadata')
        .toSet();
    expect(tables.difference({...ledgerTables.keys, ...ledgerLocalTables}),
        isEmpty,
        reason: 'a new table needs a sync decision');
    expect({...ledgerTables.keys}.difference(tables), isEmpty);
  });

  test('without installed capture nothing is created or journaled', () async {
    await DBHelper.close();
    await use('fresh');
    final app = await provider();
    await DBHelper.insertAccount(Account(
        id: 'bank',
        name: 'Banco',
        type: 'bank',
        balance: 10,
        currency: 'BRL',
        colorValue: 0));
    app.accounts = await DBHelper.getAccounts();
    await app.addTransaction(tx('plain', 4));
    final db = await DBHelper.database;
    expect(await LedgerCapture.isInstalled(db), false);
    expect(
        await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE name LIKE 'sync_%'"),
        isEmpty);
    expect(await balance('bank'), 6);
  });

  test(
      'every write path is attributed and the journal rebuilds the same ledger',
      () async {
    final app = await provider();
    final db = await DBHelper.database;

    // Accounts and categories.
    await app.addAccount(Account(
        id: 'reserve',
        name: 'Reserva',
        type: 'bank',
        balance: 250,
        currency: 'BRL',
        colorValue: 0));
    await app.updateAccount(
        app.accountById('reserve')!.copyWith(name: 'Reserva 2', balance: 300));
    await app.addCategory(
        AppCategory(id: 'pets', name: 'Pets', type: 'expense', colorValue: 0));
    await app.updateCategory(AppCategory(
        id: 'pets', name: 'Animais', type: 'expense', colorValue: 0));

    // Transactions: paid, pending, card installments, edit, delete + undo.
    await app.addTransaction(tx('food', 32.9));
    await app.addTransaction(tx('bill', 80),
        metadata: const TransactionMetadata(
            transactionId: 'bill', status: 'pending'));
    await app.addTransaction(tx('tv', 300, account: 'card'),
        metadata: const TransactionMetadata(
            transactionId: 'tv', installmentCurrent: 1, installmentTotal: 3));
    final food = app.transactions.firstWhere((t) => t.id == 'food');
    await app.updateTransaction(
        AppTransaction(
            id: 'food',
            type: 'expense',
            amount: 40,
            description: food.description,
            accountId: 'bank',
            categoryId: 'transport',
            date: food.date),
        food);
    final undoBill = await app.deleteTransactionWithUndo('bill');
    await undo(undoBill);
    await app.deleteTransaction('bill');
    await TransactionMetadataService.instance.save(
        const TransactionMetadata(transactionId: 'food', subcategory: 'App'));

    // Transfer and card invoice payment.
    await app.addTransfer(fromId: 'bank', toId: 'cash', fromAmount: 200);
    final cycle = BillingCycle.forDate(DateTime(2026, 10, 15, 12), 20, 27);
    await app.addTransfer(
        fromId: 'bank',
        toId: 'card',
        fromAmount: 100,
        invoiceCycleEnd: cycle.end);

    // Recurring: pay, skip, delete with undo.
    final rule = RecurringPayment(
        id: 'stream',
        name: 'Streaming',
        accountId: 'bank',
        categoryId: 'entertainment',
        amount: 29.9,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(2026, 9, 15),
        nextDate: DateTime(2026, 9, 15));
    await app.addRecurring(rule);
    await app.markRecurringPaid(app.recurring.single);
    await app.skipNextRecurring(app.recurring.single);
    final undoRule = await app.deleteRecurringWithUndo('stream');
    await undo(undoRule);

    // Goals: contribution, guarded deletion, withdrawal, deletion + undo.
    await app.addSavingsGoal(SavingsGoal(
        id: 'trip',
        name: 'Viagem',
        targetAmount: 1000,
        currency: 'BRL',
        colorValue: 0));
    await app.contributeToGoal(
        goalId: 'trip', fromAccountId: 'bank', amount: 100);
    await expectLater(
        app.deleteSavingsGoalWithUndo('trip'), throwsA(isA<FormatException>()));
    await app.withdrawFromGoal(
        goalId: 'trip', toAccountId: 'bank', amount: 100);
    final undoGoal = await app.deleteSavingsGoalWithUndo('trip');
    await undo(undoGoal);

    // Lended money and people.
    await app
        .addLendedPerson(LendedPerson(id: 'ana', name: 'Ana', colorValue: 0));
    final lent = LendedMoney(
        id: 'l1',
        personId: 'ana',
        amount: 50,
        type: 'lent',
        accountId: 'bank',
        date: DateTime(2026, 10, 1));
    await app.addLended(lent);
    await app.updateLended(lent.copyWith(amount: 60), lent);
    await app.settleLended(app.lended.single);
    await app.addLended(LendedMoney(
        id: 'l2',
        personId: 'ana',
        amount: 20,
        type: 'borrowed',
        accountId: 'bank',
        date: DateTime(2026, 10, 2)));
    final undoEntry = await app.deleteLendedWithUndo('l2');
    await undo(undoEntry);
    final undoPerson = await app.deleteLendedPersonWithUndo('ana');
    await undo(undoPerson);

    // Loans.
    final loan = Loan(
        id: 'loan',
        name: 'Empréstimo',
        principal: 500,
        currency: 'BRL',
        startDate: DateTime(2026, 1),
        endDate: DateTime(2026, 12),
        transferAccountId: 'bank',
        accountId: 'bank');
    await app.addLoan(loan);
    await app.payLoanInstallment(loan, amount: 100);
    await app.payLoanInstallment(loan, amount: 50);
    await app.deleteLoanPayment(
        app.loanPayments.firstWhere((p) => p.amount == 50).id);
    final undoLoan = await app.deleteLoanWithUndo('loan');
    await undo(undoLoan);

    // Assets, budgets, wishlist, import rules.
    final asset =
        AssetItem(id: 'car', name: 'Carro', value: 30000, currency: 'BRL');
    await app.addAsset(asset);
    await app.updateAsset(asset.copyWith(value: 29000));
    final undoAsset = await app.deleteAssetWithUndo('car');
    await undo(undoAsset);
    final budget = Budget(
        id: 'b1',
        categoryId: 'food_exp',
        amount: 600,
        period: 'monthly',
        createdAt: DateTime(2026, 10));
    await app.addBudget(budget);
    await app.updateBudget(budget.copyWith(amount: 700));
    await app.deleteBudget('b1');
    await app.addWishlist(WishlistItem(
        id: 'w1', name: 'Fone', targetPrice: 300, priority: 'high'));
    final undoWish = await app.deleteWishlistWithUndo('w1');
    await undo(undoWish);
    await ImportRulesService.save(const ImportRule(
        id: 'r1', pattern: 'mercado', type: 'expense', categoryId: 'food_exp'));
    await ImportRulesService.delete('r1');

    // Investments with linked cash; a market quote is derived.
    final repo = InvestmentRepository();
    final at = DateTime(2026, 10, 10);
    await repo.create(
        Investment(
            id: 'stock',
            name: 'Ação sintética',
            assetClass: 'Ações',
            ticker: 'TEST3',
            priceMicros: 10 * investmentScale,
            priceAt: at),
        InvestmentOperation(
            id: 'open',
            investmentId: 'stock',
            kind: 'opening',
            quantity: 10 * investmentScale,
            cents: 10000,
            date: at,
            createdAt: at));
    await repo.record(InvestmentOperation(
        id: 'buy',
        investmentId: 'stock',
        kind: 'buy',
        quantity: 5 * investmentScale,
        cents: 5000,
        date: at,
        createdAt: at,
        cashAccountId: 'bank'));
    await repo.price('stock', 12 * investmentScale,
        at.add(const Duration(hours: 1)), 'brapi');
    await repo.price('stock', 11 * investmentScale,
        at.add(const Duration(hours: 2)), 'manual');
    await repo.removeOperation('buy');

    expect(await LedgerCapture.unattributedChanges(db), 0,
        reason: '${await LedgerCapture.unattributedTables(db)}');
    final ops = await journal();
    final kinds = ops.map((o) => o.kind).toSet();
    for (final kind in [
      'account.create',
      'account.update',
      'transaction.add',
      'transaction.update',
      'transaction.delete',
      'transaction.restore',
      'transfer.add',
      'invoice.pay',
      'recurring.pay',
      'recurring.skip',
      'recurring.restore',
      'goal.contribute',
      'goal.withdraw',
      'goal.restore',
      'lended.add',
      'lended.settle',
      'lended.restore',
      'lended_person.restore',
      'loan.create',
      'loan.pay',
      'loan.restore',
      'investment.record',
      'investment.price',
      'investment.remove_operation',
      'import_rule.save',
      'metadata.save',
    ]) {
      expect(kinds, contains(kind));
    }
    // One manual price only: the brapi quote is never sent as a decision.
    expect(ops.where((o) => o.kind == 'investment.price'), hasLength(1));
    // The rejected goal deletion left no trace.
    expect(ops.where((o) => o.kind == 'goal.delete'), hasLength(1));

    final phone = await snapshot();
    await use('pc');
    await applyAll(ops);
    final pc = await snapshot();
    for (final table in ledgerTables.keys) {
      expect(pc[table], phone[table], reason: table);
    }
  });

  test('two offline devices spending from one account converge', () async {
    final phoneApp = await provider();
    await phoneApp.addTransaction(tx('coffee', 7.5));
    await phoneApp.addTransaction(tx('salary', 1500, type: 'income'));
    final phoneOps = await journal();

    await use('pc');
    final pcApp = await provider();
    await pcApp.addTransaction(tx('market', 0.1));
    await pcApp.addTransaction(tx('bus', 0.2));
    await pcApp.addTransfer(fromId: 'bank', toId: 'cash', fromAmount: 50);
    final pcOps = await journal();
    await applyAll(phoneOps);
    final pcState = await snapshot();
    expect(await balance('bank'),
        closeTo(1000 - 100 - 7.5 + 1500 - .3 - 50, 1e-9));
    expect(await balance('cash'), 50);

    await use('phone');
    await applyAll(pcOps);
    expect(await snapshot(), pcState);
    // Redelivery of the same page changes nothing.
    await applyAll(pcOps);
    expect(await snapshot(), pcState);
  });

  test('concurrent edits of one transaction conflict without partial writes',
      () async {
    final shared =
        (await provider()).transactions.firstWhere((t) => t.id == 'shared');
    AppTransaction amount(double value) => AppTransaction(
        id: 'shared',
        type: 'expense',
        amount: value,
        description: shared.description,
        accountId: 'bank',
        categoryId: shared.categoryId,
        date: shared.date);
    final phoneApp = await provider();
    await phoneApp.updateTransaction(amount(120), shared);
    final phoneOps = await journal();

    await use('pc');
    final pcApp = await provider();
    await pcApp.updateTransaction(amount(90), shared);
    final before = await snapshot();
    await expectLater(
        applyAll(phoneOps),
        throwsA(isA<LedgerConflict>()
            .having((e) => e.code, 'code', 'concurrent_edit')));
    expect(await snapshot(), before, reason: 'conflict rolled back entirely');
    expect(await balance('bank'), 910);
  });

  test('spending on an account deleted elsewhere is a conflict, not an orphan',
      () async {
    final phoneApp = await provider();
    await phoneApp.deleteAccount('cash');
    final phoneOps = await journal();

    await use('pc');
    final pcApp = await provider();
    await pcApp.addTransaction(tx('gift', 30, account: 'cash'));
    final pcOps = await journal();

    await use('phone');
    final before = await snapshot();
    await expectLater(applyAll(pcOps), throwsA(isA<LedgerConflict>()));
    expect(await snapshot(), before);
    expect((await DBHelper.getTransactions()).where((t) => t.id == 'gift'),
        isEmpty);
    expect(phoneOps.single.kind, 'account.delete');
  });

  test('account form applies the typed difference, not a stale total',
      () async {
    final app = await provider();
    final screen = app.accountById('bank')!; // as the form opened it
    await app.addTransaction(tx('meanwhile', 40));
    await app.updateAccount(screen.copyWith(name: 'Banco renomeado'),
        original: screen);
    expect(await balance('bank'), 1000 - 100 - 40);
    final card = app.accountById('card')!;
    await app.addTransaction(tx('purchase', 25, account: 'card'));
    await app.updateAccount(card.copyWith(dueDay: 28), original: card);
    expect(await balance('card'), -25);
    expect(
        (await DBHelper.getTransactions())
            .where((t) => t.description.contains('Ajuste')),
        isEmpty,
        reason: 'no fake card adjustment from a stale screen');
  });

  test('derived values and restores never become journaled money', () async {
    final db = await DBHelper.database;
    await DBHelper.operation(
        'gold.refresh',
        scope: LedgerScope.derived,
        (txn) => txn.update('accounts', {'balance': 1234.5},
            where: 'id = ?', whereArgs: ['cash']));
    expect(await journal(), isEmpty);
    expect(await LedgerCapture.unattributedChanges(db), 0);

    await DBHelper.importAll(await DBHelper.exportAll());
    expect(await journal(), isEmpty, reason: 'restore is not recreations');
    expect(await LedgerCapture.restoreBarrier(db), true);
    await expectLater(
        LedgerCapture.apply(
            db,
            LedgerOperation(
                id: 'remote',
                kind: 'transaction.add',
                createdAt: DateTime.utc(2026),
                edits: [],
                balances: [const LedgerBalanceDelta('bank', 1, 1)])),
        throwsA(isA<LedgerConflict>()
            .having((e) => e.code, 'code', 'restore_review_required')));
  });

  test('a write outside any domain operation is detected', () async {
    final db = await DBHelper.database;
    await db.insert('wishlist', {
      'id': 'raw',
      'name': 'Escrita direta',
      'target_price': 1.0,
      'priority': 'low',
      'created_at': DateTime(2026).toIso8601String(),
    });
    expect(await LedgerCapture.unattributedChanges(db), 1);
    expect((await LedgerCapture.unattributedTables(db)).single['table_name'],
        'wishlist');
  });
}
