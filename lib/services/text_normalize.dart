/// Lowercase text without accents, for matching names the person typed.
String normalizeText(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  const to = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
  final out = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString().toLowerCase();
}

/// Words of three letters or more, normalized.
List<String> wordsOf(String text) => normalizeText(text)
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.length >= 3)
    .toList();
