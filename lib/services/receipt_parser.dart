import 'text_normalize.dart';

/// What a receipt or invoice photo says, after OCR: the total, the date and
/// the merchant line. Pure text in, fields out; the form confirms. Works on
/// Brazilian cupons (NFC-e), card slips and boletos.
class ReceiptReading {
  const ReceiptReading(
      {this.total, this.date, this.merchant, this.lines = const []});
  final double? total;
  final DateTime? date;
  final String? merchant;
  final List<String> lines;
  bool get hasTotal => total != null && total! > 0;
}

abstract final class ReceiptParser {
  static final _money =
      RegExp(r'(?<![\d,.])(\d{1,3}(?:\.\d{3})+|\d+),(\d{2})(?![\d])');
  static final _date = RegExp(r'\b(\d{2})/(\d{2})/(\d{4}|\d{2})\b');
  static const _totalWords = [
    'valor total',
    'total a pagar',
    'valor pago',
    'total geral',
    'total r\$',
    'total',
    'valor:',
  ];
  static const _skipMerchant = [
    'cnpj',
    'cpf',
    'nfc',
    'nf-e',
    'cupom',
    'documento',
    'auxiliar',
    'consumidor',
    'sat',
    'ie:',
    'im:',
    'rua ',
    'av ',
    'avenida',
  ];

  static ReceiptReading parse(String text, {DateTime? now}) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // ── Total: the amount on a "total" line, else the largest amount ──
    double? total;
    for (final line in lines) {
      final n = normalizeText(line);
      if (!_totalWords.any(n.contains)) continue;
      if (n.contains('subtotal') ||
          n.contains('desconto') ||
          n.contains('troco')) {
        continue;
      }
      final m = _money.allMatches(line).toList();
      if (m.isNotEmpty) {
        total = _toDouble(m.last);
        break;
      }
    }
    if (total == null) {
      double? largest;
      for (final line in lines) {
        final n = normalizeText(line);
        if (n.contains('troco') || n.contains('cnpj') || n.contains('cpf'))
          continue;
        for (final m in _money.allMatches(line)) {
          final v = _toDouble(m);
          if (largest == null || v > largest) largest = v;
        }
      }
      total = largest;
    }

    // ── Date: the first dd/mm/yyyy that is not in the future ──
    DateTime? date;
    final today = now ?? DateTime.now();
    for (final line in lines) {
      for (final m in _date.allMatches(line)) {
        final d = int.parse(m[1]!), mo = int.parse(m[2]!);
        var y = int.parse(m[3]!);
        if (y < 100) y += 2000;
        if (mo < 1 || mo > 12 || d < 1 || d > 31) continue;
        final candidate = DateTime(y, mo, d);
        if (candidate.isAfter(today.add(const Duration(days: 1)))) continue;
        date = candidate;
        break;
      }
      if (date != null) break;
    }

    // ── Merchant: the first line that looks like a name ──
    String? merchant;
    for (final line in lines.take(8)) {
      final n = normalizeText(line);
      if (_skipMerchant.any(n.contains)) continue;
      if (RegExp(r'\d{3,}').hasMatch(line)) continue; // numbers: not a name
      if (wordsOf(line).isEmpty) continue;
      merchant = line.length > 40 ? line.substring(0, 40).trim() : line;
      break;
    }
    return ReceiptReading(
        total: total, date: date, merchant: merchant, lines: lines);
  }

  static double _toDouble(RegExpMatch m) =>
      double.parse('${m[1]!.replaceAll('.', '')}.${m[2]}');
}
