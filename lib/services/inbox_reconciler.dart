import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/db_helper.dart';
import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'import_rules_service.dart';
import 'notification_inbox.dart';
import 'pluggy_inbox.dart';
import 'reconciliation.dart';

/// What the inbox shows after the app did the boring part.
class InboxState {
  const InboxState(this.matches, this.resolved);

  /// Movements that need the person (maybe, own transfer, new).
  final List<Match> matches;

  /// Resolved automatically before, newest first: id → reason.
  final List<AutoResolved> resolved;
}

class AutoResolved {
  const AutoResolved(
      this.id, this.reason, this.description, this.amountCents, this.at,
      {this.transactionId});
  final String id, reason, description;
  final int amountCents;
  final DateTime at;
  final String? transactionId;

  /// Links are final on every device; only ignores can be undone.
  bool get undoable => transactionId == null;

  Map<String, Object?> toJson() => {
        'reason': reason,
        'description': description,
        'amount_cents': amountCents,
        'at': at.millisecondsSinceEpoch,
        if (transactionId != null) 'transaction_id': transactionId,
      };
  static AutoResolved fromJson(String id, Map<String, dynamic> j) =>
      AutoResolved(
          id,
          j['reason'] as String,
          j['description'] as String,
          j['amount_cents'] as int,
          DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
          transactionId: j['transaction_id'] as String?);
}

/// Applies [reconcile] to the pending suggestions: links what is certainly an
/// existing entry, sets aside reversals, reserve moves and tiny yields, and
/// remembers why, so the person can see and undo it. Never creates money.
class InboxReconciler {
  static const _resolvedKey = 'nexo_inbox_resolved_v1';
  static const _manualKey = 'nexo_inbox_manual_v1';
  static const _dismissedKey = 'nexo_inbox_dismissed_pairs_v1';
  static const ownerKey = 'nexo_owner_names_v1';
  static const autoKey = 'nexo_inbox_auto_v1';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<List<String>> ownerNames() async =>
      (await _prefs).getStringList(ownerKey) ?? const [];
  static Future<void> setOwnerNames(List<String> names) async =>
      (await _prefs).setStringList(ownerKey, [
        for (final n in names)
          if (n.trim().isNotEmpty) n.trim()
      ]);
  static Future<bool> automatic() async =>
      (await _prefs).getBool(autoKey) ?? true;
  static Future<void> setAutomatic(bool on) async =>
      (await _prefs).setBool(autoKey, on);

  static Future<Map<String, AutoResolved>> _resolved() async {
    final raw = (await _prefs).getString(_resolvedKey);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          e.key as String: AutoResolved.fromJson(
              e.key as String, (e.value as Map).cast<String, dynamic>())
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveResolved(Map<String, AutoResolved> all) async {
    final sorted = all.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    await (await _prefs).setString(
        _resolvedKey,
        jsonEncode({
          for (final r in sorted.take(500)) r.id: r.toJson(),
        }));
  }

  static Future<Set<String>> _set(String key) async =>
      ((await _prefs).getStringList(key) ?? const []).toSet();
  static Future<void> _add(String key, Iterable<String> values) async {
    final all = await _set(key)
      ..addAll(values);
    await (await _prefs).setStringList(key, all.take(2000).toList());
  }

  static String reasonLabel(String reason) => switch (reason) {
        'linked' => 'Já estava lançado',
        'reversal' => 'Pagamento estornado',
        'reserve' => 'Movimento de reserva',
        'smallYield' => 'Rendimento pequeno',
        _ => 'Resolvido',
      };

  /// Reconciles the pending suggestions and applies the automatic outcomes.
  static Future<InboxState> run({
    required List<Map<String, dynamic>> pendingRows,
    required List<AppTransaction> transactions,
    required Map<String, TransactionMetadata> metadata,
  }) async {
    final db = await DBHelper.database;
    final linked = {
      for (final r in await db.query('notification_suggestions',
          columns: ['transaction_id'],
          where: "status = 'confirmed' AND transaction_id IS NOT NULL"))
        r['transaction_id'] as String
    };
    final manual = await _set(_manualKey);
    final rules = await ImportRulesService.load();
    final learned = categoryFromHistory(transactions, metadata);
    final matches = reconcile(
        pending: [for (final r in pendingRows) PendingMovement.fromRow(r)],
        transactions: transactions,
        metadata: metadata,
        linkedIds: linked,
        ownerNames: await ownerNames(),
        dismissedPairs: await _set(_dismissedKey),
        learnedCategory: (m) {
          final type = m.outgoing ? 'expense' : 'income';
          final rule = rules
              .where((r) =>
                  r.type == type &&
                  r.pattern.trim().isNotEmpty &&
                  m.description
                      .toLowerCase()
                      .contains(r.pattern.trim().toLowerCase()))
              .firstOrNull;
          return rule?.categoryId ?? learned(m);
        });
    final resolved = await _resolved();
    final keep = <Match>[];
    final auto = await automatic();
    for (final m in matches) {
      // Undone by the person: never decided by the app again.
      if (!auto || !m.automatic || manual.contains(m.movement.id)) {
        keep.add(m.automatic
            ? Match(m.movement, Resolution.newEntry, categoryId: m.categoryId)
            : m);
        continue;
      }
      final mv = m.movement;
      try {
        if (m.resolution == Resolution.linked) {
          await DBHelper.confirmSuggestion(db, mv.id, m.transaction!.id);
        } else {
          await NotificationInbox.ignore(mv.id);
        }
      } on StateError {
        // Resolved meanwhile (another device or screen): nothing to do.
        continue;
      }
      resolved[mv.id] = AutoResolved(mv.id, m.resolution.name, mv.description,
          mv.amountCents, DateTime.now(),
          transactionId: m.transaction?.id);
    }
    await _saveResolved(resolved);
    return InboxState(
        keep, resolved.values.toList()..sort((a, b) => b.at.compareTo(a.at)));
  }

  /// "It is the same": the movement is the existing entry.
  static Future<void> link(String suggestionId, String transactionId) async =>
      DBHelper.confirmSuggestion(
          await DBHelper.database, suggestionId, transactionId);

  /// "They are different": never pair them again.
  static Future<void> dismissPair(String suggestionId, String transactionId) =>
      _add(_dismissedKey, ['$suggestionId|$transactionId']);

  /// Back to the inbox; the app will not decide it by itself again.
  static Future<void> undo(AutoResolved r) async {
    if (!r.undoable) return;
    await _add(_manualKey, [r.id]);
    await NotificationInbox.undoIgnore(r.id);
    if (PluggyInbox.isPluggy(r.id))
      await PluggyInbox.instance?.undoIgnore(r.id);
    final all = await _resolved()
      ..remove(r.id);
    await _saveResolved(all);
  }

  /// Ignores many at once (own transfers already in the balances, or what
  /// the person marked as reviewed).
  static Future<void> ignoreAll(Iterable<String> ids) async {
    for (final id in ids) {
      await NotificationInbox.ignore(id);
    }
  }
}
