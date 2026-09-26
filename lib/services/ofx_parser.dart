class OfxEntry {
  final DateTime date;
  final String description;
  final double amount;
  final String id;
  const OfxEntry(this.date, this.description, this.amount, this.id);
}

/// Supports bank OFX 1.x SGML and OFX 2.x XML, without executing XML entities.
List<OfxEntry> parseOfx(String content) {
  final entries = <OfxEntry>[];
  final seen = <String>{};
  for (final block in RegExp(
          r'<STMTTRN>([\s\S]*?)(?:</STMTTRN>|(?=<STMTTRN>|</BANKTRANLIST>))',
          caseSensitive: false)
      .allMatches(content)) {
    String value(String tag) =>
        (RegExp('<$tag>([^<\\r\\n]*)', caseSensitive: false)
                    .firstMatch(block.group(1)!)
                    ?.group(1) ??
                '')
            .trim()
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>');
    final rawDate = value('DTPOSTED');
    final amount = double.tryParse(value('TRNAMT'));
    if (rawDate.length < 8 || amount == null || !amount.isFinite || amount == 0)
      continue;
    final year = int.tryParse(rawDate.substring(0, 4));
    final month = int.tryParse(rawDate.substring(4, 6));
    final day = int.tryParse(rawDate.substring(6, 8));
    if (year == null || month == null || day == null) continue;
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) continue;
    final id = value('FITID');
    if (id.isNotEmpty && !seen.add(id)) continue;
    final description =
        [value('NAME'), value('MEMO')].where((v) => v.isNotEmpty).join(' • ');
    entries.add(OfxEntry(date,
        description.isEmpty ? 'Movimento importado' : description, amount, id));
  }
  return entries;
}
