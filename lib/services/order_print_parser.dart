import 'receipt_parser.dart';
import 'text_normalize.dart';

/// How an order was paid, as a print shows it.
enum PrintPayment { pix, credit, debit, cash }

/// What a screenshot of a delivery order (iFood) says, after on-device OCR.
/// The form is filled with it and the person confirms before saving.
class OrderPrint {
  const OrderPrint(
      {this.app,
      this.total,
      this.merchant,
      this.date,
      this.payment,
      this.reliable = false,
      this.doubts = const []});

  /// `ifood` when the print is recognized as an iFood order; null for any
  /// other text (read as a receipt).
  final String? app;
  final double? total;
  final String? merchant;
  final DateTime? date;
  final PrintPayment? payment;

  /// True only when the total came from an explicit "Total" line and the
  /// parts add up (or there were no parts), with the restaurant found.
  final bool reliable;

  /// What made the reading unsure, in words for the person.
  final List<String> doubts;

  bool get hasTotal => total != null && total! > 0;

  String? get paymentLabel => switch (payment) {
        PrintPayment.pix => 'Pix',
        PrintPayment.credit => 'cartão de crédito',
        PrintPayment.debit => 'cartão de débito',
        PrintPayment.cash => 'dinheiro',
        null => null,
      };
}

abstract final class OrderPrintParser {
  static final _money = RegExp(r'R\$\s*-?\s*(\d{1,3}(?:\.\d{3})*|\d+),(\d{2})');
  static final _slashDate =
      RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?\b');
  static final _wordDate = RegExp(
      r'\b(\d{1,2})\s+(?:de\s+)?(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)[a-zç]*\.?(?:\s+(?:de\s+)?(\d{4}))?');
  static const _months = {
    'jan': 1, 'fev': 2, 'mar': 3, 'abr': 4, 'mai': 5, 'jun': 6, //
    'jul': 7, 'ago': 8, 'set': 9, 'out': 10, 'nov': 11, 'dez': 12,
  };

  /// Lines that are the app's own words, never the restaurant's name.
  static const _chrome = [
    'detalhes do pedido',
    'pedido',
    'ajuda',
    'acompanhar',
    'avaliar',
    'concluido',
    'entregue',
    'cancelado',
    'resumo',
    'itens',
    'subtotal',
    'taxa',
    'total',
    'pagamento',
    'pago',
    'cupom',
    'desconto',
    'ifood',
    'entrega',
    'retirada',
    'endereco',
    'voltar',
    'adicionar a sacola',
    'pedir de novo',
    'repetir',
    'nota fiscal',
    'como foi',
    'gorjeta',
    'chat',
    'hoje',
    'ontem',
  ];

  static double _value(RegExpMatch m) =>
      double.parse('${m[1]!.replaceAll('.', '')}.${m[2]}');

  static bool looksLikeIfood(String text) {
    final n = normalizeText(text);
    return n.contains('ifood') ||
        (n.contains('pedido') &&
            (n.contains('taxa de entrega') || n.contains('taxa de servico')));
  }

  static OrderPrint parse(String text, {DateTime? now}) {
    final today = now ?? DateTime.now();
    if (!looksLikeIfood(text)) {
      final r = ReceiptParser.parse(text, now: today);
      return OrderPrint(
          total: r.total,
          merchant: r.merchant,
          date: r.date,
          payment: _payment(normalizeText(text)),
          doubts: const ['Não parece um pedido do iFood: lido como cupom.']);
    }
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final doubts = <String>[];

    // ── Total: the amount on the "Total" line (or the next line) ──
    double? total;
    double? subtotal;
    var fees = 0.0, discounts = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final n = normalizeText(lines[i]);
      double? amountHere() {
        final here = _money.allMatches(lines[i]).toList();
        if (here.isNotEmpty) return _value(here.last);
        if (i + 1 < lines.length) {
          final next = _money.allMatches(lines[i + 1]).toList();
          final nextWords = normalizeText(lines[i + 1]);
          if (next.isNotEmpty &&
              !RegExp(r'[a-z]{4,}')
                  .hasMatch(nextWords.replaceAll(RegExp(r'r\$|gratis'), ''))) {
            return _value(next.last);
          }
        }
        return null;
      }

      if (n.startsWith('subtotal')) {
        subtotal ??= amountHere();
      } else if (n.startsWith('taxa')) {
        if (!n.contains('gratis')) fees += amountHere() ?? 0;
      } else if (n.contains('desconto') || n.startsWith('cupom')) {
        discounts += amountHere() ?? 0;
      } else if (RegExp(r'^total\b').hasMatch(n) || n == 'total pago') {
        total ??= amountHere();
      }
    }
    if (total == null) {
      doubts.add('Não achei a linha "Total": confira o valor.');
      double? largest;
      for (final line in lines) {
        for (final m in _money.allMatches(line)) {
          final v = _value(m);
          if (largest == null || v > largest) largest = v;
        }
      }
      total = largest;
    } else if (subtotal != null &&
        (subtotal + fees - discounts - total).abs() > 0.05) {
      doubts.add('Subtotal, taxas e descontos não fecham com o total.');
    }

