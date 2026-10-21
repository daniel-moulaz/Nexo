import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import '../sync/supabase_auth.dart';
import '../sync/sync_config.dart';

class PluggyItem {
  const PluggyItem(this.itemId, this.label, this.state, this.message);
  final String itemId, label;

  /// ok | updating | reconnect | expiring | error | unknown (never read yet)
  final String state;
  final String message;

  static PluggyItem fromJson(Map<String, dynamic> json) {
    final health = json['health'] as Map<String, dynamic>?;
    return PluggyItem(
        json['item_id'] as String,
        json['label'] as String,
        health?['state'] as String? ?? 'unknown',
        health?['message'] as String? ??
            'Ainda não lido. Toque em Atualizar agora.');
  }
}

/// A server answer the person can act on.
class PluggyUnavailable implements Exception {
  const PluggyUnavailable(this.message);
  final String message;
  @override
  String toString() => 'PluggyUnavailable';
}

abstract interface class PluggyRemote {
  /// Asks the server to read Pluggy now (it limits how often it really does).
  Future<List<PluggyItem>> refresh({bool force = false});
  Future<List<PluggyItem>> items();
  Future<void> addItem(String itemId, String label);
  Future<void> removeItem(String itemId);
  Future<List<Map<String, dynamic>>> suggestions(int sinceMs);
  Future<void> decide(List<Map<String, Object?>> decisions);
}

