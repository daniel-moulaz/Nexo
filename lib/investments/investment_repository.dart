import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import 'investment_models.dart';

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
      price_at TEXT NOT NULL, price_source TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS investment_operations (
      id TEXT PRIMARY KEY, investment_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('buy','sell','opening','income')),
      quantity INTEGER NOT NULL CHECK(quantity >= 0),
      cents INTEGER NOT NULL CHECK(cents >= 0),
      date TEXT NOT NULL, created_at TEXT NOT NULL)''');
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
    await db.transaction((tx) async {
      await tx.insert('investments', item.toMap());
      await tx.insert('investment_operations', opening.toMap());
    });
    revision.value++;
  }

  Future<void> record(InvestmentOperation op) async {
    op.validate();
    if (op.kind == 'opening')
      throw const FormatException('Posição inicial já cadastrada.');
    final db = await database();
    await db.transaction((tx) async {
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
    });
    revision.value++;
  }

  Future<void> removeOperation(String id) async {
    final db = await database();
    await db.transaction((tx) async {
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
      await tx.delete('investment_operations', where: 'id=?', whereArgs: [id]);
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
    await db.transaction((tx) async {
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
    });
    revision.value++;
  }
}
