import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/services/diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Diagnostics.reset();
  });

  test('messages lose numbers, tokens and paths', () {
    expect(Diagnostics.scrub('HTTP 503 after 1.250,00 at 10:22'),
        'HTTP # after # at #');
    expect(Diagnostics.scrub('token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 bad'),
        'token <token> bad');
    expect(Diagnostics.scrub(r'cannot open C:\Users\x\nexo.db'),
        'cannot open <caminho>');
    expect(Diagnostics.scrub('palavra ' * 60).length, 161);
  });

  test('counts per area, newest first, and survives a reload', () async {
    final t0 = DateTime(2026, 10, 28, 9);
    Diagnostics.note('sync', 'timeout 30s', now: t0);
    Diagnostics.note('sync', 'timeout 31s',
        now: t0.add(const Duration(minutes: 1)));
    Diagnostics.note('backup', StateError('disk full 2 GB'),
        now: t0.add(const Duration(minutes: 2)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(Diagnostics.total, 3);
    expect(Diagnostics.entries.first.area, 'backup');
    expect(Diagnostics.entries.first.message, 'Bad state: disk full # GB');
    expect(Diagnostics.entries.last.count, 2);
    expect(Diagnostics.entries.last.message, 'timeout #s');

    // A new process reads what was persisted.
    Diagnostics.reset();
    await Diagnostics.load();
    expect(Diagnostics.total, 3);
    expect(Diagnostics.entries.map((e) => e.area), ['backup', 'sync']);

    await Diagnostics.clear();
    expect(Diagnostics.entries, isEmpty);
    Diagnostics.reset();
    await Diagnostics.load();
    expect(Diagnostics.entries, isEmpty);
  });

  test('never throws on a broken store', () async {
    SharedPreferences.setMockInitialValues({'nexo_diagnostics': 'not json'});
    Diagnostics.reset();
    await Diagnostics.load();
    expect(Diagnostics.entries, isEmpty);
    Diagnostics.note('x', 'y');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(Diagnostics.total, 1);
  });
}
