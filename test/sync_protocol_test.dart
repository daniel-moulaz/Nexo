import 'dart:convert';
import 'dart:io';

import 'package:nexo/models/models.dart';
import 'package:nexo/services/finance_rules.dart';
import 'package:nexo/services/transaction_metadata_service.dart';
import 'package:nexo/sync/sync_protocol.dart';
import 'package:nexo/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sqlite_sync_server.dart';

const bank = SyncKey('account', 'bank');
const reserve = SyncKey('account', 'reserve');
const card = SyncKey('account', 'card');

void main() {
  late SyncStore phone;
  late SyncStore pc;
  late SqliteSyncServer server;
  late DateTime now;
  final opened = <Database>[];

  Future<Database> database([String path = inMemoryDatabasePath]) async {
    final db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(singleInstance: false));
    opened.add(db);
    return db;
  }

  Future<SyncStore> device(String id, {String? path}) async {
    final store =
        SyncStore(await database(path ?? inMemoryDatabasePath), now: () => now);
    await store.initialize(
        datasetId: 'synthetic', epoch: 'epoch-1', deviceId: id);
    return store;
  }

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    now = DateTime.utc(2026, 10, 16, 12);
    phone = await device('phone');
    pc = await device('pc');
    server = SqliteSyncServer(await database(), 'synthetic', 'epoch-1');
    await server.initialize();
  });
  tearDown(() async {
    for (final db in opened) {
      if (db.isOpen) await db.close();
    }
    opened.clear();
  });

  Future<SyncEdit> edit(
          SyncStore store, SyncKey key, Map<String, dynamic>? value) async =>
      SyncEdit(key, await store.revision(key), value);

  Future<double> balance(SyncStore store, SyncKey key) async =>
      Account.fromMap((await store.value(key))!).balance;

  Future<SyncEdit> delta(SyncStore store, SyncKey key, double amount) async {
    final account = Account.fromMap((await store.value(key))!);
    return edit(store, key,
        account.copyWith(balance: account.balance + amount).toMap());
  }

  Future<void> seed() async {
    await phone.stage([
      for (final key in [bank, reserve, card])
        SyncEdit(
            key,
            0,
            Account(
                    id: key.id,
                    name: 'Teste ${key.id}',
                    type: key == card ? 'credit' : 'bank',
                    balance: key == bank ? 1000 : 0,
                    currency: 'BRL',
                    colorValue: 0)
                .toMap()),
    ]);
    await phone.synchronize(server);
    await pc.synchronize(server);
  }

  SyncEdit entry(String id, double amount,
      {String accountId = 'bank',
      String type = 'expense',
      String status = 'paid',
      String source = 'manual',
      bool neutral = false,
      int base = 0}) {
    final tx = AppTransaction(
        id: id,
        type: type,
        amount: amount,
        description: 'Sintético',
        accountId: accountId,
        categoryId: 'test',
        date: now,
        currency: 'BRL');
    final metadata = TransactionMetadata(
        transactionId: id,
        status: status,
        source: source,
        excludeFromSpending: neutral);
    return SyncEdit(SyncKey('transaction', id), base,
        {'transaction': tx.toMap(), 'metadata': metadata.toMap()});
  }

  Future<SyncOperation> post(SyncStore store, String id, double amount,
          {SyncKey account = bank,
          String type = 'expense',
          String status = 'paid'}) async =>
      store.stage([
        if (status == 'paid')
          await delta(store, account, type == 'income' ? amount : -amount),
        entry(id, amount, accountId: account.id, type: type, status: status),
      ]);

  Future<double> spending(SyncStore store) async {
    final rows = await store.db.query('sync_lab_entities',
        where: "kind = 'transaction' AND value_json IS NOT NULL");
    var sum = 0.0;
    for (final row in rows) {
      final json = jsonDecode(row['value_json'] as String);
      final tx = AppTransaction.fromMap(json['transaction']);
      final meta = TransactionMetadata.fromMap(json['metadata']);
      if (tx.type == 'expense' &&
          !meta.isPending &&
          !FinanceRules.isNeutral(tx, meta)) sum += tx.amount;
    }
    return sum;
  }

  Future<SyncOperation> transfer(SyncStore store, String id,
          {SyncKey destination = reserve, double amount = 200}) async =>
      store.stage([
        await delta(store, bank, -amount),
        await delta(store, destination, amount),
        entry('$id:out', amount, source: 'transfer:$id', neutral: true),
        entry('$id:in', amount,
            accountId: destination.id,
            type: 'income',
            source: 'transfer:$id',
            neutral: true),
        if (destination == card)
          SyncEdit(SyncKey('invoice_payment', id), 0, {
            'amount': amount,
            'card_id': card.id,
            'cycle_end': '2026-10-31'
          }),
      ]);

  test('canonical payload is immutable, bounded and stable across key order',
      () async {
    final source = <String, dynamic>{
      'z': 1,
      'a': {'x': 2}
    };
    final e = SyncEdit(const SyncKey('test', 'id'), 0, source);
    source['z'] = 999;
    e.value!['a'] = null;
    final op = await phone.stage([e]);
    expect(e.value, {
      'a': {'x': 2},
      'z': 1
    });
    expect(await SyncOperation.decode(op.encode()).digest(), await op.digest());
    expect(canonicalSyncJson({'z': 1, 'a': 2}),
        canonicalSyncJson({'a': 2, 'z': 1}));
    expect(() => SyncEdit(bank, 0, {'amount': double.nan}),
        throwsA(isA<SyncProtocolException>()));
    for (final broken in ['"protocol":3', '"protocol":2']) {
      // Unknown version, or v2 without its effect/requirement lists.
      expect(
          () => SyncOperation.decode(
              op.encode().replaceFirst('"protocol":1', broken)),
          throwsA(isA<SyncProtocolException>()));
    }
  });

  test('local projection and outbox roll back together after a disk error',
      () async {
    await seed();
    await phone.db.execute('''CREATE TRIGGER deny_outbox BEFORE INSERT ON
      sync_lab_outbox BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END''');
    await expectLater(
        post(phone, 'fail', 100), throwsA(isA<DatabaseException>()));
    expect(await balance(phone, bank), 1000);
    expect(await phone.value(const SyncKey('transaction', 'fail')), isNull);
    expect(await phone.pendingCount, 0);
  });

  test('income, paid expense and pending expense converge with unchanged cash',
      () async {
    await seed();
    await post(phone, 'salary', 1500, type: 'income');
    await post(phone, 'market', 100);
    await post(phone, 'internet', 80, status: 'pending');
    expect(await balance(phone, bank), 2400);
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await balance(pc, bank), 2400);
    expect(await spending(pc), 100);
    final pending = await pc.value(const SyncKey('transaction', 'internet'));
    expect(pending!['metadata']['status'], 'pending');
    expect(pending['transaction']['amount'], 80);
  });

  test('transfer arrives atomically, preserves assets and has no consumption',
      () async {
    await seed();
    await transfer(phone, 'transfer');
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await balance(pc, bank), 800);
    expect(await balance(pc, reserve), 200);
    expect(await balance(pc, bank) + await balance(pc, reserve), 1000);
    expect(await spending(pc), 0);
    await pc.synchronize(server);
    expect(await balance(pc, bank), 800);
  });

  test('reserve contribution remains neutral on both devices', () async {
    await seed();
    await phone.stage([
      await delta(phone, bank, -200),
      SyncEdit(const SyncKey('goal', 'reserve'), 0, {'current_amount': 200}),
      SyncEdit(const SyncKey('goal_contribution', 'deposit'), 0,
          {'amount': 200, 'goal_id': 'reserve', 'account_id': 'bank'}),
    ]);
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await balance(pc, bank), 800);
    expect(
        (await pc.value(const SyncKey('goal', 'reserve')))!['current_amount'],
        200);
    expect(await spending(pc), 0);
  });

  test('card purchase and invoice payment count spending only once', () async {
    await seed();
    await post(phone, 'card-purchase', 120, account: card);
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await balance(pc, bank), 1000);
    expect(await balance(pc, card), -120);
    expect(await spending(pc), 120);
    await transfer(pc, 'invoice', destination: card, amount: 120);
    await pc.synchronize(server);
    await phone.synchronize(server);
    expect(await balance(phone, bank), 880);
    expect(await balance(phone, card), 0);
    expect(await spending(phone), 120);
    expect(await phone.value(const SyncKey('invoice_payment', 'invoice')),
        isNotNull);
  });

  test('lost server response retries the same operation without double debit',
      () async {
    await seed();
    await post(phone, 'lost-response', 100);
    server.loseNextResponse = true;
    expect(await phone.synchronize(server), SyncPass.retryLater);
    expect(await phone.pendingCount, 1);
    expect(await phone.synchronize(server), SyncPass.retryLater);
    now = now.add(const Duration(minutes: 10));
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await phone.pendingCount, 0);
    expect(await balance(phone, bank), 900);
    expect(await balance(pc, bank), 900);
    expect(await server.db.query('server_log'), hasLength(2));
  });

  test('pull can recover an accepted operation whose push receipt was lost',
      () async {
    await seed();
    await post(phone, 'receipt', 50);
    server.loseNextResponse = true;
    await phone.synchronize(server);
    final page = await server.pull(
        datasetId: 'synthetic',
        epoch: 'epoch-1',
        after: await phone.cursor,
        limit: 100);
    await phone.accept(page.single);
    await phone.accept(page.single);
    expect(await balance(phone, bank), 950);
    expect(await phone.pendingCount, 0);
  });

  test(
      'interrupted pull rolls back all sides and leaves cursor before transfer',
      () async {
    await seed();
    await transfer(phone, 'atomic');
    await phone.synchronize(server);
    await pc.db.execute('''CREATE TRIGGER deny_transaction BEFORE INSERT ON
      sync_lab_entities WHEN NEW.kind = 'transaction'
      BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END''');
    await expectLater(
        pc.synchronize(server), throwsA(isA<DatabaseException>()));
    expect(await pc.cursor, 1);
    expect(await balance(pc, bank), 1000);
    expect(await balance(pc, reserve), 0);
    await pc.db.execute('DROP TRIGGER deny_transaction');
    await pc.synchronize(server);
    expect(await pc.cursor, 2);
    expect(await balance(pc, bank), 800);
  });

  test('server rollback does not create a committed revision gap', () async {
    await seed();
    final op = await post(phone, 'server-fault', 25);
    await server.db
        .execute('''CREATE TRIGGER deny_log BEFORE INSERT ON server_log
      BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END''');
    await expectLater(server.push(op), throwsA(isA<DatabaseException>()));
    expect((await server.db.query('server_clock')).single['revision'], 1);
    await server.db.execute('DROP TRIGGER deny_log');
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await pc.cursor, 2);
    expect(await balance(pc, bank), 975);
  });

  test('simultaneous financial edits preserve both alternatives without LWW',
      () async {
    await seed();
    const key = SyncKey('budget', 'food');
    await phone.stage([
      SyncEdit(key, 0, {'limit': 350})
    ]);
    await phone.synchronize(server);
    await pc.synchronize(server);
    await phone.stage([
      await edit(phone, key, {'limit': 400})
    ]);
    now = now.subtract(const Duration(days: 100));
    await pc.stage([
      await edit(pc, key, {'limit': 500})
    ]);
    await phone.synchronize(server);
    expect(await pc.synchronize(server), SyncPass.conflict);
    expect(await pc.value(key), {'limit': 500});
    expect(await phone.value(key), {'limit': 400});
    final conflict = (await pc.conflicts).single;
    expect(conflict['base_payload'], contains('350'));
    expect(conflict['local_payload'], contains('500'));
    expect(conflict['remote_payload'], contains('400'));
    expect(await pc.pendingCount, 1);
  });

  test('two offline expenses on one account are conservatively blocked',
      () async {
    await seed();
    await post(phone, 'phone-expense', 100);
    await post(pc, 'pc-expense', 50);
    await phone.synchronize(server);
    expect(await pc.synchronize(server), SyncPass.conflict);
    expect(await balance(pc, bank), 950);
    expect(await balance(phone, bank), 900);
    expect(await pc.conflicts, hasLength(1));
    // These are NOT merged by overwriting a cached account balance.
  });

  test('independent offline entities converge without a conflict', () async {
    await seed();
    await phone.stage([
      SyncEdit(const SyncKey('budget', 'food'), 0, {'limit': 350})
    ]);
    await pc.stage([
      SyncEdit(const SyncKey('budget', 'travel'), 0, {'limit': 150})
    ]);
    await phone.synchronize(server);
    await pc.synchronize(server);
    await phone.synchronize(server);
    expect(
        await phone.value(const SyncKey('budget', 'travel')), {'limit': 150});
    expect(await pc.value(const SyncKey('budget', 'food')), {'limit': 350});
    expect(await pc.conflicts, isEmpty);
  });

  test('deletion retains a tombstone and old creation cannot resurrect it',
      () async {
    const key = SyncKey('budget', 'old');
    final create = await phone.stage([
      SyncEdit(key, 0, {'limit': 350})
    ]);
    await phone.synchronize(server);
    await pc.synchronize(server);
    await phone.stage([await edit(phone, key, null)]);
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await pc.value(key), isNull);
    expect(await pc.revision(key), 2);
    expect((await pc.db.query('sync_lab_entities')).single['deleted_at'],
        isNotNull);
    expect(await server.push(create), isA<SyncAccepted>());
    final old = SyncOperation(
        id: 'restore-old',
        datasetId: 'synthetic',
        epoch: 'epoch-1',
        deviceId: 'old-pc',
        createdAt: now,
        edits: create.edits);
    expect(await server.push(old), isA<SyncRejected>());
    await pc.synchronize(server);
    expect(await pc.value(key), isNull);
  });

  test('delete versus offline edit is a reviewable conflict', () async {
    const key = SyncKey('budget', 'food');
    await phone.stage([
      SyncEdit(key, 0, {'limit': 350})
    ]);
    await phone.synchronize(server);
    await pc.synchronize(server);
    await phone.stage([await edit(phone, key, null)]);
    await pc.stage([
      await edit(pc, key, {'limit': 450})
    ]);
    await phone.synchronize(server);
    expect(await pc.synchronize(server), SyncPass.conflict);
    expect(await pc.value(key), {'limit': 450});
    expect((await pc.conflicts).single['remote_payload'],
        contains('"value":null'));
  });

  test('installment batch retry never duplicates a series or card debt',
      () async {
    await seed();
    final op = await phone.stage([
      await delta(phone, card, -300),
      for (var i = 1; i <= 3; i++)
        entry('purchase:installment:$i', 100,
            accountId: 'card', source: 'installment'),
    ]);
    await phone.synchronize(server);
    await server.push(op);
    await server.push(op);
    await pc.synchronize(server);
    expect(await balance(pc, card), -300);
    expect(await spending(pc), 300);
    expect(
        await pc.db.query('sync_lab_entities', where: "kind = 'transaction'"),
        hasLength(3));
  });

  test('same recurring occurrence on two devices never debits twice remotely',
      () async {
    await seed();
    const rule = SyncKey('recurring', 'internet');
    await phone.stage([
      SyncEdit(rule, 0, {'next_date': '2026-10-16'})
    ]);
    await phone.synchronize(server);
    await pc.synchronize(server);
    for (final store in [phone, pc]) {
      await store.stage([
        await delta(store, bank, -80),
        entry('recurring:internet:2026-10-16', 80, source: 'recurring'),
        await edit(store, rule, {'next_date': '2026-11-16'}),
        SyncEdit(const SyncKey('recurring_history', 'internet:2026-10-16'), 0,
            {'action': 'paid', 'amount': 80}),
      ]);
    }
    await phone.synchronize(server);
    expect(await pc.synchronize(server), SyncPass.conflict);
    final third = await device('third');
    await third.synchronize(server);
    expect(await balance(third, bank), 920);
    expect(await spending(third), 80);
    expect(await third.value(rule), {'next_date': '2026-11-16'});
  });

  test('same operation id with another payload is rejected before mutation',
      () async {
    final original = await phone.stage([
      SyncEdit(bank, 0, {'balance': 1000})
    ]);
    await phone.synchronize(server);
    final corrupt = SyncOperation(
        id: original.id,
        datasetId: original.datasetId,
        epoch: original.epoch,
        deviceId: original.deviceId,
        createdAt: now,
        edits: [
          SyncEdit(bank, 0, {'balance': 9000})
        ]);
    await expectLater(
        server.push(corrupt), throwsA(isA<SyncProtocolException>()));
    expect(await server.db.query('server_log'), hasLength(1));
  });

  test('receipt with a forged digest cannot change the projection', () async {
    final op = await phone.stage([
      SyncEdit(bank, 0, {'balance': 1000})
    ]);
    await expectLater(pc.accept(SyncReceipt(1, op, 'invalid')),
        throwsA(isA<SyncProtocolException>()));
    expect(await pc.value(bank), isNull);
    expect(await pc.cursor, 0);
  });

  test('wrong dataset, epoch and cursor gaps are rejected', () async {
    final op = await phone.stage([
      SyncEdit(bank, 0, {'balance': 1000})
    ]);
    await expectLater(pc.accept(SyncReceipt(2, op, await op.digest())),
        throwsA(isA<SyncProtocolException>()));
    final wrong = SyncOperation(
        id: 'foreign',
        datasetId: 'another-user',
        epoch: 'epoch-1',
        deviceId: 'device',
        createdAt: now,
        edits: op.edits);
    await expectLater(pc.accept(SyncReceipt(1, wrong, await wrong.digest())),
        throwsA(isA<SyncProtocolException>()));
    final epoch = SyncOperation(
        id: 'old-epoch',
        datasetId: 'synthetic',
        epoch: 'epoch-0',
        deviceId: 'device',
        createdAt: now,
        edits: op.edits);
    await expectLater(
        server.push(epoch), throwsA(isA<SyncProtocolException>()));
    expect(await pc.cursor, 0);
  });

  test('offline local work survives and converges when transport recovers',
      () async {
    await seed();
    server.offline = true;
    await post(phone, 'offline', 32.90);
    expect(await balance(phone, bank), closeTo(967.10, .0001));
    expect(await phone.synchronize(server), SyncPass.retryLater);
    expect(await phone.pendingCount, 1);
    server.offline = false;
    now = now.add(const Duration(days: 14));
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await balance(pc, bank), closeTo(967.10, .0001));
  });

  test('restore barrier survives restart and prevents even a network request',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nexo-sync-synthetic-');
    addTearDown(() async {
      for (final db in opened) {
        if (db.isOpen) await db.close();
      }
      await directory.delete(recursive: true);
    });
    final path = '${directory.path}${Platform.pathSeparator}synthetic.db';
    final first = await device('restore-test', path: path);
    await first.stage([
      SyncEdit(bank, 0, {'balance': 1000})
    ]);
    await first.pauseForRestore();
    await first.db.close();
    final restarted = await device('restore-test', path: path);
    expect(await restarted.pendingCount, 1);
    expect(await restarted.value(bank), {'balance': 1000});
    expect(await restarted.synchronize(server), SyncPass.paused);
    expect(server.pushes, 0);
    await expectLater(
        restarted.initialize(
            datasetId: 'synthetic',
            epoch: 'epoch-1',
            deviceId: 'cloned-device'),
        throwsA(isA<SyncProtocolException>()));
  });

  test('durable pending operations retry after process-like store restart',
      () async {
    await seed();
    await post(phone, 'pending-restart', 100);
    final restarted = SyncStore(phone.db, now: () => now);
    await restarted.initialize(
        datasetId: 'synthetic', epoch: 'epoch-1', deviceId: 'phone');
    await restarted.synchronize(server);
    await pc.synchronize(server);
    expect(await balance(pc, bank), 900);
    expect(await restarted.pendingCount, 0);
  });

  test('concurrent workers cannot send the same outbox in overlapping passes',
      () async {
    await phone.stage([
      SyncEdit(bank, 0, {'balance': 1000})
    ]);
    final results = await Future.wait([
      phone.synchronize(server),
      phone.synchronize(server),
    ]);
    expect(results, contains(SyncPass.busy));
    expect(server.pushes, 1);
  });

  test('paginated log advances only through applied aggregates', () async {
    for (var i = 0; i < 105; i++) {
      await phone.stage([
        SyncEdit(SyncKey('note', '$i'), 0, {'text': 'synthetic'})
      ]);
    }
    await phone.synchronize(server);
    expect(await phone.pendingCount, 5);
    await phone.synchronize(server);
    await pc.synchronize(server);
    expect(await pc.cursor, 100);
    await pc.synchronize(server);
    expect(await pc.cursor, 105);
    expect(await pc.db.query('sync_lab_entities'), hasLength(105));
    expect(await pc.synchronize(server), SyncPass.idle);
  });
}
