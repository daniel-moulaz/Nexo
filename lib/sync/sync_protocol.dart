import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Experimental protocol. No app startup, network client or live DB uses it.
/// Values are opaque domain aggregates; a production adapter must validate
/// accounting invariants before staging or applying them.
const syncProtocolVersion = 1;

class SyncProtocolException implements Exception {
  const SyncProtocolException(this.code);
  final String code;
  @override
  String toString() => 'SyncProtocolException($code)';
}

void requireSync(bool condition, String code) {
  if (!condition) throw SyncProtocolException(code);
}

void _identifier(String value) =>
    requireSync(value.isNotEmpty && value.length <= 256, 'invalid_identifier');

Object? _canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  requireSync(
      value == null ||
          value is String ||
          value is bool ||
          (value is num && value.isFinite),
      'invalid_json');
  return value;
}

String canonicalSyncJson(Object? value) => jsonEncode(_canonical(value));

class SyncKey {
  const SyncKey(this.kind, this.id);
  final String kind;
  final String id;
  void validate() {
    _identifier(kind);
    _identifier(id);
  }

  Map<String, dynamic> toJson() => {'kind': kind, 'id': id};
  @override
  bool operator ==(Object other) =>
      other is SyncKey && other.kind == kind && other.id == id;
  @override
  int get hashCode => Object.hash(kind, id);
}

class SyncEdit {
  SyncEdit(this.key, this.baseRevision, Map<String, dynamic>? value)
      : _json = value == null ? null : canonicalSyncJson(value) {
    key.validate();
    requireSync(baseRevision >= 0, 'invalid_revision');
    requireSync(value != null || baseRevision > 0, 'delete_missing_entity');
  }

  final SyncKey key;
  final int baseRevision;
  final String? _json;
  // Defensive decode: callers cannot change an operation after hashing it.
  Map<String, dynamic>? get value =>
      _json == null ? null : jsonDecode(_json) as Map<String, dynamic>;
  bool get deleted => _json == null;
  Map<String, dynamic> toJson() => {
        ...key.toJson(),
        'base_revision': baseRevision,
        'value': value,
      };
  factory SyncEdit.fromJson(Map<String, dynamic> json) => SyncEdit(
      SyncKey(json['kind'] as String, json['id'] as String),
      json['base_revision'] as int,
      (json['value'] as Map?)?.cast<String, dynamic>());
}

class SyncOperation {
  SyncOperation({
    required this.id,
    required this.datasetId,
    required this.epoch,
    required this.deviceId,
    required DateTime createdAt,
    required List<SyncEdit> edits,
  })  : createdAt = createdAt.toUtc(),
        edits = List.unmodifiable(edits) {
    for (final identifier in [id, datasetId, epoch, deviceId]) {
      _identifier(identifier);
    }
    requireSync(edits.isNotEmpty && edits.length <= 10000, 'invalid_batch');
    requireSync(edits.map((e) => e.key).toSet().length == edits.length,
        'duplicate_entity_in_operation');
    requireSync(
        utf8.encode(encode()).length <= 1024 * 1024, 'operation_too_big');
  }

  final String id;
  final String datasetId;
  final String epoch;
  final String deviceId;
  final DateTime createdAt;
  final List<SyncEdit> edits;
  Map<String, dynamic> toJson() => {
        'protocol': syncProtocolVersion,
        'id': id,
        'dataset_id': datasetId,
        'epoch': epoch,
        'device_id': deviceId,
        'created_at': createdAt.toIso8601String(),
        'edits': edits.map((e) => e.toJson()).toList(),
      };
  String encode() => canonicalSyncJson(toJson());
  Future<String> digest() async => (await Sha256().hash(utf8.encode(encode())))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  factory SyncOperation.decode(String encoded) {
    requireSync(
        utf8.encode(encoded).length <= 1024 * 1024, 'operation_too_big');
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    requireSync(
        json['protocol'] == syncProtocolVersion, 'unsupported_protocol');
    return SyncOperation(
      id: json['id'] as String,
      datasetId: json['dataset_id'] as String,
      epoch: json['epoch'] as String,
      deviceId: json['device_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      edits: (json['edits'] as List)
          .map((e) => SyncEdit.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class SyncReceipt {
  SyncReceipt(this.revision, this.operation, this.hash) {
    requireSync(revision > 0, 'invalid_cursor');
  }
  final int revision;
  final SyncOperation operation;
  final String hash;
  Future<void> validate() async =>
      requireSync(hash == await operation.digest(), 'payload_hash_mismatch');
  Map<String, dynamic> toJson() => {
        'revision': revision,
        'operation': operation.toJson(),
        'hash': hash,
      };
}

sealed class SyncPushResult {}

class SyncAccepted extends SyncPushResult {
  SyncAccepted(this.receipt);
  final SyncReceipt receipt;
}

class SyncRejected extends SyncPushResult {
  SyncRejected(this.remote);
  // Complete remote alternatives for the rejected aggregate, including null
  // for absent entities. The prototype never chooses a winning alternative.
  final List<SyncRemoteState> remote;
}

class SyncRemoteState {
  SyncRemoteState(this.key, this.revision, Map<String, dynamic>? value)
      : _json = value == null ? null : canonicalSyncJson(value) {
    key.validate();
    requireSync(revision >= 0, 'invalid_revision');
    requireSync(revision > 0 || value == null, 'invalid_remote_absence');
  }
  final SyncKey key;
  final int revision;
  final String? _json;
  Map<String, dynamic>? get value =>
      _json == null ? null : jsonDecode(_json) as Map<String, dynamic>;
  Map<String, dynamic> toJson() => {
        ...key.toJson(),
        'revision': revision,
        'value': value,
      };
}

class SyncUnavailable implements Exception {
  const SyncUnavailable();
}

abstract interface class SyncTransport {
  Future<SyncPushResult> push(SyncOperation operation);
  Future<List<SyncReceipt>> pull({
    required String datasetId,
    required String epoch,
    required int after,
    required int limit,
  });
}
