import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'supabase_auth.dart';
import 'sync_config.dart';

class McpConnector {
  const McpConnector(this.id, this.label, this.lastUsed, this.revoked,
      {this.requests7d, this.lastRequest, this.createdAt, this.datasetId});
  final String id, label;
  final DateTime? lastUsed;
  final bool revoked;

  /// Requests in the last 7 days and the latest one (1.17.0 servers).
  final int? requests7d;
  final DateTime? lastRequest, createdAt;

  /// The dataset this connector reads; null on very old servers.
  final String? datasetId;
}

/// A problem the person can act on.
class McpUnavailable implements Exception {
  const McpUnavailable(this.message);
  final String message;
  @override
  String toString() => 'McpUnavailable';
}

/// Read-only access for an AI assistant (Claude) to the synced dataset.
/// The server stores only a hash of the token; the full address is shown
/// once to the person and never kept by the app.
class McpConnectors {
  McpConnectors(this.config, this.auth, {http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;
  final SyncConfig config;
  final SupabaseAuth auth;
  final http.Client Function() _clientFactory;

  static McpConnectors? instance;

  Future<Object?> _rpc(String name, Map<String, Object?> args) async {
    final token = await auth.accessToken();
    if (token == null) {
      throw const McpUnavailable('Entre na sua conta primeiro.');
    }
    final client = _clientFactory();
    try {
      final response = await client
          .post(config.projectUrl.resolve('/rest/v1/rpc/$name'),
              headers: {
                'apikey': config.publishableKey,
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(args))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200 || response.statusCode == 204) {
        return response.body.isEmpty ? null : jsonDecode(response.body);
      }
      String? code;
      try {
        code = (jsonDecode(response.body) as Map)['message'] as String?;
      } catch (_) {}
      throw McpUnavailable(switch ((response.statusCode, code)) {
        (404, _) => 'A conexão com IA ainda não foi ativada no servidor.',
        (_, 'too_many_connectors') =>
          'Já existem 5 conexões ativas. Desconecte uma antes.',
        (401 || 403, _) => 'Entre novamente na sua conta.',
        _ =>
          'O servidor não respondeu como esperado (HTTP ${response.statusCode}).',
      });
    } on TimeoutException {
      throw const McpUnavailable('Sem resposta do servidor. Tente mais tarde.');
    } on http.ClientException {
      throw const McpUnavailable('Sem conexão com o servidor.');
    } finally {
      client.close();
    }
  }

  /// Creates a connector and returns the address to paste in Claude. It
  /// contains the token: shown once, never stored by the app.
  Future<String> create(String datasetId, String label) async {
    final result = await _rpc('nexo_mcp_create_connector',
        {'p_dataset_id': datasetId, 'p_label': label}) as Map;
    final token = result['token'] as String;
    return config.projectUrl
        .resolve('/functions/v1/nexo-mcp/$token')
        .toString();
  }

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  /// Connectors with their use; an older server gives the plain list.
  Future<List<McpConnector>> list() async {
    Object? rows;
    var detailed = true;
    try {
      rows = await _rpc('nexo_mcp_connector_status', const {});
    } on McpUnavailable {
      detailed = false;
      rows = await _rpc('nexo_mcp_list_connectors', const {});
    }
    return [
      for (final c in (rows as List? ?? const []).cast<Map>())
        McpConnector(c['id'] as String, c['label'] as String,
            _time(c['last_used_at']), c['revoked_at'] != null,
            requests7d: detailed ? (c['requests_7d'] as num?)?.toInt() : null,
            lastRequest: _time(c['last_request_at']),
            createdAt: _time(c['created_at']),
            datasetId: c['dataset_id'] as String?)
    ];
  }

  Future<void> revoke(String id) =>
      _rpc('nexo_mcp_revoke_connector', {'p_id': id});
}
