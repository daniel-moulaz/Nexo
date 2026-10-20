import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'sync_lab_check.dart';
import 'sync_protocol.dart';

class SyncAuthenticationRequired implements Exception {
  const SyncAuthenticationRequired();
  @override
  String toString() => 'SyncAuthenticationRequired';
}

/// The server revoked this installation. Signing in again must not silently
/// re-register it; the device needs a new epoch/bootstrap decision.
class SyncDeviceRevoked implements Exception {
  const SyncDeviceRevoked();
  @override
  String toString() => 'SyncDeviceRevoked';
}

// Closed list of codes raised by the lab RPCs. Anything else is reported by
// HTTP status only, so server text never reaches logs or the interface.
const _serverCodes = {
  'synthetic_lab_required',
  'invalid_payload_hash',
  'invalid_operation_header',
  'invalid_edits',
  'invalid_edit_count',
  'invalid_edit',
  'delete_missing_entity',
  'duplicate_entity',
  'epoch_mismatch',
  'operation_id_reused',
  'invalid_page',
  'epoch_or_cursor_mismatch',
  'dataset_unavailable',
  'invalid_effects',
  'invalid_effect',
  'invalid_requires',
  'invalid_requirement',
  'duplicate_effect',
};

/// Authenticated transport for the isolated synthetic Supabase lab.
/// No app startup integration, login flow, token persistence or real-data opt-in.
/// The session supplier must return a current user access token, never an admin
/// key. Each request owns its client so timeout can close outstanding sockets.
class SupabaseSyncTransport implements SyncLabTransport {
  SupabaseSyncTransport({
    required this.projectUrl,
    required this.publishableKey,
    required this.deviceId,
    required this.accessToken,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 20),
  }) : _clientFactory = clientFactory ?? http.Client.new {
    requireSync(
        projectUrl.scheme == 'https' &&
            projectUrl.host.isNotEmpty &&
            projectUrl.userInfo.isEmpty &&
            !projectUrl.hasQuery &&
            !projectUrl.hasFragment &&
            (projectUrl.path.isEmpty || projectUrl.path == '/'),
        'invalid_project_url');
    requireSync(
        publishableKey.startsWith('sb_publishable_') &&
            !publishableKey.contains(RegExp(r'\s')),
        'publishable_key_required');
    SyncKey(deviceId, deviceId).validate();
    requireSync(timeout > Duration.zero, 'invalid_timeout');
  }

  final Uri projectUrl;
  final String publishableKey;
  final String deviceId;
  final Future<String?> Function() accessToken;
  final Duration timeout;
  final http.Client Function() _clientFactory;
  static const _maxResponseBytes = 8 * 1024 * 1024;
  // One operation can occupy 1 MiB, escaping its JSON in a receipt adds bytes.
  // Keep pages bounded until realistic domain payloads have been profiled.
  static const _pageOperations = 3;

  void _requireUserSession(String? token) {
    if (token == null || token.contains(RegExp(r'\s'))) {
      throw const SyncAuthenticationRequired();
    }
    try {
      final parts = token.split('.');
      if (parts.length != 3) throw const FormatException();
      final claims = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      // This is an accidental-admin-key guard, NOT local JWT verification.
      // Supabase validates the signature, expiry and authenticated identity.
      if (claims['role'] != 'authenticated' ||
          claims['sub'] is! String ||
          (claims['sub'] as String).isEmpty) {
        throw const FormatException();
      }
    } catch (_) {
      throw const SyncAuthenticationRequired();
    }
  }

  Future<Object?> _rpc(String name, Map<String, dynamic> parameters) async {
    final token = await accessToken();
    _requireUserSession(token);
    final request = http.Request(
        'POST', projectUrl.resolve('/rest/v1/rpc/nexo_sync_lab_$name'))
      ..followRedirects = false
      ..headers.addAll({
        'apikey': publishableKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      })
      ..body = jsonEncode(parameters);
    final client = _clientFactory();
    try {
      return await _send(client, request).timeout(timeout);
    } on TimeoutException {
      throw const SyncUnavailable();
    } on http.ClientException {
      throw const SyncUnavailable();
    } finally {
      client.close();
    }
  }

  Future<Object?> _send(http.Client client, http.Request request) async {
    final response = await client.send(request);
    final status = response.statusCode;
    if (status == 429 || status >= 500) throw const SyncUnavailable();
    final ok = status == 200 || status == 204;
    // Error bodies are small; never buffer an unbounded one to classify it.
    final limit = ok ? _maxResponseBytes : _maxErrorBytes;
    if ((response.contentLength ?? 0) > limit) {
      if (!ok) throw _failure(status, null);
      throw const SyncProtocolException('response_too_big');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > limit) {
        if (!ok) throw _failure(status, null);
        throw const SyncProtocolException('response_too_big');
      }
      bytes.add(chunk);
    }
    if (!ok) throw _failure(status, _errorCode(bytes.takeBytes()));
    final body = bytes.takeBytes();
    // Functions returning void answer 204 or an empty 200 body.
    if (status == 204 || body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(body));
    } catch (_) {
      throw const SyncProtocolException('invalid_server_response');
    }
  }

  static const _maxErrorBytes = 16 * 1024;

  static String? _errorCode(Uint8List body) {
    try {
      final message = (jsonDecode(utf8.decode(body)) as Map)['message'];
      return message is String ? message : null;
    } catch (_) {
      return null;
    }
  }

  static Exception _failure(int status, String? code) {
    if (code == 'device_unavailable') return const SyncDeviceRevoked();
    if (code != null && _serverCodes.contains(code)) {
      return SyncProtocolException(code);
    }
    // Expired/invalid JWT (PostgREST) and `authentication_required` land here.
    if (status == 401 || status == 403) {
      return const SyncAuthenticationRequired();
    }
    // Redirects are never followed: credentials stay with the project host.
    return SyncProtocolException('backend_http_$status');
  }

  Future<void> createSyntheticDataset(String datasetId, String epoch) async {
    final result = await _rpc('create', {
      'p_dataset_id': datasetId,
      'p_epoch': epoch,
      'p_device_id': deviceId,
      'p_synthetic_only': true,
    });
    requireSync(
        result is Map &&
            result['protocol'] == 1 &&
            result['dataset_id'] == datasetId &&
            result['epoch'] == epoch &&
            result['synthetic_only'] == true,
        'invalid_dataset_response');
  }

  /// Synthetic lab only: revokes [device] in a dataset owned by the user.
  Future<void> revokeDevice(String datasetId, String device) async {
    await _rpc(
        'revoke_device', {'p_dataset_id': datasetId, 'p_device_id': device});
  }

  Future<SyncReceipt> _receipt(Object? data) async {
    try {
      final json = data as Map;
      requireSync(json['status'] == 'accepted', 'invalid_receipt_status');
      final receipt = SyncReceipt(
          json['revision'] as int,
          SyncOperation.decode(json['payload'] as String),
          json['hash'] as String);
      await receipt.validate();
      return receipt;
    } on SyncProtocolException {
      rethrow;
    } catch (_) {
      throw const SyncProtocolException('invalid_server_response');
    }
  }

  @override
  Future<SyncPushResult> push(SyncOperation operation) async {
    requireSync(operation.deviceId == deviceId, 'wrong_local_device');
    final hash = await operation.digest();
    final result = await _rpc('push', {
      'p_payload': operation.encode(),
      'p_hash': hash,
    });
    requireSync(result is Map, 'invalid_server_response');
    final json = result as Map;
    if (json['status'] == 'conflict') {
      try {
        final remote = (json['remote'] as List)
            .map((e) => SyncRemoteState(
                  SyncKey(e['kind'] as String, e['id'] as String),
                  e['revision'] as int,
                  (e['value'] as Map?)?.cast<String, dynamic>(),
                ))
            .toList();
        requireSync(
            remote.length == operation.checkedKeys.length &&
                remote
                    .map((r) => r.key)
                    .toSet()
                    .containsAll(operation.checkedKeys),
            'incomplete_remote_alternative');
        return SyncRejected(remote);
      } on SyncProtocolException {
        rethrow;
      } catch (_) {
        throw const SyncProtocolException('invalid_server_response');
      }
    }
    final receipt = await _receipt(json);
    requireSync(receipt.hash == hash && receipt.operation.id == operation.id,
        'receipt_mismatch');
    return SyncAccepted(receipt);
  }

  @override
  Future<List<SyncReceipt>> pull({
    required String datasetId,
    required String epoch,
    required int after,
    required int limit,
  }) async {
    requireSync(after >= 0 && limit > 0 && limit <= 100, 'invalid_page');
    final pageLimit = min(limit, _pageOperations);
    final result = await _rpc('pull', {
      'p_dataset_id': datasetId,
      'p_epoch': epoch,
      'p_device_id': deviceId,
      'p_after': after,
      'p_limit': pageLimit,
    });
    requireSync(result is List && result.length <= pageLimit, 'invalid_page');
    final receipts = <SyncReceipt>[];
    for (final item in result as List) {
      final receipt = await _receipt(item);
      requireSync(
          receipt.operation.datasetId == datasetId &&
              receipt.operation.epoch == epoch,
          'wrong_dataset_or_epoch');
      requireSync(
          receipt.revision == after + receipts.length + 1, 'cursor_gap');
      receipts.add(receipt);
    }
    return receipts;
  }
}
