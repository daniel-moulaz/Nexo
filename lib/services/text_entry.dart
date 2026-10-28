import '../models/models.dart';
import 'category_memory.dart';
import 'text_normalize.dart';

/// One line of text turned into the fields of an entry, the way Fantastical
/// reads "lunch with Sarah at 1pm tomorrow": "mercado 45,90 ontem no roxo"
/// becomes amount 45,90, yesterday, the account whose name contains "roxo",
/// and the category the person usually confirms for "mercado". Nothing is
/// saved here; the form opens filled in and the person confirms.
class TextEntry {
  const TextEntry(
      {required this.amount,
      required this.description,
      required this.date,
      required this.type,
      this.accountId,
      this.categoryId,
      this.categoryAlternatives = const []});
  final double? amount;
  final String description;
  final DateTime date;
  final String type; // income | expense
  final String? accountId;
  final String? categoryId;

  /// Runner-up categories from the history, for a one-tap correction.
  final List<String> categoryAlternatives;

  bool get complete => amount != null && amount! > 0;
}

class TextEntryParser {
  static const _incomeWords = {
    'recebi',
    'recebido',
    'recebimento',
    'salario',
    'entrada',
    'entrou',
    'renda',
    'receita',
    'reembolso',
    'estorno',
    'ganhei',
    'pagamento recebido',
  };
  static const _weekdays = {
    'segunda': DateTime.monday,
    'terca': DateTime.tuesday,
    'quarta': DateTime.wednesday,
    'quinta': DateTime.thursday,
    'sexta': DateTime.friday,
    'sabado': DateTime.saturday,
    'domingo': DateTime.sunday,
  };

  /// Words that usually name a category, when the person has no history
  /// for the description yet. Matched against the category *names*.
  static const _lexicon = <String, List<String>>{
    'aliment': [
      'mercado',
      'supermercado',
      'ifood',
      'restaurante',
      'lanche',
      'padaria',
      'almoco',
      'jantar',
      'pizza',
      'cafe',
      'comida',
      'feira',
      'acougue',
    ],
    'transp': [
      'uber',
      'taxi',
      'onibus',
      'metro',
      'gasolina',
      'combustivel',
      'estacionamento',
      'pedagio',
      'passagem',
    ],
    'saude': [
      'farmacia',
      'remedio',
      'medico',
      'consulta',
      'dentista',
      'academia',
      'exame',
    ],
    'assinatura': ['netflix', 'spotify', 'assinatura', 'prime', 'disney'],
    'moradia': [
      'aluguel',
      'condominio',
      'luz',
      'agua',
      'internet',
      'energia',
      'gas',
      'iptu',
    ],
    'lazer': ['cinema', 'show', 'bar', 'jogo', 'viagem', 'passeio'],
    'educa': ['curso', 'livro', 'escola', 'faculdade', 'mensalidade'],
    'salario': ['salario'],
  };

  static TextEntry parse(String text,
      {required List<Account> accounts,
      required List<AppCategory> categories,
      DateTime? now,
      CategoryMemory? memory}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    var rest = ' ${text.trim()} ';

    // ── Amount: "45,90", "1.250,00", "45.90", "45", with or without R$ ──
    double? amount;
    final money = RegExp(
        r'(?<![\w,.])(?:r\$\s*)?(\d{1,3}(?:\.\d{3})+|\d+)(?:[,](\d{1,2}))?(?![\w,.])',
        caseSensitive: false);
    final dotDecimal = RegExp(r'(?<![\w,.])(?:r\$\s*)?(\d+)\.(\d{2})(?![\w,.])',
        caseSensitive: false);
    // Dates "27/10" must not be read as money; mask them first.
    final dateToken = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b');
    final masked = rest.replaceAllMapped(dateToken, (m) => ' ' * m[0]!.length);
    final dot = dotDecimal.firstMatch(masked);
    final plain = money.firstMatch(masked);
    if (dot != null && (plain == null || dot.start <= plain.start)) {
      amount = double.parse('${dot[1]}.${dot[2]}');
      rest = _blank(rest, dot.start, dot.end);
    } else if (plain != null) {
      final whole = plain[1]!.replaceAll('.', '');
      final cents = plain[2];
      amount = double.parse(
          cents == null ? whole : '$whole.${cents.padRight(2, '0')}');
      rest = _blank(rest, plain.start, plain.end);
    }

    // ── Type ──
    final normalized = normalizeText(rest);
    final words = wordsOf(rest);
    var type = 'expense';
    if (normalized.trim().startsWith('+') ||
        words.any(_incomeWords.contains) ||
        _incomeWords.any((w) => w.contains(' ') && normalized.contains(w))) {
      type = 'income';
    }
    rest = rest.replaceFirst(RegExp(r'^\s*\+'), ' ');

    // ── Date ──
    var date = day;
    final explicit = dateToken.firstMatch(rest);
    if (explicit != null) {
      final d = int.parse(explicit[1]!);
      final m = int.parse(explicit[2]!);
      var y = explicit[3] == null ? day.year : int.parse(explicit[3]!);
      if (y < 100) y += 2000;
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        date = DateTime(y, m, d);
        // Without a year, a day/month ahead of today means last year.
        if (explicit[3] == null && date.isAfter(day)) {
          date = DateTime(y - 1, m, d);
        }
      }
      rest = _blank(rest, explicit.start, explicit.end);
    } else {
      final relative = <RegExp, int>{
        RegExp(r'\banteontem\b'): -2,
        RegExp(r'\bontem\b'): -1,
        RegExp(r'\bhoje\b'): 0,
      };
      var found = false;
      for (final e in relative.entries) {
        final m = e.key.firstMatch(normalizeText(rest));
        if (m != null) {
          date = day.add(Duration(days: e.value));
          rest = _blankWord(rest, m[0]!);
          found = true;
          break;
        }
      }
      if (!found) {
        final dia =
            RegExp(r'\bdia (\d{1,2})\b').firstMatch(normalizeText(rest));
        if (dia != null) {
          final d = int.parse(dia[1]!);
          if (d >= 1 && d <= 31) {
            date = d > day.day
                ? DateTime(day.year, day.month - 1, d)
                : DateTime(day.year, day.month, d);
          }
          rest = _blankWord(rest, dia[0]!);
          found = true;
        }
      }
      if (!found) {
        for (final e in _weekdays.entries) {
          final m = RegExp('\\b${e.key}(?:-feira)?\\b')
              .firstMatch(normalizeText(rest));
          if (m != null) {
            var back = (day.weekday - e.value) % 7;
            if (back < 0) back += 7;
            date = day.subtract(Duration(days: back));
            rest = _blankWord(rest, m[0]!);
            break;
          }
        }
      }
    }

