import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Device-local choices, never a bank identity inference or financial backup data.
class NotificationPreferences {
  static const key = 'nexo_notification_accounts_v1';
  static String scope(String app, String medium, String type) =>
      '$app|$medium|$type';
  static Future<Map<String, String>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> remember(String scope, String account) async {
    final rules = await load();
    rules[scope] = account;
    if (!await (await SharedPreferences.getInstance())
        .setString(key, jsonEncode(rules))) {
      throw StateError('Não foi possível lembrar esta escolha.');
    }
  }

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(key);
  static String? suggest(
      Map<String, String> rules, String scope, List<Account> accounts,
      {required String medium, required String type}) {
    final id = rules[scope];
    final account = accounts.where((a) => a.id == id).firstOrNull;
    if (account == null ||
        account.isGold ||
        account.currency != 'BRL' ||
        (type == 'transfer' && account.type == 'credit') ||
        (medium == 'credit' && account.type != 'credit') ||
        (medium == 'bank' && account.type == 'credit')) return null;
    return id;
  }
}
