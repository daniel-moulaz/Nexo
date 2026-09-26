import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

class NotificationInbox {
  static const channel = MethodChannel('com.ma.expensy/automation');
  static bool _syncing = false;
  static const knownApps = {
    'com.nu.production': 'Nubank',
    'com.mercadopago.wallet': 'Mercado Pago',
    'br.com.intermedium': 'Inter',
    'com.picpay': 'PicPay'
  };
  static Future<void> ingest(List<dynamic> rows, {DateTime? now}) async {
    final db = await DBHelper.database;
    final cutoff = (now ?? DateTime.now())
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        if (row['id'] is! String ||
            row['app_id'] is! String ||
            row['description'] is! String ||
            row['occurred_at'] is! int ||
            row['amount_cents'] is! int) continue;
        if ((row['amount_cents'] as int) <= 0 ||
            (row['occurred_at'] as int) < cutoff ||
            !['income', 'expense', 'refund', 'transfer'].contains(row['kind']))
          continue;
        await txn.insert(
            'notification_suggestions',
            {
              for (final key in [
                'id',
                'app_id',
                'amount_cents',
                'description',
                'kind',
                'medium',
                'occurred_at'
              ])
                key: row[key]
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      // Retain only the fingerprint tombstone after seven days, so replay cannot
      // resurrect an ignored/confirmed item, without retaining merchant data.
      await txn.rawUpdate(
          "UPDATE notification_suggestions SET status = CASE WHEN status = 'pending' THEN 'expired' ELSE status END, description = '', amount_cents = 0 WHERE occurred_at < ?",
          [cutoff]);
    });
  }

  static Future<void> sync() async {
    if (defaultTargetPlatform != TargetPlatform.android || _syncing) return;
    _syncing = true;
    try {
      final text = await channel.invokeMethod<String>('queue');
      final rows = text == null ? <dynamic>[] : jsonDecode(text) as List;
      await ingest(rows);
      await channel
          .invokeMethod('ack', {'ids': rows.map((r) => r['id']).toList()});
    } finally {
      _syncing = false;
    }
  }

  static Future<List<Map<String, dynamic>>> pending() async {
    await ingest([]);
    return (await DBHelper.database).query('notification_suggestions',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'occurred_at DESC');
  }

  static Future<void> ignore(String id) async => (await DBHelper.database)
      .update('notification_suggestions', {'status': 'ignored'},
          where: 'id = ? AND status = ?', whereArgs: [id, 'pending']);
}
