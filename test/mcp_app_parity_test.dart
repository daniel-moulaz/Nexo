import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/sync/app_actions.dart';
import 'package:nexo/sync/assistant_commands.dart';
import 'package:nexo/sync/assistant_settings.dart';

/// Regression guard of "everything the app does, the assistant can do".
/// Reads the source: every ledger operation name the app writes, every
/// setting it stores and every tool the server offers.
void main() {
  final dart = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  final server = Directory('supabase/functions/nexo-mcp')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ts'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  /// Names given to `ledgerTransaction(db, '…')`, `operation('…')` and the
  /// helpers that forward a name to them.
  Set<String> operationNames() {
    final names = <String>{};
    // saveSharedSettings receives the name and passes it to operation().
    final call = RegExp(
        r'ledgerTransaction\(|[^a-zA-Z_]operation\(|saveSharedSettings\(');
    final label = RegExp(r"'([a-z_]+\.[a-z_]+)'");
    for (final f in dart) {
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        var window = src.substring(m.end, (m.end + 220).clamp(0, src.length));
        // Only the arguments before the body.
        for (final stop in ['(txn', '(tx)', '(tx ', 'async', '=>']) {
          final i = window.indexOf(stop);
          if (i >= 0) window = window.substring(0, i);
        }
        names.addAll(label.allMatches(window).map((x) => x.group(1)!));
      }
    }
    return names;
  }

  final tools = RegExp(r'name: "([a-z_]+)"')
      .allMatches(server)
      .map((m) => m.group(1)!)
      .toSet();

  test('every write of the app has an assistant tool or a stated reason', () {
    final written = operationNames();
    expect(written.length, greaterThan(60),
        reason: 'the scan found the app writes');
    final known = {...appWriteActions.keys, ...appInternalWrites.keys};
    final missing = written.difference(known);
    expect(missing, isEmpty,
        reason:
            'New writes without a tool in lib/sync/app_actions.dart: $missing. '
            'Give them an assistant tool (supabase/functions/nexo-mcp) or say why not.');
    expect(known.difference(written), isEmpty,
        reason: 'Entries for writes the app no longer has');
  });

  test('every tool named by the registry exists on the server', () {
    expect(tools.length, greaterThan(90));
    for (final entry in appWriteActions.entries) {
      for (final tool in entry.value) {
        expect(tools, contains(tool), reason: '${entry.key} → $tool');
      }
    }
  });

  test('every setting the app stores is reachable or explained', () {
    final provider = File('lib/providers/app_provider.dart').readAsStringSync();
    final assign = provider
        .split('void _assignSetting(')[1]
        .split(RegExp(r'\n  }\n'))
        .first;
    final keys = RegExp(r"case '([a-zA-Z]+)':")
        .allMatches(assign)
        .map((m) => m.group(1)!)
        .toSet();
    expect(keys, isNotEmpty);
    final reachable = {
      ...assistantSettings.map((s) => s.key),
      ...appInternalSettings.keys
    };
    expect(keys.difference(reachable), isEmpty,
        reason: 'Settings without assistant access');
    expect(reachable.difference(keys), isEmpty,
        reason: 'Registry names a setting the app does not store');
    // The server registry is the same list (also checked on the Node side).
    for (final s in assistantSettings) {
      expect(server, contains('key: "${s.key}"'), reason: s.key);
    }
  });

  test('the app applies exactly the kinds the server can queue', () {
    final queued = RegExp(r'"([a-z]+\.[a-z_]+)"')
        .allMatches(server)
        .map((m) => m.group(1)!)
        .where((k) => !k.endsWith('.ts'))
        .toSet();
    expect(queued, AssistantCommands.supportedKinds.toSet());
  });

  test('the coverage matrix lists every tool', () {
    final doc = File('docs/mcp-paridade.md').readAsStringSync();
    final absent = tools.where((t) => !doc.contains(t)).toList();
    expect(absent, isEmpty, reason: 'Tools missing in docs/mcp-paridade.md');
  });
}
