import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
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
      archived INTEGER NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'BRL',
      fx_micros INTEGER NOT NULL DEFAULT 1000000)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS investment_operations (
      id TEXT PRIMARY KEY, investment_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('buy','sell','opening','income')),
      quantity INTEGER NOT NULL CHECK(quantity >= 0),
      cents INTEGER NOT NULL CHECK(cents >= 0),
      date TEXT NOT NULL, created_at TEXT NOT NULL, cash_account_id TEXT,
      brl_cents INTEGER, tax_cents INTEGER NOT NULL DEFAULT 0)''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS investment_ops_asset ON investment_operations(investment_id)');
  }

  /// Schema 28: assets in dollars. Only adds columns, whose defaults are
  /// exactly what every existing row already meant (reais).
  static Future<void> addCurrency(DatabaseExecutor db) async {
    Future<void> add(String table, String column, String type) async {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((c) => c['name'] == column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      }
    }

    await add('investments', 'currency', "TEXT NOT NULL DEFAULT 'BRL'");
    await add('investments', 'fx_micros', 'INTEGER NOT NULL DEFAULT 1000000');
    await add('investment_operations', 'brl_cents', 'INTEGER');
    await add(
        'investment_operations', 'tax_cents', 'INTEGER NOT NULL DEFAULT 0');
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
      await _cash(tx, opening, item.name, currency: item.currency);
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
      await _cash(tx, op, rows.single['name'] as String,
          currency: rows.single['currency'] as String? ?? 'BRL');
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
    final currencies = {
      for (final r in (data['investments'] as List? ?? []))
        (r as Map)['id']: (r['currency'] as String?) ?? 'BRL'
    };
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
      final currency = currencies[op.investmentId] ?? 'BRL';
      if (account == null ||
          account['currency'] != currency ||
          ['credit', 'gold'].contains(account['type']) ||
          tx == null ||
          tx['account_id'] != op.cashAccountId ||
          tx['currency'] != currency ||
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

  /// The same id on every device, so two of them never create it twice.
  static String cashCategoryId(String type) =>
      type == 'expense' ? 'investments-expense' : 'investments-income';

  /// Investment cash used to take the first category of its type, which is
  /// how a sale came to read as a salary.
  Future<String> _cashCategory(DatabaseExecutor tx, String type) async {
    final id = cashCategoryId(type);
    // One the person already has counts: never a second with the same name.
    final found = await tx.query('categories',
        columns: ['id'],
        where:
            "id=? OR (type=? AND LOWER(name) IN ('investimentos', 'investment'))",
        whereArgs: [id, type],
        limit: 1);
    if (found.isNotEmpty) return found.single['id'] as String;
    await tx.insert(
        'categories',
        AppCategory(
                id: id,
                name: 'Investimentos',
                type: type,
                colorValue: 0xFF00695C,
                iconCodePoint: Icons.show_chart.codePoint)
            .toMap());
    return id;
  }

  /// Money for an asset leaves and returns in the asset's own currency: a
  /// dollar stock moves a dollar account, and changing reais into dollars is
  /// a separate step (an exchange between accounts).
  Future<void> _cash(DatabaseExecutor tx, InvestmentOperation op, String name,
      {required String currency}) async {
    if (op.cashAccountId == null) return;
    op.validate();
    final accounts = await tx
        .query('accounts', where: 'id=?', whereArgs: [op.cashAccountId]);
    if (accounts.length != 1 ||
        accounts.single['currency'] != currency ||
        ['credit', 'gold'].contains(accounts.single['type'])) {
      throw FormatException(currency == 'BRL'
          ? 'Selecione uma conta de saldo em reais, sem ser cartão ou ouro.'
          : 'Selecione uma conta em $currency, como a conta em dólar da corretora. Para trocar reais por dólares, faça antes um câmbio entre as contas.');
    }
    final type = cashDebit(op) ? 'expense' : 'income';
    final categoryId = await _cashCategory(tx, type);
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
          categoryId: categoryId,
          date: op.date,
          currency: currency,
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
      await _cash(tx, op, asset['name'] as String,
          currency: asset['currency'] as String? ?? 'BRL');
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

  /// [fxMicros] is the rate of the day for an asset in another currency;
  /// without it the last rate stays.
  Future<void> price(String id, int micros, DateTime at, String source,
      {int? fxMicros}) async {
    if (micros < 0 ||
        micros > 1000000000000 ||
        (fxMicros != null && (fxMicros <= 0 || fxMicros > 1000 * fxScale)) ||
        !['manual', 'brapi', 'mercado'].contains(source)) {
      throw const FormatException('Cotação inválida.');
    }
    final market = source != 'manual';
    final db = await database();
    // A market quote is fetched by each device; only a price typed by the
    // person is a decision worth sending to another device.
    await ledgerTransaction(db, 'investment.price', (tx) async {
      final rows =
          await tx.query('investments', where: 'id=?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final item = Investment.fromMap(rows.single);
      if (market && at.isBefore(item.priceAt)) return;
      await tx.update(
          'investments',
          {
            'price_micros': micros,
            'price_at': at.toUtc().toIso8601String(),
            'price_source': source,
            if (item.foreign && fxMicros != null) 'fx_micros': fxMicros
          },
          where: 'id=?',
          whereArgs: [id]);
    }, scope: market ? LedgerScope.derived : LedgerScope.user);
    revision.value++;
  }

  /// Today's rate for every asset in [currency], as the accounts use it, so
  /// a dollar account and a dollar stock never disagree in reais. Each
  /// device reads the rate itself, like a quote.
  Future<void> refreshFx(String currency, int fxMicros) async {
    if (currency == 'BRL' || fxMicros <= 0 || fxMicros > 1000 * fxScale) {
      return;
    }
    final db = await database();
    var changed = 0;
    await ledgerTransaction(db, 'investment.fx', (tx) async {
      changed = await tx.update('investments', {'fx_micros': fxMicros},
          where: 'currency=? AND fx_micros<>?',
          whereArgs: [currency, fxMicros]);
    }, scope: LedgerScope.derived);
    if (changed > 0) revision.value++;
  }
}
