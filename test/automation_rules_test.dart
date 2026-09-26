import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:expensy/services/nexo_security.dart';
import 'package:expensy/services/financial_reminders.dart';
import 'package:expensy/services/cash_forecast.dart';

class TestDeviceAuth extends LocalAuthentication {
  final bool approved;
  TestDeviceAuth(this.approved);
  @override
  Future<bool> authenticate(
          {required String localizedReason,
          Iterable<dynamic> authMessages = const [],
          bool biometricOnly = false,
          bool sensitiveTransaction = true,
          bool persistAcrossBackgrounding = false}) async =>
      approved;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Unreadable protection fails closed and recovery requires device authentication',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues(
        {'nexo_security_v1': 'invalid-json'});
    final denied = NexoSecurity(auth: TestDeviceAuth(false));
    await denied.load();
    expect(denied.storageError, true);
    expect(denied.locked, true);
    expect(await denied.recoverStorage(), false);
    expect(await const FlutterSecureStorage().read(key: 'nexo_security_v1'),
        'invalid-json');
    final allowed = NexoSecurity(auth: TestDeviceAuth(true));
    await allowed.load();
    expect(await allowed.recoverStorage(), true);
    expect(allowed.storageError, false);
    expect(allowed.locked, false);
    expect(allowed.enabled, false);
  });
  test('Future reminders cancel when resolved and include unpaid cards only',
      () {
    final now = DateTime(2026, 9, 1, 8);
    final prefs = {
      ...FinancialReminders.defaults,
      'bills': true,
      'invoice': true,
      'income': true
    };
    final events = [
      ForecastEvent(
          date: DateTime(2026, 9, 5),
          title: 'private',
          accountId: 'a',
          kind: 'transaction',
          id: 'bill',
          currency: 'BRL',
          amount: -100),
      ForecastEvent(
          date: DateTime(2026, 9, 8),
          title: 'card',
          accountId: 'c',
          kind: 'invoice',
          id: 'c',
          currency: 'BRL',
          amount: -200)
    ];
    final plans =
        ReminderPlanner.build(CashForecast(1000, 700, events, []), prefs, now);
    expect(plans, hasLength(6));
    expect(plans.every((p) => p.at.isAfter(now)), true);
    expect(plans.map((p) => p.id).toSet(), hasLength(6));
    expect(plans.map((p) => p.body).join(), isNot(contains('100')));
    expect(
        ReminderPlanner.build(
            const CashForecast(1000, 1000, [], []), prefs, now),
        isEmpty);
    expect(
        ReminderPlanner.build(CashForecast(1000, 700, events, []),
            FinancialReminders.defaults, now),
        isEmpty);
  });
  test(
      'Recurring follow-up and negative forecast are opt-in and stable per date',
      () {
    final now = DateTime(2026, 9, 5, 12);
    final f = CashForecast(100, -100, [
      ForecastEvent(
          date: DateTime(2026, 9, 3),
          title: 'r',
          accountId: 'a',
          kind: 'recurring',
          id: 'r',
          currency: 'BRL',
          amount: -200)
    ], []);
    final prefs = {
      ...FinancialReminders.defaults,
      'recurring': true,
      'forecast': true
    };
    final first = ReminderPlanner.build(f, prefs, now);
    final second =
        ReminderPlanner.build(f, prefs, now.add(const Duration(hours: 1)));
    expect(first, hasLength(2));
    expect(first.map((p) => p.id), second.map((p) => p.id));
  });
  test('Recurring today remains available for its custom reminder time', () {
    final now = DateTime(2026, 9, 5, 12);
    final forecast = CashForecast(100, 50, [
      ForecastEvent(date: DateTime(2026, 9, 5), title: 'r', accountId: 'a',
          kind: 'recurring', id: 'r', currency: 'BRL', amount: -50)
    ], []);
    final plans = ReminderPlanner.build(forecast,
        {...FinancialReminders.defaults, 'recurring': true}, now);
    expect(plans, hasLength(1));
    // The scheduler substitutes the registered time before checking it is future.
    expect(plans.single.key, startsWith('recurring:r:'));
  });
  test('Autolock boundaries and PIN format', () {
    for (final seconds in [0, 30, 60, 300]) {
      expect(PinVerifier.timeoutReached(Duration(seconds: seconds), seconds),
          true);
      if (seconds > 0)
        expect(
            PinVerifier.timeoutReached(Duration(seconds: seconds - 1), seconds),
            false);
    }
    expect(PinVerifier.valid('123456'), true);
    for (final pin in ['12345', '1234567', '12a456', '']) {
      expect(PinVerifier.valid(pin), false);
    }
    expect(PinVerifier.equal('abc', 'abd'), false);
  });
  test('PIN is salted and hashed, persists securely and locks on restart',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({});
    final security = NexoSecurity();
    await security.load();
    expect(security.locked, false);
    await security.setPin('193746');
    final raw =
        await const FlutterSecureStorage().read(key: 'nexo_security_v1');
    expect(raw, isNot(contains('193746')));
    expect(jsonDecode(raw!)['salt'], isNotEmpty);
    final restart = NexoSecurity();
    await restart.load();
    expect(restart.locked, true);
    expect(await restart.verify('193745'), false);
    expect(restart.locked, true);
    expect(await restart.verify('193746'), true);
    expect(restart.locked, false);
    await restart.configure(timeout: 0, recents: true, capture: false);
    restart.background();
    restart.resume();
    expect(restart.locked, true);
    expect(restart.hideRecents, true);
    expect(restart.blockCapture, false);
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('PIN cooldown persists and cannot be bypassed by restarting', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({
      'nexo_security_v1': jsonEncode({
        'enabled': true,
        'retryAt': DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch
      })
    });
    final security = NexoSecurity();
    await security.load();
    expect(security.locked, true);
    expect(security.retrySeconds, greaterThan(0));
    expect(await security.verify('123456'), false);
    expect(security.locked, true);
  });
}
