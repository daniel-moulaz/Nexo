import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/services/agenda_ics.dart';
import 'package:nexo/services/cash_forecast.dart';

void main() {
  test('one all-day event per commitment, amounts in the title, text escaped',
      () {
    final ics = AgendaIcs.build([
      ForecastEvent(
          date: DateTime(2026, 11, 5),
          title: 'Aluguel; apto, centro',
          accountId: 'main',
          kind: 'recurring',
          id: 'recurring:rent:2026-11-05',
          currency: 'BRL',
          amount: -1650),
      ForecastEvent(
          date: DateTime(2026, 11, 7),
          title: 'Salário',
          accountId: 'main',
          kind: 'recurring',
          id: 'recurring:salary:2026-11-07',
          currency: 'BRL',
          amount: 6200),
      ForecastEvent(
          date: DateTime(2026, 11, 9),
          title: 'Aviso sem valor',
          accountId: 'main',
          kind: 'info',
          id: 'info',
          currency: 'BRL',
          amount: 0),
    ],
        money: (v, c) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}',
        accountName: (_) => 'Conta principal',
        now: DateTime.utc(2026, 10, 28, 12));
    expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2, reason: 'info events out');
    expect(ics, contains('DTSTART;VALUE=DATE:20261105\r\n'));
    expect(ics, contains('DTEND;VALUE=DATE:20261106\r\n'));
    expect(ics, contains(r'SUMMARY:Aluguel\; apto\, centro (−R$ 1650,00)'));
    expect(ics, contains(r'SUMMARY:Salário (+R$ 6200,00)'));
    expect(ics, contains('DESCRIPTION:Conta recorrente\\nConta principal'));
    expect(ics, contains('DTSTAMP:20261028T120000Z'));
    expect(ics,
        contains('UID:nexo-recurring:rent:2026-11-05-20261105@nexo.local'));
  });
}