    // ── Restaurant: the first line that is a name, not the app's words ──
    String? merchant;
    for (final line in lines.take(10)) {
      final n = normalizeText(line);
      if (_chrome
          .any((c) => n == c || n.startsWith('$c ') || n.startsWith(c))) {
        continue;
      }
      if (_money.hasMatch(line) || RegExp(r'^\d').hasMatch(line)) continue;
      if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(line)) continue;
      if (wordsOf(line).isEmpty || line.length < 3) continue;
      merchant = line.length > 40 ? line.substring(0, 40).trim() : line;
      break;
    }
    if (merchant == null) doubts.add('Não achei o nome do restaurante.');

    // ── Date: dd/mm[/yyyy] or "13 de nov", never in the future ──
    DateTime? date;
    for (final line in lines) {
      final n = normalizeText(line);
      if (n.contains('hoje')) {
        date = DateTime(today.year, today.month, today.day);
      } else if (n.contains('ontem')) {
        final y = today.subtract(const Duration(days: 1));
        date = DateTime(y.year, y.month, y.day);
      } else {
        date = _dateIn(n, today);
      }
      if (date != null) break;
    }
    if (date == null) doubts.add('Sem data no print: ficou a de hoje.');

    final payment = _payment(normalizeText(text));
    if (payment == null) doubts.add('Não achei a forma de pagamento.');

    return OrderPrint(
        app: 'ifood',
        total: total,
        merchant: merchant,
        date: date,
        payment: payment,
        reliable: doubts.isEmpty ||
            (doubts.length == 1 && date == null && total != null),
        doubts: doubts);
  }

  static DateTime? _dateIn(String n, DateTime today) {
    DateTime? pick(int d, int m, int? y) {
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      var year = y ?? today.year;
      if (year < 100) year += 2000;
      var candidate = DateTime(year, m, d);
      // "13 de dez" read in January is last year's.
      if (y == null && candidate.isAfter(today.add(const Duration(days: 1)))) {
        candidate = DateTime(year - 1, m, d);
      }
      if (candidate.isAfter(today.add(const Duration(days: 1)))) return null;
      return candidate;
    }

    for (final m in _slashDate.allMatches(n)) {
      final got = pick(int.parse(m[1]!), int.parse(m[2]!),
          m[3] == null ? null : int.parse(m[3]!));
      if (got != null) return got;
    }
    for (final m in _wordDate.allMatches(n)) {
      final got = pick(int.parse(m[1]!), _months[m[2]!]!,
          m[3] == null ? null : int.parse(m[3]!));
      if (got != null) return got;
    }
    return null;
  }

  static PrintPayment? _payment(String n) {
    if (RegExp(r'\bpix\b').hasMatch(n)) return PrintPayment.pix;
    if (n.contains('debito')) return PrintPayment.debit;
    if (n.contains('credito') ||
        RegExp(r'\b(mastercard|visa|elo|amex|hipercard|nubank)\b')
            .hasMatch(n) ||
        RegExp(r'(\*{2,}|•{2,}|\.{3,})\s*\d{4}').hasMatch(n)) {
      return PrintPayment.credit;
    }
    if (n.contains('dinheiro')) return PrintPayment.cash;
    return null;
  }
}
