import 'package:intl/intl.dart';

/// Parses money typed in either Brazilian format (1.234,56 / 1234,56)
/// or international format (1,234.56 / 1234.56).
double? parseMoney(String raw) {
  var value = raw
      .replaceAll('R\$', '')
      .replaceAll('\u00A0', '')
      .replaceAll(' ', '')
      .trim();
  if (value.isEmpty) return null;

  final hasComma = value.contains(',');
  final hasDot = value.contains('.');

  if (hasComma && hasDot) {
    if (value.lastIndexOf(',') > value.lastIndexOf('.')) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
    } else {
      value = value.replaceAll(',', '');
    }
  } else if (hasComma) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  }

  value = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
  return double.tryParse(value);
}

String ptDate(DateTime date) => DateFormat('dd/MM/yyyy', 'pt_BR').format(date);

String ptShortDate(DateTime date) => DateFormat('dd/MM', 'pt_BR').format(date);

String ptMonthYear(DateTime date) {
  final value = DateFormat('MMMM yyyy', 'pt_BR').format(date);
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
