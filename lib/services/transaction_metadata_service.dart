import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import 'package:sqflite/sqflite.dart';

class TransactionMetadata {
  final String transactionId;
  final String subcategory;
  final String status; // paid | pending
  final DateTime? dueDate;
  final String expenseClass; // normal | extraordinary
  final bool excludeFromSpending;
  final int? installmentCurrent;
  final int? installmentTotal;
  final bool affectsBalance;
  final String source; // manual | import | recurring

  const TransactionMetadata({
    required this.transactionId,
    this.subcategory = '',
    this.status = 'paid',
    this.dueDate,
    this.expenseClass = 'normal',
    this.excludeFromSpending = false,
    this.installmentCurrent,
    this.installmentTotal,
    this.source = 'manual',
    this.affectsBalance = true,
  });

  bool get isPending => status == 'pending';

  bool get isOverdue {
    if (!isPending || dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  String get installmentLabel {
    if (installmentCurrent == null || installmentTotal == null) return '';
    return '$installmentCurrent/$installmentTotal';
  }

  Map<String, dynamic> toMap() => {
        'transaction_id': transactionId,
        'subcategory': subcategory,
        'status': status,
        'due_date': dueDate?.toIso8601String(),
        'expense_class': expenseClass,
        'exclude_from_spending': excludeFromSpending ? 1 : 0,
        'installment_current': installmentCurrent,
        'installment_total': installmentTotal,
        'source': source,
        'affects_balance': affectsBalance ? 1 : 0,
      };

  static TransactionMetadata fromMap(Map<String, dynamic> map) {
    return TransactionMetadata(
      transactionId: map['transaction_id'] as String? ?? '',
      subcategory: map['subcategory'] as String? ?? '',
      status: map['status'] as String? ?? 'paid',
      dueDate: map['due_date'] != null
          ? DateTime.tryParse(map['due_date'] as String)
          : null,
      expenseClass: map['expense_class'] as String? ?? 'normal',
      excludeFromSpending: (map['exclude_from_spending'] as int? ?? 0) == 1,
      installmentCurrent: map['installment_current'] as int?,
      installmentTotal: map['installment_total'] as int?,
      source: map['source'] as String? ?? 'manual',
      affectsBalance: (map['affects_balance'] as int? ?? 1) == 1,
    );
  }
}

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

  Future<void> save(TransactionMetadata metadata) async {
    final db = await _database;
    await db.insert(
      'transaction_metadata',
      metadata.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    revision.value++;
  }

  Future<void> delete(String transactionId) async {
    final db = await _database;
    await db.delete(
      'transaction_metadata',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
    revision.value++;
  }
}
