import '../database/db_helper.dart';
import '../models/models.dart';
import 'package:sqflite/sqflite.dart';

class ImportRule {
  final String id, pattern, type, categoryId, subcategory;
  const ImportRule(
      {required this.id,
      required this.pattern,
      required this.type,
      required this.categoryId,
      this.subcategory = ''});
  Map<String, Object?> toMap() => {
        'id': id,
        'pattern': pattern.trim(),
        'type': type,
        'category_id': categoryId,
        'subcategory': subcategory.trim()
      };
  factory ImportRule.fromMap(Map<String, dynamic> m) => ImportRule(
      id: m['id'],
      pattern: m['pattern'],
      type: m['type'],
      categoryId: m['category_id'],
      subcategory: m['subcategory']);
}

class ImportRulesService {
  static Future<List<ImportRule>> load() async =>
      (await (await DBHelper.database).query('import_rules'))
          .map(ImportRule.fromMap)
          .toList();
  static Future<void> save(ImportRule rule) async {
    if (rule.pattern.trim().isEmpty ||
        !['expense', 'income'].contains(rule.type)) {
      throw ArgumentError('Informe o texto da descrição e o tipo.');
    }
    final db = await DBHelper.database;
    final cats = await db.query('categories',
        where: 'id = ? AND type = ?', whereArgs: [rule.categoryId, rule.type]);
    if (cats.isEmpty)
      throw ArgumentError('Selecione uma categoria válida para o tipo.');
    await db.insert('import_rules', rule.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> delete(String id) async => (await DBHelper.database)
      .delete('import_rules', where: 'id = ?', whereArgs: [id]);
  static ImportRule? match(List<ImportRule> rules, String description,
      String type, List<AppCategory> categories) {
    final candidates = rules
        .where((r) =>
            r.pattern.trim().isNotEmpty &&
            r.type == type &&
            description
                .toLowerCase()
                .contains(r.pattern.trim().toLowerCase()) &&
            categories.any((c) => c.id == r.categoryId && c.type == type))
        .toList()
      ..sort((a, b) {
        final length =
            b.pattern.trim().length.compareTo(a.pattern.trim().length);
        return length == 0 ? a.id.compareTo(b.id) : length;
      });
    return candidates.firstOrNull;
  }

  /// Candidates only: never merges or modifies balances.
  static List<AppTransaction> candidates(List<AppTransaction> transactions,
          {required String accountId,
          required DateTime date,
          required double amount,
          required String type}) =>
      transactions
          .where((t) =>
              t.accountId == accountId &&
              t.type == type &&
              (t.amount - amount).abs() < 0.005 &&
              DateTime(t.date.year, t.date.month, t.date.day)
                      .difference(DateTime(date.year, date.month, date.day))
                      .inDays
                      .abs() <=
                  3)
          .toList();
}
