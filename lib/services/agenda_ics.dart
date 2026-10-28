import 'cash_forecast.dart';

/// The agenda as an iCalendar file: one all-day event per commitment, with
/// the amount in the title and the account in the description. Opens in
/// Google Calendar, Outlook and the phone's calendar. Nothing here writes
/// to the ledger; it is a view of what is already planned.
abstract final class AgendaIcs {
  static String build(List<ForecastEvent> events,
      {required String Function(double amount, String currency) money,
      required String Function(String accountId) accountName,
      DateTime? now}) {
    final stamp = _utc(now ?? DateTime.now());
    final out = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Nexo//Agenda//PT')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH')
      ..writeln('X-WR-CALNAME:Nexo');
    for (final e in events) {
      if (e.amount == 0 && e.kind == 'info') continue;
      final day = _day(e.date);
      final next = _day(e.date.add(const Duration(days: 1)));
      final sign = e.amount < 0 ? '−' : '+';
      final title = e.amount == 0
          ? e.title
          : '${_escape(e.title)} ($sign${money(e.amount.abs(), e.currency)})';
      out
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:nexo-${_escape(e.id)}-$day@nexo.local')
        ..writeln('DTSTAMP:$stamp')
        ..writeln('DTSTART;VALUE=DATE:$day')
        ..writeln('DTEND;VALUE=DATE:$next')
        ..writeln('SUMMARY:$title')
        ..writeln(
            'DESCRIPTION:${_escape(_kindLabel(e.kind))}\\n${_escape(accountName(e.accountId))}')
        ..writeln('CATEGORIES:Nexo')
        ..writeln('END:VEVENT');
    }
    out.writeln('END:VCALENDAR');
    return out.toString().replaceAll('\n', '\r\n');
  }

  static String _kindLabel(String kind) => switch (kind) {
        'recurring' => 'Conta recorrente',
        'pending' => 'Lançamento pendente',
        'invoice' => 'Fatura do cartão',
        'goal' => 'Objetivo',
        _ => 'Compromisso',
      };

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static String _utc(DateTime d) {
    final u = d.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  /// RFC 5545 text escaping: backslash, semicolon, comma and newlines.
  static String _escape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll(RegExp(r'\r?\n'), '\\n');
}
