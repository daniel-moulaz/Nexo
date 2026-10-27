import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'finance_rules.dart';

/// The six kinds of spending of the AUVP method, each with a share of the
/// reference income. Categories are assigned to a kind; the month is then
/// read as "how much of each kind's share was used". Planning only: nothing
/// here moves money or changes entries.
class EnvelopeDef {
  const EnvelopeDef(
      this.id, this.name, this.defaultShare, this.hint, this.color, this.icon);
  final String id, name, hint;
  final int defaultShare;
  final Color color;
  final IconData icon;
}

const envelopeDefs = [
  EnvelopeDef(
      'fixed',
      'Custos fixos',
      30,
      'O que precisa pagar para viver: aluguel, luz, água, internet, mercado, plano de saúde.',
      Color(0xFF1E88E5),
      Icons.home_outlined),
  EnvelopeDef(
      'comfort',
      'Conforto',
      15,
      'Melhora a rotina sem ser essencial: streaming, academia, delivery.',
      Color(0xFFEC407A),
      Icons.weekend_outlined),
  EnvelopeDef(
      'goals',
      'Metas',
      15,
      'O que guarda para um objetivo com prazo: viagem, entrada, troca de carro.',
      Color(0xFFAB47BC),
      Icons.flag_outlined),
  EnvelopeDef(
      'pleasures',
      'Prazeres',
      10,
      'Existe só pelo prazer: jantar fora, bar, presente, hobby.',
      Color(0xFFFB8C00),
      Icons.celebration_outlined),
  EnvelopeDef(
      'knowledge',
      'Conhecimento',
      5,
      'Investe em você: cursos, livros, mentoria, certificação.',
      Color(0xFFFDD835),
      Icons.school_outlined),
  EnvelopeDef(
      'freedom',
      'Liberdade financeira',
      25,
      'O que investe para construir patrimônio: aportes e aplicações.',
      Color(0xFF7E57C2),
      Icons.trending_up),
];

EnvelopeDef? envelopeById(String? id) =>
    id == null ? null : envelopeDefs.where((e) => e.id == id).firstOrNull;

/// The method's default split (sums 100).
Map<String, int> get defaultEnvelopeShares =>
    {for (final e in envelopeDefs) e.id: e.defaultShare};

/// A first guess from the category name; the person can change it.
String? suggestEnvelope(String categoryName) {
  final n = categoryName.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  if (has(['invest', 'aporte', 'reserva', 'poupan'])) return 'freedom';
  if (has(['educa', 'curso', 'livro', 'faculdade', 'escola', 'mentoria'])) {
    return 'knowledge';
  }
  if (has([
    'lazer',
    'bar',
    'festa',
    'presente',
    'hobby',
    'jogo',
    'cinema',
    'viagem',
    'roupa',
    'vestu',
    'compras',
    'shopping'
  ])) {
    return 'pleasures';
  }
  if (has([
    'assinatura',
    'streaming',
    'academia',
    'delivery',
    'ifood',
    'beleza',
    'pet',
    'restaurante',
    'lanche'
  ])) {
    return 'comfort';
  }
  if (has([
    'moradia',
    'conta',
    'aluguel',
    'luz',
    'água',
    'agua',
    'internet',
    'telefone',
    'celular',
    'mercado',
    'saúde',
    'saude',
    'farm',
    'transporte',
    'combust',
    'gasolina',
    'passage',
    'seguro',
    'imposto',
    'taxa',
    'condom',
    'aliment'
  ])) {
    return 'fixed';
  }
  return null;
}

class EnvelopeLine {
  const EnvelopeLine(
      {required this.def,
      required this.share,
      required this.planned,
      required this.spent,
      required this.categories});
  final EnvelopeDef def;
  final int share;
  final double planned, spent;
  final List<AppCategory> categories;

  double get usedRatio => planned <= 0 ? 0 : spent / planned;

  /// Investing and saving are the goal; spending is the thing to watch.
  bool get isSaving => def.id == 'freedom' || def.id == 'goals';
  bool get over => !isSaving && planned > 0 && spent > planned + .005;
}

class EnvelopeReport {
  const EnvelopeReport(
      {required this.lines,
      required this.referenceIncome,
      required this.unassignedSpent,
      required this.unassigned});
  final List<EnvelopeLine> lines;
  final double referenceIncome;

  /// Spending in expense categories without a kind this month.
  final double unassignedSpent;
  final List<AppCategory> unassigned;

  bool get hasBase => referenceIncome > 0;
  double get spent =>
      lines.fold<double>(0, (s, l) => s + l.spent) + unassignedSpent;
}

/// How the month sits against the shares. [investedCents] are the month's
/// investment purchases (Liberdade financeira); goal deposits come from
/// [contributions] (Metas); everything else is read from the categories.
EnvelopeReport envelopeReport({
  required List<AppCategory> categories,
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  required List<SavingsContribution> contributions,
  required int investedCents,
  required Map<String, int> shares,
  required double referenceIncome,
  required double Function(AppTransaction) toMain,
  required DateTime now,
}) {
  final start = DateTime(now.year, now.month);
  final end = DateTime(now.year, now.month + 1);
  bool inMonth(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  final byCategory = <String, double>{};
  for (final t in transactions) {
    if (t.type != 'expense' || !inMonth(t.date)) continue;
    if (FinanceRules.isNeutral(t, metadata[t.id])) continue;
    byCategory.update(t.categoryId, (v) => v + toMain(t),
        ifAbsent: () => toMain(t));
  }
  final expenseCategories =
      categories.where((c) => c.type == 'expense').toList();
  final lines = <EnvelopeLine>[];
  for (final def in envelopeDefs) {
    final own = expenseCategories.where((c) => c.envelope == def.id).toList();
    var spent = own.fold<double>(0, (s, c) => s + (byCategory[c.id] ?? 0));
    if (def.id == 'freedom') spent += investedCents / 100;
    if (def.id == 'goals') {
      spent += contributions
          .where((c) => c.type != 'withdraw' && inMonth(c.date))
          .fold<double>(0, (s, c) => s + c.amount);
    }
    final share = shares[def.id] ?? def.defaultShare;
    lines.add(EnvelopeLine(
        def: def,
        share: share,
        planned: referenceIncome * share / 100,
        spent: spent,
        categories: own));
  }
  final unassigned =
      expenseCategories.where((c) => envelopeById(c.envelope) == null).toList();
  return EnvelopeReport(
      lines: lines,
      referenceIncome: referenceIncome,
      unassignedSpent:
          unassigned.fold<double>(0, (s, c) => s + (byCategory[c.id] ?? 0)),
      unassigned:
          unassigned.where((c) => (byCategory[c.id] ?? 0) > 0).toList());
}
