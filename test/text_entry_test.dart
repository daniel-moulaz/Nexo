import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/services/category_memory.dart';
import 'package:nexo/services/text_entry.dart';

void main() {
  final accounts = [
    Account(
        id: 'bank',
        name: 'Conta principal',
        type: 'bank',
        balance: 0,
        currency: 'BRL',
        colorValue: 0),
    Account(
        id: 'roxo',
        name: 'Cartão roxo',
        type: 'credit',
        balance: 0,
        currency: 'BRL',
        colorValue: 0),
  ];
  final categories = [
    AppCategory(
        id: 'food', name: 'Alimentação', type: 'expense', colorValue: 0),
    AppCategory(
        id: 'transport', name: 'Transporte', type: 'expense', colorValue: 0),
    AppCategory(id: 'home', name: 'Moradia', type: 'expense', colorValue: 0),
    AppCategory(id: 'salary', name: 'Salário', type: 'income', colorValue: 0),
  ];
  final now = DateTime(2026, 10, 28, 15);
  TextEntry parse(String text, {CategoryMemory? memory}) =>
      TextEntryParser.parse(text,
          accounts: accounts, categories: categories, now: now, memory: memory);

  test('amount, yesterday, card by name and category by lexicon', () {
    final e = parse('mercado 45,90 ontem no roxo');
    expect(e.amount, 45.90);
    expect(e.date, DateTime(2026, 10, 27));
    expect(e.accountId, 'roxo');
    expect(e.categoryId, 'food');
    expect(e.type, 'expense');
    expect(e.description, 'Mercado');
    expect(e.complete, isTrue);
  });

  test('thousands with dots and cents, explicit date, R\$ prefix', () {
    final e = parse('R\$ 1.250,00 aluguel 05/10');
    expect(e.amount, 1250.0);
    expect(e.date, DateTime(2026, 10, 5));
    expect(e.categoryId, 'home');
    expect(e.description, 'Aluguel');
  });

  test('dot decimals and a plain integer', () {
    expect(parse('uber 23.50').amount, 23.5);
    expect(parse('uber 23.50').categoryId, 'transport');
    expect(parse('padaria 12').amount, 12.0);
    expect(parse('padaria 12').categoryId, 'food');
  });

  test('a date is never read as money', () {
    final e = parse('academia 27/10');
    expect(e.amount, isNull);
    expect(e.complete, isFalse);
    expect(e.date, DateTime(2026, 10, 27));
  });

  test('income words switch the type and the category set', () {
    final e = parse('recebi salário 6200');
    expect(e.type, 'income');
    expect(e.amount, 6200);
    expect(e.categoryId, 'salary');
    final plus = parse('+ 150 reembolso');
    expect(plus.type, 'income');
    expect(plus.amount, 150);
  });

  test('"dia N" after today means last month; weekday is the latest one', () {
    expect(parse('luz 120 dia 30').date, DateTime(2026, 9, 30));
    expect(parse('luz 120 dia 3').date, DateTime(2026, 10, 3));
    // 28/10/2026 is a Wednesday; "segunda" is the 26th.
    expect(parse('almoço 30 segunda').date, DateTime(2026, 10, 26));
    expect(parse('café 8 quarta').date, DateTime(2026, 10, 28));
  });

  test('a day/month ahead of today without a year belongs to last year', () {
    expect(parse('seguro 900 15/12').date, DateTime(2025, 12, 15));
    expect(parse('seguro 900 15/12/26').date, DateTime(2026, 12, 15));
  });

  test('the account by the most matching words, prepositions dropped', () {
    final e = parse('farmácia 59,90 na conta principal');
    expect(e.accountId, 'bank');
    expect(e.description, 'Farmácia');
    expect(parse('pizza 80 no cartão roxo').accountId, 'roxo');
  });

  test('history beats the lexicon and keeps the runner-up one tap away', () {
    AppTransaction tx(String id, String desc, String cat) => AppTransaction(
        id: id,
        type: 'expense',
        amount: 10,
        description: desc,
        accountId: 'bank',
        categoryId: cat,
        date: now);
    final memory = CategoryMemory.fromTransactions([
      tx('1', 'Mercado Bom', 'home'),
      tx('2', 'Mercado Bom', 'home'),
      tx('3', 'mercado bom 123', 'home'),
      tx('4', 'Mercado Bom', 'food'),
    ]);
    final e = parse('mercado bom 50', memory: memory);
    expect(e.categoryId, 'home');
    expect(e.categoryAlternatives, ['food']);
  });

  test('memory stays quiet when the history is thin or split', () {
    AppTransaction tx(String id, String desc, String cat) => AppTransaction(
        id: id,
        type: 'expense',
        amount: 10,
        description: desc,
        accountId: 'bank',
        categoryId: cat,
        date: now);
    final thin =
        CategoryMemory.fromTransactions([tx('1', 'Padaria X', 'food')]);
    expect(thin.suggest('Padaria X', type: 'expense'), isNull);
    final split = CategoryMemory.fromTransactions([
      tx('1', 'Loja', 'food'),
      tx('2', 'Loja', 'home'),
      tx('3', 'Loja', 'food'),
      tx('4', 'Loja', 'home'),
    ]);
    expect(split.suggest('Loja', type: 'expense'), isNull);
    expect(split.ranked('Loja', type: 'expense'), hasLength(2));
    expect(split.suggest('Loja', type: 'income'), isNull);
  });

  test('nothing useful still yields a safe entry', () {
    final e = parse('   ');
    expect(e.amount, isNull);
    expect(e.description, '');
    expect(e.date, DateTime(2026, 10, 28));
    expect(e.type, 'expense');
  });
}
