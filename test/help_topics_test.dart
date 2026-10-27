import 'package:expensy/screens/help_screen.dart';
import 'package:expensy/services/help_topics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search looks in the whole answer, every word must match', () {
    expect(searchHelp(''), helpTopics);
    final fatura = searchHelp('fatura fechamento');
    expect(fatura, isNotEmpty);
    expect(
        fatura.every((t) =>
            t.answer.toLowerCase().contains('fechamento') ||
            t.question.toLowerCase().contains('fechamento')),
        isTrue);
    expect(searchHelp('neutro').map((t) => t.question),
        contains('O que é o ajuste de saldo neutro?'));
    expect(searchHelp('xyzzy'), isEmpty);
  });

  testWidgets('the help screen filters as the person types', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    expect(find.text('Como o Nexo conta'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'pontual');
    await tester.pumpAndSettle();
    expect(find.text('O que é um gasto pontual?'), findsOneWidget);
    expect(find.text('Como atualizar o app?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
