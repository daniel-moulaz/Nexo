import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../database/db_helper.dart';
import '../models/models.dart';
import '../models/transaction_metadata.dart';
import '../providers/app_provider.dart';
import '../services/pluggy_inbox.dart';
import 'supabase_auth.dart';
import 'sync_config.dart';

/// A request from the AI assistant, as claimed by this device.
class AssistantCommand {
  const AssistantCommand(this.id, this.kind, this.args);
  final String id, kind;
  final Map<String, dynamic> args;
}

abstract interface class AssistantRemote {
  Future<AssistantCommand?> claim(String datasetId, String deviceId);
  Future<void> finish(String id, String status, Map<String, Object?> result);
}

class SupabaseAssistantRemote implements AssistantRemote {
  SupabaseAssistantRemote(this.config, this.auth);
  final SyncConfig config;
  final SupabaseAuth auth;

  Future<Object?> _rpc(String name, Map<String, Object?> args) async {
    final token = await auth.accessToken();
    if (token == null) throw StateError('not_signed_in');
    final response = await http
        .post(config.projectUrl.resolve('/rest/v1/rpc/$name'),
            headers: {
              'apikey': config.publishableKey,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(args))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw StateError('assistant_http_${response.statusCode}');
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  @override
  Future<AssistantCommand?> claim(String datasetId, String deviceId) async {
    final r = await _rpc(
        'nexo_mcp_claim', {'p_dataset_id': datasetId, 'p_device_id': deviceId});
    if (r is! Map) return null;
    return AssistantCommand(r['id'] as String, r['kind'] as String,
        (r['args'] as Map).cast<String, dynamic>());
  }

  @override
  Future<void> finish(String id, String status, Map<String, Object?> result) =>
      _rpc('nexo_mcp_finish',
          {'p_id': id, 'p_status': status, 'p_result': result});
}

/// Applies the assistant's requests on this device through the same
/// provider methods the screens use, so every rule (balances, cards,
/// transfers, investments) holds. Applying is idempotent: a request that was
/// applied but not reported is never applied twice.
class AssistantCommands {
  AssistantCommands(this.remote, this.app);
  final AssistantRemote remote;
  final AppProvider app;
  static AssistantCommands? instance;

  static const _appliedKey = 'nexo_assistant_applied_v1';
  Future<int>? _running;

  /// Claims and applies pending requests (at most [max]); returns how many.
  Future<int> run(
          {required String datasetId,
          required String deviceId,
          int max = 20}) =>
      _running ??=
          _run(datasetId, deviceId, max).whenComplete(() => _running = null);

  Future<int> _run(String datasetId, String deviceId, int max) async {
    var count = 0;
    for (; count < max; count++) {
      final command = await remote.claim(datasetId, deviceId);
      if (command == null) break;
      final applied = await _applied();
      final previous = applied[command.id];
      final (status, result) = previous != null
          ? (
              previous['status'] as String,
              (previous['result'] as Map).cast<String, Object?>()
            )
          : await _apply(command);
      if (previous == null) {
        applied[command.id] = {'status': status, 'result': result};
        await _remember(applied);
      }
      await remote.finish(command.id, status, result);
    }
    return count;
  }

  Future<Map<String, Map<String, dynamic>>> _applied() async {
    final raw = (await SharedPreferences.getInstance()).getString(_appliedKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map(
        (k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()));
  }

  Future<void> _remember(Map<String, Map<String, dynamic>> applied) async {
    // Bounded: requests older than the last 300 are long finished.
    final keep = applied.entries.toList();
    final trimmed = Map.fromEntries(
        keep.length > 300 ? keep.sublist(keep.length - 300) : keep);
    await (await SharedPreferences.getInstance())
        .setString(_appliedKey, jsonEncode(trimmed));
  }

  static DateTime _day(String? iso, [DateTime? keepTime]) {
    final d = DateTime.parse(iso!);
    return DateTime(
        d.year, d.month, d.day, keepTime?.hour ?? 12, keepTime?.minute ?? 0);
  }

  static double _reais(Object? cents) => (cents as num).toInt() / 100;

  Future<(String, Map<String, Object?>)> _apply(AssistantCommand c) async {
    try {
      final message = await _do(c);
      return ('done', message);
    } on FormatException catch (e) {
      return ('rejected', {'reason': e.message});
    } on ArgumentError catch (e) {
      return ('rejected', {'reason': '${e.message}'});
    } on StateError catch (e) {
      return ('rejected', {'reason': e.message});
    } catch (e) {
      return (
        'rejected',
        {'reason': 'Erro inesperado no app (${e.runtimeType}).'}
      );
    }
  }

  Account _account(Object? id) =>
      app.accountById(id as String? ?? '') ??
      (throw StateError('A conta não existe mais no Nexo.'));

  void _category(Object? id) {
    if (!app.categories.any((c) => c.id == id)) {
      throw StateError('A categoria não existe mais no Nexo.');
    }
  }

  Future<AppTransaction?> _transaction(String id) async {
    for (final t in await DBHelper.getTransactions()) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<Map<String, Object?>> _do(AssistantCommand c) async {
    final a = c.args;
    switch (c.kind) {
      case 'transaction.add':
        final id = 'assistant:${c.id}';
        if (await _transaction(id) != null) {
          return {'transaction_id': id, 'message': 'Já estava lançado.'};
        }
        final account = _account(a['account_id']);
        _category(a['category_id']);
        await app.addTransaction(
            AppTransaction(
                id: id,
                type: a['type'] as String,
                amount: _reais(a['amount_cents']),
                description: a['description'] as String,
                accountId: account.id,
                categoryId: a['category_id'] as String,
                date: _day(a['date'] as String?),
                note: a['note'] as String? ?? '',
                currency: account.currency),
            metadata:
                TransactionMetadata(transactionId: id, source: 'assistant'));
        return {'transaction_id': id, 'message': 'Lançado.'};
      case 'transfer.add':
        final from = _account(a['from_account_id']);
        final to = _account(a['to_account_id']);
        await app.addTransfer(
            fromId: from.id,
            toId: to.id,
            fromAmount: _reais(a['amount_cents']),
            note: a['note'] as String? ?? '',
            occurredAt: _day(a['date'] as String?));
        return {
          'message': 'Transferência lançada de ${from.name} para ${to.name}.'
        };
      case 'transaction.update':
        final original = await _transaction(a['id'] as String) ??
            (throw StateError('O lançamento não existe mais.'));
        final account = a.containsKey('account_id')
            ? _account(a['account_id'])
            : app.accountById(original.accountId);
        if (a.containsKey('category_id')) _category(a['category_id']);
        await app.updateTransaction(
            AppTransaction(
                id: original.id,
                type: original.type,
                amount: a.containsKey('amount_cents')
                    ? _reais(a['amount_cents'])
                    : original.amount,
                description:
                    a['description'] as String? ?? original.description,
                accountId: account?.id ?? original.accountId,
                categoryId: a['category_id'] as String? ?? original.categoryId,
                date: a.containsKey('date')
                    ? _day(a['date'] as String?, original.date)
                    : original.date,
                note: a['note'] as String? ?? original.note,
                currency: a.containsKey('account_id')
                    ? account!.currency
                    : original.currency),
            original);
        return {'transaction_id': original.id, 'message': 'Corrigido.'};
      case 'transaction.delete':
        final id = a['id'] as String;
        if (await _transaction(id) == null) {
          return {'transaction_id': id, 'message': 'Já não existia.'};
        }
        await app.deleteTransaction(id);
        return {'transaction_id': id, 'message': 'Apagado.'};
      case 'suggestion.confirm':
        return _confirmSuggestion(a);
      default:
        throw StateError('Pedido desconhecido.');
    }
  }

  Future<Map<String, Object?>> _confirmSuggestion(
      Map<String, dynamic> a) async {
    final sid = a['id'] as String;
    Future<Map<String, Object?>?> row() async {
      final rows = await (await DBHelper.database)
          .query('notification_suggestions', where: 'id = ?', whereArgs: [sid]);
      return rows.isEmpty ? null : rows.single;
    }

    var s = await row();
    if (s == null) {
      await PluggyInbox.instance?.sync();
      s = await row();
    }
    if (s == null) throw StateError('Sugestão não encontrada neste aparelho.');
    final txId = 'notification:$sid';
    if (s['status'] == 'confirmed') {
      return {
        'transaction_id': s['transaction_id'] ?? txId,
        'message': 'Já estava confirmada.'
      };
    }
    if (s['status'] != 'pending') {
      throw StateError('A sugestão já foi ignorada ou expirou.');
    }
    final type = a['type'] as String? ??
        (s['kind'] == 'refund' ? 'income' : s['kind'] as String);
    if (type != 'expense' && type != 'income') {
      throw StateError(
          'Esta sugestão parece uma transferência; registre com add_transfer e ignore a sugestão.');
    }
    final account = _account(a['account_id']);
    _category(a['category_id']);
    await app.addTransaction(
        AppTransaction(
            id: txId,
            type: type,
            amount: (s['amount_cents'] as int) / 100,
            description:
                a['description'] as String? ?? s['description'] as String,
            accountId: account.id,
            categoryId: a['category_id'] as String,
            date: DateTime.fromMillisecondsSinceEpoch(s['occurred_at'] as int),
            currency: account.currency,
            note: s['kind'] == 'refund' ? 'Estorno / reembolso revisado' : ''),
        metadata: TransactionMetadata(
            transactionId: txId,
            source: s['kind'] == 'refund' && type == 'income'
                ? 'notification_refund'
                : 'notification'),
        suggestionId: sid);
    unawaited(PluggyInbox.instance?.sync());
    return {
      'transaction_id': txId,
      'message': 'Sugestão confirmada e lançada.'
    };
  }
}
