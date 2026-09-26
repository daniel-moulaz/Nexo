import 'package:path/path.dart';
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
      excludeFromSpending:
          (map['exclude_from_spending'] as int? ?? 0) == 1,
      installmentCurrent: map['installment_current'] as int?,
      installmentTotal: map['installment_total'] as int?,
      source: map['source'] as String? ?? 'manual',
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
    await _ensureSchema(_db!);
    return _db!;
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_metadata (
        transaction_id TEXT PRIMARY KEY,
        subcategory TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'paid',
        due_date TEXT,
        expense_class TEXT NOT NULL DEFAULT 'normal',
        exclude_from_spending INTEGER NOT NULL DEFAULT 0,
        installment_current INTEGER,
        installment_total INTEGER,
        source TEXT NOT NULL DEFAULT 'manual'
      )
    ''');

    final columns = await db.rawQuery('PRAGMA table_info(transaction_metadata)');
    final names = columns.map((e) => e['name']).toSet();

    Future<void> add(String name, String sql) async {
      if (!names.contains(name)) await db.execute(sql);
    }

    await add(
      'expense_class',
      "ALTER TABLE transaction_metadata ADD COLUMN expense_class TEXT NOT NULL DEFAULT 'normal'",
    );
    await add(
      'exclude_from_spending',
      'ALTER TABLE transaction_metadata ADD COLUMN exclude_from_spending INTEGER NOT NULL DEFAULT 0',
    );
    await add(
      'installment_current',
      'ALTER TABLE transaction_metadata ADD COLUMN installment_current INTEGER',
    );
    await add(
      'installment_total',
      'ALTER TABLE transaction_metadata ADD COLUMN installment_total INTEGER',
    );
    await add(
      'source',
      "ALTER TABLE transaction_metadata ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'",
    );
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

  Future<void> markAsPaid(String transactionId) async {
    final current = await getFor(transactionId);
    await save(
      TransactionMetadata(
        transactionId: current.transactionId,
        subcategory: current.subcategory,
        status: 'paid',
        dueDate: null,
        expenseClass: current.expenseClass,
        excludeFromSpending: current.excludeFromSpending,
        installmentCurrent: current.installmentCurrent,
        installmentTotal: current.installmentTotal,
        source: current.source,
      ),
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