class SupabasePluggyRemote implements PluggyRemote {
  SupabasePluggyRemote(this.config, this.auth,
      {http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;
  final SyncConfig config;
  final SupabaseAuth auth;
  final http.Client Function() _clientFactory;

  Future<Object?> _post(String path, Object body) async {
    final token = await auth.accessToken();
    if (token == null) {
      throw const PluggyUnavailable(
          'Entre na sua conta em Sincronizar dispositivos.');
    }
    final client = _clientFactory();
    try {
      final response = await client
          .post(config.projectUrl.resolve(path),
              headers: {
                'apikey': config.publishableKey,
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      final status = response.statusCode;
      if (status == 200 || status == 204) {
        return response.body.isEmpty ? null : jsonDecode(response.body);
      }
      String? code;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map)
          code = (decoded['error'] ?? decoded['message']) as String?;
      } catch (_) {}
      throw PluggyUnavailable(switch ((status, code)) {
        (404, _) when path.startsWith('/functions') =>
          'A busca no Pluggy ainda não foi publicada no servidor.',
        (503, 'not_configured') =>
          'As credenciais do Pluggy ainda não foram cadastradas no servidor.',
        (403, 'not_owner') => 'Esta conta não é a dona das conexões Pluggy.',
        (401 || 403, _) => 'Entre novamente na sua conta para buscar no banco.',
        (_, 'too_many_items') => 'O Meu Pluggy permite até 5 conexões.',
        (_, 'invalid_item') =>
          'Identificador inválido. Copie o id do item no painel do Pluggy.',
        _ =>
          'O servidor não respondeu como esperado (HTTP $status). Tente mais tarde.',
      });
    } on TimeoutException {
      throw const PluggyUnavailable(
          'Sem resposta do servidor. Tente mais tarde.');
    } on http.ClientException {
      throw const PluggyUnavailable('Sem conexão com o servidor.');
    } finally {
      client.close();
    }
  }

  Future<Object?> _rpc(String name, Map<String, Object?> args) =>
      _post('/rest/v1/rpc/$name', args);

  List<PluggyItem> _items(Object? list) => [
        for (final i in (list as List? ?? const []))
          PluggyItem.fromJson((i as Map).cast<String, dynamic>())
      ];

  @override
  Future<List<PluggyItem>> refresh({bool force = false}) async {
    final result = await _post('/functions/v1/pluggy-sync', {'force': force});
    return _items((result as Map?)?['items']);
  }

  @override
  Future<List<PluggyItem>> items() async =>
      _items(await _rpc('nexo_pluggy_items', const {}));

  @override
  Future<void> addItem(String itemId, String label) =>
      _rpc('nexo_pluggy_add_item', {'p_item_id': itemId, 'p_label': label});

  @override
  Future<void> removeItem(String itemId) =>
      _rpc('nexo_pluggy_remove_item', {'p_item_id': itemId});

  @override
  Future<List<Map<String, dynamic>>> suggestions(int sinceMs) async => [
        for (final r
            in (await _rpc('nexo_pluggy_suggestions', {'p_since_ms': sinceMs})
                    as List? ??
                const []))
          (r as Map).cast<String, dynamic>()
      ];

  @override
  Future<void> decide(List<Map<String, Object?>> decisions) =>
      _rpc('nexo_pluggy_decide', {'p_decisions': decisions});
}

/// Open Finance movements as reviewable suggestions in the same inbox as the
/// bank notifications. The server keeps the decision of every suggestion so
/// all devices agree; confirming creates the transaction with a fixed id
/// (`notification:pluggy:<id>`), so two devices can never register it twice.
class PluggyInbox {
  PluggyInbox(this.remote, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final PluggyRemote remote;
  final DateTime Function() _now;
  static PluggyInbox? instance;

  static const appId = 'pluggy';
  static const window = Duration(days: 35);
  static const _refreshEvery = Duration(minutes: 30);
  DateTime? _lastRefresh;
  Future<String?>? _running;

  static bool isPluggy(String suggestionId) =>
      suggestionId.startsWith('pluggy:');

  /// Sends local decisions, asks the server to read Pluggy when due, and
  /// brings suggestions and other devices' decisions. Returns a message for
  /// the person when something could not be done; local data stays valid.
  Future<String?> sync({bool force = false}) =>
      _running ??= _sync(force).whenComplete(() => _running = null);

  Future<String?> _sync(bool force) async {
    final db = await DBHelper.database;
    final since = _now().subtract(window).millisecondsSinceEpoch;
    String? problem;
    try {
      final decided = await db.query('notification_suggestions',
          where:
              "app_id = ? AND status IN ('confirmed', 'ignored') AND occurred_at >= ?",
          whereArgs: [appId, since]);
      for (var i = 0; i < decided.length; i += 500) {
        await remote.decide([
          for (final r in decided.skip(i).take(500))
            {
              'id': r['id'],
              'review': r['status'],
              if (r['transaction_id'] != null)
                'transaction_id': r['transaction_id'],
            }
        ]);
      }
      final last = _lastRefresh;
      if (force || last == null || _now().difference(last) >= _refreshEvery) {
        try {
          await remote.refresh(force: force);
          _lastRefresh = _now();
        } on PluggyUnavailable catch (e) {
          // Suggestions already on the server still arrive below.
          problem = e.message;
        }
      }
      await _apply(db, await remote.suggestions(since));
    } on PluggyUnavailable catch (e) {
      return e.message;
    }
    return problem;
  }

  Future<void> _apply(Database db, List<Map<String, dynamic>> rows) =>
      db.transaction((txn) async {
        for (final r in rows) {
          final id = r['id'], review = r['review'];
          if (id is! String || !isPluggy(id)) continue;
          if (review == 'pending') {
            final values = {
              'amount_cents': r['amount_cents'],
              'description': r['description'],
              'kind': r['kind'],
              'medium': r['medium'],
              'occurred_at': r['occurred_at'],
            };
            if (values.values.any((v) => v == null)) continue;
            final inserted = await txn.insert('notification_suggestions',
                {'id': id, 'app_id': appId, ...values},
                conflictAlgorithm: ConflictAlgorithm.ignore);
            // The bank corrected a suggestion nobody decided yet.
            if (inserted == 0) {
              await txn.update('notification_suggestions', values,
                  where: "id = ? AND status = 'pending'", whereArgs: [id]);
            }
          } else if (review == 'confirmed' || review == 'ignored') {
            // Resolved on another device: leave this inbox.
            await txn.update('notification_suggestions', {'status': review},
                where: "id = ? AND status = 'pending'", whereArgs: [id]);
          }
        }
      });

  /// Undo an ignore on this device and tell the server right away.
  Future<void> undoIgnore(String id) async {
    await remote.decide([
      {'id': id, 'review': 'pending'}
    ]);
  }
}
