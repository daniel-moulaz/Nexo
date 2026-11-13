import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/screens/claude_queue_screen.dart';
import 'package:nexo/sync/assistant_commands.dart';
import 'package:nexo/sync/claude_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a check survives the trip through preferences, with its source',
      () async {
    final at = DateTime(2026, 11, 13, 13, 20);
    await ClaudeQueue.record(QueueCheck(at: at, source: 'push', applied: 2));
    await ClaudeQueue.record(QueueCheck(
        at: at.add(const Duration(minutes: 15)), source: 'periodic'));
    final last = await ClaudeQueue.last();
    expect(last!.source, 'periodic');
    expect(last.sourceLabel, 'checagem a cada 15 min');
    expect(last.applied, 0);
    // The last one that recorded something is kept apart.
    final applied = await ClaudeQueue.lastApplied();
    expect(applied!.at, at);
    expect(applied.applied, 2);
    expect(applied.sourceLabel, 'aviso do servidor');
    expect(QueueCheck.fromJson({'source': 'app'}), isNull,
        reason: 'no time, no check');
  });

  test('on by default; the switch is remembered', () async {
    expect(await ClaudeQueue.enabled(), isTrue);
    expect(await ClaudeQueue.notifies(), isTrue);
    await ClaudeQueue.setNotifies(false);
    expect(await ClaudeQueue.notifies(), isFalse);
  });

  test('the server status reads devices and the waiting reasons', () {
    final s = QueueStatus.fromJson({
      'pending': 2,
      'waiting_for_update': 1,
      'oldest_pending_at': '2026-11-13T15:00:00Z',
      'devices': [
        {
          'device_id': 'a',
          'app_version': '1.17.0+59',
          'seen_at': '2026-11-13T15:00:00Z',
          'checked_at': '2026-11-13T15:10:00Z',
          'push': true
        },
        {'device_id': 'b', 'app_version': '1.15.1+57'}
      ]
    });
    expect([s.pending, s.waitingForUpdate], [2, 1]);
    expect(s.devices.first.push, isTrue);
    expect(s.devices.first.lastContact,
        DateTime.utc(2026, 11, 13, 15, 10).toLocal());
    expect(s.devices.last.lastContact, isNull);
  });

  group('push registration', () {
    final calls = <String>[];
    var token = 'token-aaaaaaaaaaaaaaaaaaaaaa';
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ClaudeQueue.channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'pushConfigured' => true,
          'pushToken' => token,
          _ => null,
        };
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ClaudeQueue.channel, null));

    test('sent once per token and device; a new token, again; off removes it',
        () async {
      if (!ClaudeQueue.supported) {
        // Android only; on the test host the call does nothing.
        expect(
            await ClaudeQueue.registerPush('d', 'dev', (_) async {}), isFalse);
        return;
      }
      final sent = <String?>[];
      Future<void> register(String? t) async => sent.add(t);
      expect(await ClaudeQueue.registerPush('d', 'dev', register), isTrue);
      expect(await ClaudeQueue.registerPush('d', 'dev', register), isTrue);
      expect(sent, [token]);
      token = 'token-bbbbbbbbbbbbbbbbbbbbbb';
      await ClaudeQueue.registerPush('d', 'dev', register);
      expect(sent.last, token);
      await ClaudeQueue.setEnabled(false);
      expect(await ClaudeQueue.registerPush('d', 'dev', register), isFalse);
      expect(sent.last, isNull);
    });
  });

  Widget screen(QueueStatus? status, {bool android = true}) => MaterialApp(
      home: ClaudeQueueScreen(
          key: UniqueKey(),
          load: () async => status,
          thisDevice: 'a',
          checkNow: () async {},
          android: android));

  testWidgets('empty queue: says so, with this device and the switches',
      (tester) async {
    await ClaudeQueue.record(QueueCheck(
        at: DateTime.now().subtract(const Duration(minutes: 3)),
        source: 'periodic'));
    await tester.pumpWidget(
        screen(QueueStatus(pending: 0, waitingForUpdate: 0, devices: [
      QueueDevice(
          id: 'a',
          version: '1.17.0+59',
          checkedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          push: true),
      const QueueDevice(id: 'b', version: '1.17.0+59'),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum pedido esperando'), findsOneWidget);
    expect(find.text('Última conferência: há 3 min'), findsOneWidget);
    expect(find.textContaining('checagem a cada 15 min'), findsOneWidget);
    expect(find.text('Este aparelho · 1.17.0+59'), findsOneWidget);
    expect(find.text('Outro aparelho · 1.17.0+59'), findsOneWidget);
    expect(
        find.textContaining('acorda com o aviso do servidor'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Avisar quando gravar'), 200);
    expect(find.text('Gravar pedidos com o app fechado'), findsOneWidget);
  });

  testWidgets('a request waiting for an update is not called a delay',
      (tester) async {
    await tester
        .pumpWidget(screen(const QueueStatus(pending: 1, waitingForUpdate: 1)));
    await tester.pumpAndSettle();
    expect(find.text('1 pedido esperando atualização'), findsOneWidget);
    expect(find.textContaining('não é gravado errado'), findsOneWidget);
  });

  testWidgets('pending requests and an older server', (tester) async {
    await tester.pumpWidget(screen(QueueStatus(
        pending: 2,
        waitingForUpdate: 0,
        oldestPendingAt:
            DateTime.now().subtract(const Duration(minutes: 12)))));
    await tester.pumpAndSettle();
    expect(find.text('2 pedidos na fila'), findsOneWidget);
    expect(find.text('Esperando há 12 min.'), findsOneWidget);

    await tester.pumpWidget(screen(null, android: false));
    await tester.pumpAndSettle();
    expect(find.text('Fila no servidor indisponível'), findsOneWidget);
    expect(find.text('Gravar pedidos com o app fechado'), findsNothing,
        reason: 'no phone switches off Android');
  });

  test('the platform channel name matches the native side', () {
    expect(ClaudeQueue.channel, const MethodChannel('nexo/background'));
  });
}
