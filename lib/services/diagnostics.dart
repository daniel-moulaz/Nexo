import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where failures that used to vanish in `catch (_)` leave a trace: one line
/// per area with a count, the last time and a message with every number
/// taken out, so no amount, id or token is kept. Shown in Ajuda › Diagnóstico.
class DiagnosticEntry {
  const DiagnosticEntry(
      {required this.area,
      required this.count,
      required this.last,
      required this.message});
  final String area;
  final int count;
  final DateTime last;
  final String message;

  Map<String, dynamic> toJson() => {
        'area': area,
        'count': count,
        'last': last.toIso8601String(),
        'message': message,
      };
  static DiagnosticEntry fromJson(Map<String, dynamic> j) => DiagnosticEntry(
      area: j['area'] as String,
      count: (j['count'] as num).toInt(),
      last: DateTime.tryParse(j['last'] as String? ?? '') ?? DateTime(2000),
      message: j['message'] as String? ?? '');
}

abstract final class Diagnostics {
  static const _key = 'nexo_diagnostics';
  static const _limit = 40;
  static final Map<String, DiagnosticEntry> _byArea = {};
  static Future<void>? _loading;

  /// Bumps whenever an entry changes; screens listen to redraw.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<DiagnosticEntry> get entries =>
      _byArea.values.toList()..sort((a, b) => b.last.compareTo(a.last));

  static int get total => _byArea.values.fold(0, (s, e) => s + e.count);

  /// Records a failure in [area] ("sync", "open finance", "backup"…).
  /// Never throws, never keeps numbers, never blocks the caller.
  static void note(String area, Object error, {DateTime? now}) {
    unawaited(_record(area, scrub(error.toString()), now ?? DateTime.now()));
  }

  static Future<void> _record(String area, String message, DateTime at) async {
    try {
      await load();
      final previous = _byArea[area];
      _byArea[area] = DiagnosticEntry(
          area: area,
          count: (previous?.count ?? 0) + 1,
          last: at,
          message: message);
      while (_byArea.length > _limit) {
        _byArea.remove(entries.last.area);
      }
      revision.value++;
      await (await SharedPreferences.getInstance())
          .setString(_key, jsonEncode([for (final e in entries) e.toJson()]));
    } catch (_) {
      // Diagnostics must never be the thing that fails.
    }
  }

  /// Numbers, long tokens and paths out; the shape of the error stays.
  static String scrub(String text) {
    var s = text.replaceAll(RegExp(r'[A-Za-z]:\\[^\s]+'), '<caminho>');
    s = s.replaceAll(RegExp(r'[A-Za-z0-9_\-]{24,}'), '<token>');
    s = s.replaceAll(RegExp(r'\d[\d.,:/-]*'), '#');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      for (final j in (jsonDecode(raw) as List).whereType<Map>()) {
        final e = DiagnosticEntry.fromJson(Map<String, dynamic>.from(j));
        _byArea.putIfAbsent(e.area, () => e);
      }
      revision.value++;
    } catch (_) {
      // A corrupt record is dropped, not surfaced.
    }
  }

  static Future<void> clear() async {
    _byArea.clear();
    revision.value++;
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() {
    _byArea.clear();
    _loading = null;
    revision.value++;
  }
}
