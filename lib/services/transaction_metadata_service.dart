import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class TransactionMetadata {
  final String transactionId;
  final String subcategory;
  final String status; // paid | pending
  final DateTime? dueDate;

  const TransactionMetadata({
    required this.transactionId,
    this.subcategory = '',
    this.status = 'paid',
    this.dueDate,
  });

  bool get isPending => status == 'pending';

  bool get isOverdue {
    if (!isPending || dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  Map<String, dynamic> toMap() => {
        'transaction_id': transactionId,
        'subcategory': subcategory,
        'status': status,
        'due_date': dueDate?.toIso8601String(),
      };

  static TransactionMetadata fromMap(Map<String, dynamic> map) {
    return TransactionMetadata(
      transactionId: map['transaction_id'] as String? ?? '',
      subcategory: map['subcategory'] as String? ?? '',
      status: map['status'] as String? ?? 'paid',
      dueDate: map['due_date'] != null
          ? DateTime.tryParse(map['due_date'] as String)
          : null,
    );
  }
}

class TransactionMetadataService {
  TransactionMetadataService._();

  static final TransactionMetadataService instance =
      TransactionMetadataService._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dbPath = join(await getDatabasesPath(), 'expensy.db');
    _db = await openDatabase(dbPath);
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS transaction_metadata (
        transaction_id TEXT PRIMARY KEY,
        subcategory TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'paid',
        due_date TEXT
      )
    ''');
    return _db!;
  }

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
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'transaction_metadata',
      where: 'transaction_id IN ($placeholders)',
      whereArgs: ids,
    );

    final result = <String, TransactionMetadata>{};
    for (final row in rows) {
      final metadata = TransactionMetadata.fromMap(row);
      result[metadata.transactionId] = metadata;
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
  }

  Future<void> delete(String transactionId) async {
    final db = await _database;
    await db.delete(
      'transaction_metadata',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
  }
}
