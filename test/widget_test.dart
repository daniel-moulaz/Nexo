// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:expensy/main.dart';
import 'package:provider/provider.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build and trigger a frame.
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AppProvider(), child: const ExpensyApp()));
    expect(find.byType(ExpensyApp), findsOneWidget);
  });
}