    // ── Account: the name with the most words in the text ──
    String? accountId;
    var bestScore = 0;
    for (final a in accounts) {
      final score = _nameScore(a.name, rest);
      if (score > bestScore) {
        bestScore = score;
        accountId = a.id;
      }
    }
    if (accountId != null) {
      final account = accounts.firstWhere((a) => a.id == accountId);
      for (final w in wordsOf(account.name)) {
        rest = _blankWord(rest, w);
      }
      rest = rest.replaceAll(
          RegExp(r'\s(no|na|pelo|pela|com|do|da|de|cartao|cartão|conta)\s+$',
              caseSensitive: false),
          ' ');
    }

    // ── Description: what is left ──
    var description = rest
        .replaceAll(RegExp(r'\br\$', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    description = description
        .replaceAll(
            RegExp(r'\s+(no|na|pelo|pela|com|do|da|de|cartao|cartão|conta)$',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'^(no|na|pelo|pela|com|do|da|de)\s+', caseSensitive: false),
            '')
        .trim();
    if (description.isNotEmpty) {
      description = description[0].toUpperCase() + description.substring(1);
    }

    // ── Category: history first, then category names, then the lexicon ──
    String? categoryId;
    var alternatives = const <String>[];
    final ofType = categories.where((c) => c.type == type).toList();
    if (memory != null && description.isNotEmpty) {
      categoryId = memory.suggest(description, type: type);
      alternatives = memory
          .ranked(description, type: type)
          .where((id) => id != categoryId && ofType.any((c) => c.id == id))
          .take(2)
          .toList();
    }
    if (categoryId == null) {
      var best = 0;
      for (final c in ofType) {
        final score = _nameScore(c.name, text);
        if (score > best) {
          best = score;
          categoryId = c.id;
        }
      }
    }
    if (categoryId == null) {
      final textWords = wordsOf(text).toSet();
      for (final e in _lexicon.entries) {
        if (!e.value.any(textWords.contains)) continue;
        final match = ofType
            .where((c) => normalizeText(c.name).contains(e.key))
            .firstOrNull;
        if (match != null) {
          categoryId = match.id;
          break;
        }
      }
    }
    if (categoryId != null && !ofType.any((c) => c.id == categoryId)) {
      categoryId = null;
    }

    return TextEntry(
        amount: amount,
        description: description,
        date: date,
        type: type,
        accountId: accountId,
        categoryId: categoryId,
        categoryAlternatives: alternatives);
  }

  static int _nameScore(String name, String text) {
    final textWords = wordsOf(text).toSet();
    return wordsOf(name).where(textWords.contains).length;
  }

  static String _blank(String s, int start, int end) =>
      s.substring(0, start) + ' ' * (end - start) + s.substring(end);

  /// Blanks the first whole-word occurrence, comparing without accents.
  static String _blankWord(String s, String word) {
    final norm = normalizeText(s);
    final m = RegExp('(?<![a-z0-9])${RegExp.escape(word)}(?![a-z0-9])')
        .firstMatch(norm);
    if (m == null) return s;
    return _blank(s, m.start, m.end);
  }
}
