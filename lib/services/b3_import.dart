import 'package:excel/excel.dart';
import 'text_normalize.dart';

/// One trade from the B3 investor area export ("Negociação", Excel).
/// Columns the file carries: Data do Negócio, Tipo de Movimentação
/// (Compra/Venda), Mercado, Prazo/Vencimento, Instituição, Código de
/// Negociação, Quantidade, Preço, Valor.
class B3Trade {
  const B3Trade(
      {required this.date,
      required this.kind,
      required this.ticker,
      required this.institution,
      required this.quantity,
      required this.priceCents,
      required this.totalCents,
      required this.market});
  final DateTime date;

  /// buy | sell
  final String kind;
  final String ticker, institution, market;
  final int quantity, priceCents, totalCents;

  /// Stable across re-imports of the same file: the same trade is not
  /// created twice.
  String get fingerprint =>
      'b3:${date.toIso8601String().substring(0, 10)}:$kind:$ticker:$quantity:$totalCents';
}

class B3ImportResult {
  const B3ImportResult(this.trades, this.skipped);
  final List<B3Trade> trades;

  /// Rows that could not be read, with the reason (no amounts).
  final List<String> skipped;
}

abstract final class B3Import {
  static B3ImportResult parse(List<int> xlsxBytes) {
    final excel = Excel.decodeBytes(xlsxBytes);
    final trades = <B3Trade>[];
    final skipped = <String>[];
    for (final sheet in excel.tables.values) {
      final rows = sheet.rows;
      if (rows.isEmpty) continue;
      final header = _findHeader(rows);
      if (header == null) continue;
      final col = header.columns;
      for (var i = header.index + 1; i < rows.length; i++) {
        final r = rows[i];
        String text(String key) {
          final c = col[key];
          return c == null || c >= r.length ? '' : _text(r[c]?.value);
        }

        final tickerText = text('ticker');
        if (tickerText.trim().isEmpty) continue;
        final date = _date(col['date'] == null || col['date']! >= r.length
            ? null
            : r[col['date']!]?.value);
        final kindText = normalizeText(text('kind'));
        final kind = kindText.startsWith('compra')
            ? 'buy'
            : kindText.startsWith('venda')
                ? 'sell'
                : null;
        final qty = _number(
            col['quantity'] == null || col['quantity']! >= r.length
                ? null
                : r[col['quantity']!]?.value);
        final price = _number(col['price'] == null || col['price']! >= r.length
            ? null
            : r[col['price']!]?.value);
        final total = _number(col['total'] == null || col['total']! >= r.length
            ? null
            : r[col['total']!]?.value);
        if (date == null ||
            kind == null ||
            qty == null ||
            qty <= 0 ||
            price == null) {
          skipped.add(
              'linha ${i + 1}: ${date == null ? 'data' : kind == null ? 'tipo' : 'quantidade ou preço'} ilegível');
          continue;
        }
        trades.add(B3Trade(
            date: date,
            kind: kind,
            ticker:
                tickerText.trim().toUpperCase().replaceAll(RegExp(r'F$'), ''),
            institution: text('institution').trim(),
            market: text('market').trim(),
            quantity: qty.round(),
            priceCents: (price * 100).round(),
            totalCents: ((total ?? qty * price) * 100).round()));
      }
    }
    trades.sort((a, b) => a.date.compareTo(b.date));
    return B3ImportResult(trades, skipped);
  }

  static ({int index, Map<String, int> columns})? _findHeader(
      List<List<Data?>> rows) {
    const wanted = {
      'date': ['data do negocio', 'data'],
      'kind': ['tipo de movimentacao', 'tipo'],
      'market': ['mercado'],
      'institution': ['instituicao'],
      'ticker': ['codigo de negociacao', 'codigo', 'ativo'],
      'quantity': ['quantidade'],
      'price': ['preco'],
      'total': ['valor'],
    };
    for (var i = 0; i < rows.length && i < 20; i++) {
      final cells =
          rows[i].map((c) => normalizeText(_text(c?.value)).trim()).toList();
      final columns = <String, int>{};
      for (final e in wanted.entries) {
        for (var c = 0; c < cells.length; c++) {
          if (e.value.any((w) => cells[c] == w || cells[c].startsWith(w))) {
            columns[e.key] = c;
            break;
          }
        }
      }
      if (columns.containsKey('ticker') &&
          columns.containsKey('quantity') &&
          columns.containsKey('price')) {
        return (index: i, columns: columns);
      }
    }
    return null;
  }

  static String _text(CellValue? v) => switch (v) {
        null => '',
        TextCellValue t => t.value.text ?? '',
        IntCellValue n => n.value.toString(),
        DoubleCellValue n => n.value.toString(),
        DateCellValue d =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}',
        DateTimeCellValue d =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}',
        _ => v.toString(),
      };

  static double? _number(CellValue? v) => switch (v) {
        null => null,
        IntCellValue n => n.value.toDouble(),
        DoubleCellValue n => n.value,
        TextCellValue t => _parseNumber(t.value.text ?? ''),
        _ => null,
      };

  /// "1.234,56" and "1234.56" both read as 1234.56; "R$" is ignored.
  static double? _parseNumber(String s) {
    var t = s.replaceAll(RegExp(r'[R$\s]'), '');
    if (t.isEmpty) return null;
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(t);
  }

  static DateTime? _date(CellValue? v) {
    switch (v) {
      case DateCellValue d:
        return DateTime(d.year, d.month, d.day);
      case DateTimeCellValue d:
        return DateTime(d.year, d.month, d.day);
      case TextCellValue t:
        final m = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{2,4})')
            .firstMatch(t.value.text ?? '');
        if (m == null) {
          return DateTime.tryParse(t.value.text ?? '');
        }
        var y = int.parse(m[3]!);
        if (y < 100) y += 2000;
        return DateTime(y, int.parse(m[2]!), int.parse(m[1]!));
      default:
        return null;
    }
  }
}
