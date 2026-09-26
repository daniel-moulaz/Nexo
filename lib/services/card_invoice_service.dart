import '../database/db_helper.dart';
import 'package:sqflite/sqflite.dart';

class CardInvoiceService {
  CardInvoiceService._();

  static final CardInvoiceService instance = CardInvoiceService._();
  Future<Database> get _database => DBHelper.database;

  String _cycleKey(DateTime cycleEnd) =>
      '${cycleEnd.year.toString().padLeft(4, '0')}-${cycleEnd.month.toString().padLeft(2, '0')}-${cycleEnd.day.toString().padLeft(2, '0')}';

  Future<double> paidForCycle(String cardId, DateTime cycleEnd) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT SUM(amount) AS total FROM card_invoice_payments WHERE card_id = ? AND cycle_end = ?',
      [cardId, _cycleKey(cycleEnd)],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> recordPayment({
    required String id,
    required String cardId,
    required DateTime cycleEnd,
    required double amount,
  }) async {
    final db = await _database;
    await db.insert(
      'card_invoice_payments',
      {
        'id': id,
        'card_id': cardId,
        'cycle_end': _cycleKey(cycleEnd),
        'amount': amount,
        'paid_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
