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
  } else if (RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(value)) {
    value = value.replaceAll('.', '');
  }

  if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parsed = double.tryParse(value);
  return parsed != null && parsed.isFinite ? parsed : null;
}

String ptDate(DateTime date) => DateFormat('dd/MM/yyyy', 'pt_BR').format(date);

String ptShortDate(DateTime date) => DateFormat('dd/MM', 'pt_BR').format(date);

String ptMonthYear(DateTime date) {
  final value = DateFormat('MMMM yyyy', 'pt_BR').format(date);
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
