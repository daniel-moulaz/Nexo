// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:expensy/main.dart';
import 'package:provider/provider.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:expensy/widgets/security_gate.dart';
import 'package:expensy/services/nexo_security.dart';

void main() {
  testWidgets('Lock hides finance content and keeps PIN action above keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    final security = NexoSecurity.instance;
    security.ready = true;
    security.locked = true;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SecurityGate(child: child!),
      home: const Scaffold(body: Text('Dados financeiros privados')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Dados financeiros privados'), findsNothing);
    final action = find.text('Desbloquear com PIN');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(action).dy, lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    security.ready = false;
  });
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build and trigger a frame.
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AppProvider(), child: const ExpensyApp()));
    expect(find.byType(ExpensyApp), findsOneWidget);
  });
}
