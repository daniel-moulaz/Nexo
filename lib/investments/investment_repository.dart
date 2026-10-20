import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import 'investment_models.dart';
import '../models/models.dart';
import '../services/transaction_metadata_service.dart';
import '../sync/ledger_capture.dart';

class InvestmentRepository {
  static final revision = ValueNotifier<int>(0);
  final Future<Database> Function() database;
  InvestmentRepository({Future<Database> Function()? database})
      : database = database ?? (() => DBHelper.database);

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS investments (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, asset_class TEXT NOT NULL,
      ticker TEXT NOT NULL, institution TEXT NOT NULL,
      price_micros INTEGER NOT NULL CHECK(price_micros >= 0),
      price_at TEXT NOT NULL, price_source TEXT NOT NULL,
      archived INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS investment_operations (
      id TEXT PRIMARY KEY, investment_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('buy','sell','opening','income')),
      quantity INTEGER NOT NULL CHECK(quantity >= 0),
      cents INTEGER NOT NULL CHECK(cents >= 0),
      date TEXT NOT NULL, created_at TEXT NOT NULL, cash_account_id TEXT)''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS investment_ops_asset ON investment_operations(investment_id)');
  }

  static List<InvestmentPosition> decode(
      List<Map<String, dynamic>> assets, List<Map<String, dynamic>> entries) {
    final investments = assets.map(Investment.fromMap).toList();
    final operations = entries.map(InvestmentOperation.fromMap).toList();
    final ids = investments.map((i) => i.id).toSet();
    if (ids.length != investments.length ||
        operations.map((o) => o.id).toSet().length != operations.length ||
        operations.any((o) => !ids.contains(o.investmentId))) {
      throw const FormatException(
          'Carteira inválida: identificadores ou vínculos inconsistentes.');
    }
    return [
      for (final i in investments)
        InvestmentPosition(i, operations.where((o) => o.investmentId == i.id))
    ];
  }

  Future<List<InvestmentPosition>> load() async {
    final db = await database();
    return db.transaction((tx) async => decode(await tx.query('investments'),
        await tx.query('investment_operations')));
  }

  Future<void> create(Investment item, InvestmentOperation opening) async {
    InvestmentPosition(item, [opening]);
    if (!['opening', 'buy'].contains(opening.kind)) {
      throw const FormatException('Comece com uma posição inicial ou compra.');
    }
    final db = await database();
    await ledgerTransaction(db, 'investment.create', (tx) async {
      await tx.insert('investments', item.toMap());
      await tx.insert('investment_operations', opening.toMap());
      await _cash(tx, opening, item.name);
    });
    revision.value++;
  }

  Future<void> record(InvestmentOperation op) async {
    op.validate();
    if (op.kind == 'opening')
      throw const FormatException('Posição inicial já cadastrada.');
    final db = await database();
    await ledgerTransaction(db, 'investment.record', (tx) async {
      final rows = await tx
          .query('investments', where: 'id=?', whereArgs: [op.investmentId]);
      if (rows.isEmpty)
        throw const FormatException('Investimento não encontrado.');
      final previous = await tx
          .query('investment_operations', where: 'id=?', whereArgs: [op.id]);
      if (previous.isNotEmpty) {
        if (!mapEquals(previous.single, op.toMap())) {
          throw const FormatException(
              'Identificador já utilizado por outra operação.');
        }
        return; // Retrying the same confirmed operation is harmless.
      }
      final entries = await tx.query('investment_operations',
          where: 'investment_id=?', whereArgs: [op.investmentId]);
      InvestmentPosition(Investment.fromMap(rows.single),
          [...entries.map(InvestmentOperation.fromMap), op]);
      await tx.insert('investment_operations', op.toMap());
      await _cash(tx, op, rows.single['name'] as String);
      await tx.update('investments', {'archived': 0},
          where: 'id=?', whereArgs: [op.investmentId]);
    });
    revision.value++;
  }

  Future<void> removeOperation(String id) async {
    final db = await database();
    await ledgerTransaction(db, 'investment.remove_operation', (tx) async {
      final rows = await tx
          .query('investment_operations', where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final assetId = rows.single['investment_id'];
      final assets =
          await tx.query('investments', where: 'id=?', whereArgs: [assetId]);
      final entries = await tx.query('investment_operations',
          where: 'investment_id=? AND id<>?', whereArgs: [assetId, id]);
      InvestmentPosition(Investment.fromMap(assets.single),
          entries.map(InvestmentOperation.fromMap));
      final op = InvestmentOperation.fromMap(rows.single);
      if (op.cashAccountId != null) {
        final linked = await tx
            .query('transactions', where: 'id=?', whereArgs: [cashId(op.id)]);
        if (linked.length != 1 ||
            linked.single['account_id'] != op.cashAccountId ||
            ((linked.single['amount'] as num) * 100).round() != op.cents) {
          throw const FormatException(
              'Movimentação vinculada inconsistente. Nenhum valor foi alterado.');
        }
        final changed = await tx.rawUpdate(
            'UPDATE accounts SET balance=balance+? WHERE id=?', [
          cashDebit(op) ? op.cents / 100 : -op.cents / 100,
          op.cashAccountId
        ]);
        if (changed != 1)
          throw const FormatException('Conta vinculada não encontrada.');
        await tx.delete('transaction_metadata',
            where: 'transaction_id=?', whereArgs: [cashId(op.id)]);
        await tx
            .delete('transactions', where: 'id=?', whereArgs: [cashId(op.id)]);
      }
      await tx.delete('investment_operations', where: 'id=?', whereArgs: [id]);
      await tx.update('investments', {'archived': 0},
          where: 'id=?', whereArgs: [assetId]);
    });
    revision.value++;
  }

  static String cashId(String operationId) => 'investment:$operationId';
  static bool cashDebit(InvestmentOperation op) =>
      op.kind == 'buy' || op.kind == 'opening';

  static void validateCashBackup(Map<String, dynamic> data) {
    final operations = ((data['investment_operations'] as List?) ?? [])
        .map((r) =>
            InvestmentOperation.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
    final transactions = {
      for (final r in (data['transactions'] as List? ?? [])) (r as Map)['id']: r
    };
    final metadata = {
      for (final r in (data['transaction_metadata'] as List? ?? []))
        (r as Map)['transaction_id']: r
    };
    final accounts = {
      for (final r in (data['accounts'] as List? ?? [])) (r as Map)['id']: r
    };
    final linked = <String>{};
    for (final op in operations.where((o) => o.cashAccountId != null)) {
      final id = cashId(op.id);
      final tx = transactions[id],
          meta = metadata[id],
          account = accounts[op.cashAccountId];
      if (account == null ||
          account['currency'] != 'BRL' ||
          ['credit', 'gold'].contains(account['type']) ||
          tx == null ||
          tx['account_id'] != op.cashAccountId ||
          tx['currency'] != 'BRL' ||
          tx['amount'] is! num ||
          !(tx['amount'] as num).isFinite ||
          ((tx['amount'] as num) * 100).round() != op.cents ||
          tx['type'] != (cashDebit(op) ? 'expense' : 'income') ||
          meta == null ||
          meta['source'] != id ||
          meta['status'] != 'paid' ||
          meta['affects_balance'] != 1 ||
          meta['exclude_from_spending'] != (op.kind == 'income' ? 0 : 1)) {
        throw const FormatException(
            'Backup contém uma movimentação de investimento inconsistente. Nenhum dado foi alterado.');
      }
      linked.add(id);
    }
    if (transactions.keys.any((id) =>
        id is String && id.startsWith('investment:') && !linked.contains(id))) {
      throw const FormatException(
          'Backup contém movimentação sem operação de investimento.');
    }
  }

  Future<void> _cash(
      DatabaseExecutor tx, InvestmentOperation op, String name) async {
    if (op.cashAccountId == null) return;
    op.validate();
    final accounts = await tx
        .query('accounts', where: 'id=?', whereArgs: [op.cashAccountId]);
    if (accounts.length != 1 ||
        accounts.single['currency'] != 'BRL' ||
        ['credit', 'gold'].contains(accounts.single['type'])) {
      throw const FormatException(
          'Selecione uma conta de saldo em reais, sem ser cartão ou ouro.');
    }
    final type = cashDebit(op) ? 'expense' : 'income';
    final categories = await tx.query('categories',
        where: 'type=?', whereArgs: [type], limit: 1);
    final id = cashId(op.id);
    await tx.insert(
        'transactions',
        AppTransaction(
          id: id,
          type: type,
          amount: op.cents / 100,
          description:
              '${cashDebit(op) ? 'Aporte' : op.kind == 'sell' ? 'Resgate' : 'Provento'} · $name',
          accountId: op.cashAccountId!,
          categoryId:
              categories.isEmpty ? '' : categories.single['id'] as String,
          date: op.date,
          currency: 'BRL',
          note: 'Vinculado a Investir. Revise a operação na carteira.',
        ).toMap());
    await tx.insert(
        'transaction_metadata',
        TransactionMetadata(
          transactionId: id,
          source: id,
          excludeFromSpending: op.kind != 'income',
        ).toMap());
    await tx.rawUpdate('UPDATE accounts SET balance=balance+? WHERE id=?',
        [cashDebit(op) ? -op.cents / 100 : op.cents / 100, op.cashAccountId]);
  }

  /// Explicit reconciliation only. Existing operations remain unlinked until
  /// the user confirms that this cash effect has not already been recorded.
  Future<void> linkCash(String operationId, String accountId) async {
    final db = await database();
    await ledgerTransaction(db, 'investment.link_cash', (tx) async {
      final rows = await tx.query('investment_operations',
          where: 'id=?', whereArgs: [operationId]);
      if (rows.length != 1)
        throw const FormatException('Operação não encontrada.');
      final old = InvestmentOperation.fromMap(rows.single);
      if (old.cashAccountId != null) {
        if (old.cashAccountId == accountId) return;
        throw const FormatException('Esta operação já movimenta uma conta.');
      }
      final op = InvestmentOperation.fromMap(
          {...rows.single, 'cash_account_id': accountId});
      final asset = (await tx.query('investments',
              where: 'id=?', whereArgs: [op.investmentId]))
          .single;
      await _cash(tx, op, asset['name'] as String);
      await tx.update('investment_operations', {'cash_account_id': accountId},
          where: 'id=?', whereArgs: [operationId]);
    });
    revision.value++;
  }

  Future<void> archive(String id, {bool archived = true}) async {
    final db = await database();
    await ledgerTransaction(db, 'investment.archive', (tx) async {
      final rows =
          await tx.query('investments', where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty)
        throw const FormatException('Investimento não encontrado.');
      final entries = await tx.query('investment_operations',
          where: 'investment_id=?', whereArgs: [id]);
      final position = InvestmentPosition(Investment.fromMap(rows.single),
          entries.map(InvestmentOperation.fromMap));
      if (archived && position.quantity != 0) {
        throw const FormatException(
            'Encerre a posição antes de retirá-la da carteira.');
      }
      await tx.update('investments', {'archived': archived ? 1 : 0},
          where: 'id=?', whereArgs: [id]);
    });
    revision.value++;
  }

  Future<void> price(String id, int micros, DateTime at, String source) async {
    if (micros < 0 ||
        micros > 1000000000000 ||
        !['manual', 'brapi'].contains(source)) {
      throw const FormatException('Cotação inválida.');
    }
    final db = await database();
    // A market quote is fetched by each device; only a price typed by the
    // person is a decision worth sending to another device.
    await ledgerTransaction(db, 'investment.price', (tx) async {
      final rows =
          await tx.query('investments', where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final item = Investment.fromMap(rows.single);
      if (source == 'brapi' && at.isBefore(item.priceAt)) return;
      await tx.update(
          'investments',
          {
            'price_micros': micros,
            'price_at': at.toUtc().toIso8601String(),
            'price_source': source
          },
          where: 'id=?',
          whereArgs: [id]);
    }, scope: source == 'brapi' ? LedgerScope.derived : LedgerScope.user);
    revision.value++;
  }
}
