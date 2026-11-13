import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/services/desktop_profile.dart';
import 'package:nexo/services/desktop_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    DesktopProfile.isTest = false;
    DesktopProfile.testTray = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nexo/window'),
            (call) async {
      calls.add(call);
      return call.method == 'startsWithWindows' ? false : true;
    });
  });
  tearDown(() {
    DesktopProfile.isTest = false;
    debugDefaultTargetPlatformOverride = null;
  });

  test('stays in the tray by default, and the choice is remembered', () async {
    await DesktopWindow.start();
    expect(calls.first.arguments, true);
    await DesktopWindow.setKeepInTray(false);
    calls.clear();
    await DesktopWindow.start();
    expect(calls.single.arguments, false);
  });

  test('starts with Windows once, with the tray on; a later choice stays',
      () async {
    await DesktopWindow.start();
    expect(calls.map((c) => c.method),
        ['setKeepInTray', 'startsWithWindows', 'setStartWithWindows']);
    expect(calls.last.arguments, true);
    // The person turned it off afterwards: never turned on again.
    calls.clear();
    await DesktopWindow.start();
    expect(calls.map((c) => c.method), ['setKeepInTray']);
  });

  test('a test profile closes normally unless asked', () async {
    DesktopProfile.isTest = true;
    await DesktopWindow.start();
    expect(calls.single.arguments, false);
    DesktopProfile.testTray = true;
    calls.clear();
    await DesktopWindow.start();
    expect(calls.single.arguments, true);
  });

  test('nothing is called off Windows', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await DesktopWindow.start();
    expect(calls, isEmpty);
  });
}
