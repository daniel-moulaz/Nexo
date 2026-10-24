import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// "Não vou renovar": subscriptions the person wants to cancel, with how many
/// days before the next charge to be reminded. Kept on this device; nothing
/// changes in the ledger (the charge still comes until it is cancelled).
class CancelIntents {
  static const _key = 'nexo_cancel_intents_v1';
  static const dismissedAlertsKey = 'nexo_charge_alerts_dismissed_v1';

  static Future<Map<String, int>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> set(String recurringId, int? daysBefore) async {
    final all = await load();
    if (daysBefore == null) {
      all.remove(recurringId);
    } else {
      all[recurringId] = daysBefore;
    }
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(all));
  }

  /// Due to cancel now: within [days] of the next charge (or overdue).
  static bool due(RecurringPayment r, int days, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final next = DateTime(r.nextDate.year, r.nextDate.month, r.nextDate.day);
    return !today.isBefore(next.subtract(Duration(days: days)));
  }

  static Future<Set<String>> dismissedAlerts() async {
    try {
      return ((await SharedPreferences.getInstance())
                  .getStringList(dismissedAlertsKey) ??
              const [])
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> dismissAlert(String key) async {
    final all = await dismissedAlerts()
      ..add(key);
    await (await SharedPreferences.getInstance())
        .setStringList(dismissedAlertsKey, all.take(500).toList());
  }
}
