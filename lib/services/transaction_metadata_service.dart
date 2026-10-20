import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import 'package:sqflite/sqflite.dart';

import '../models/transaction_metadata.dart';
export '../models/transaction_metadata.dart';

class TransactionMetadataService {
  TransactionMetadataService._();

  static final TransactionMetadataService instance =
      TransactionMetadataService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  Future<Database> get _database => DBHelper.database;

  Future<TransactionMetadata> getFor(String transactionId) async {
    final db = await _database;
    final rows = await db.query(
      'transaction_metadata',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return TransactionMetadata(transactionId: transactionId);
    }
    return TransactionMetadata.fromMap(rows.first);
  }

  Future<Map<String, TransactionMetadata>> getForMany(
    Iterable<String> transactionIds,
  ) async {
    final ids = transactionIds.toSet().toList();
    if (ids.isEmpty) return {};

    final db = await _database;
    final result = <String, TransactionMetadata>{};
    for (var offset = 0; offset < ids.length; offset += 400) {
      final chunk = ids.skip(offset).take(400).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query('transaction_metadata',
          where: 'transaction_id IN ($placeholders)', whereArgs: chunk);
      for (final row in rows) {
        final metadata = TransactionMetadata.fromMap(row);
        result[metadata.transactionId] = metadata;
      }
    }
    return result;
  }

  /// Classification only. Status or balance flags that change money must go
  /// through AppProvider, which adjusts the account in the same commit.
  Future<void> save(TransactionMetadata metadata) async {
    await DBHelper.operation(
        'metadata.save',
        (txn) => txn.insert('transaction_metadata', metadata.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace));
    revision.value++;
  }

  Future<void> delete(String transactionId) async {
    await DBHelper.operation(
        'metadata.delete',
        (txn) => txn.delete('transaction_metadata',
            where: 'transaction_id = ?', whereArgs: [transactionId]));
    revision.value++;
  }
}
