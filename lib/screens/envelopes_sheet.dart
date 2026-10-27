import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/envelopes.dart';
import '../services/spendable.dart';
import '../widgets/nexo_ui.dart';

/// "Por tipo de gasto": the six envelopes of the month against their share
/// of the reference income, with the sheets to adjust shares and to assign
/// categories. Planning only; nothing here changes entries or balances.
class EnvelopesSection extends StatefulWidget {
  const EnvelopesSection(
      {super.key, required this.app, required this.money, required this.now});
  final AppProvider app;
  final String Function(double) money;
  final DateTime now;

  @override
  State<EnvelopesSection> createState() => _EnvelopesSectionState();
}

class _EnvelopesSectionState extends State<EnvelopesSection> {
  Future<int>? _invested;

  @override
  void initState() {
    super.initState();
    _invested = _investedCents(widget.now);
  }

  /// Investment purchases of the month, in cents (Liberdade financeira).
  static Future<int> _investedCents(DateTime now) async {
    try {
      final db = await DBHelper.database;
      final start = DateTime(now.year, now.month).toIso8601String();
      final end = DateTime(now.year, now.month + 1).toIso8601String();
      final rows = await db.rawQuery(
          "SELECT COALESCE(SUM(cents), 0) AS c FROM investment_operations "
          "WHERE kind = 'buy' AND date >= ? AND date < ?",
          [start, end]);
      return (rows.first['c'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0; // No investments table yet: nothing invested.
    }
  }

  double _referenceIncome(AppProvider app) {
    if (app.settings.referenceIncome > 0) return app.settings.referenceIncome;
    return spendable(
      transactions: app.transactions,
      metadata: app.transactionMetadata,
      recurring: app.recurring,
      goals: app.savingsGoals,
      toMain: (t) => app.convertToMain(
          t.amount,
          t.currency.isEmpty
              ? app.accountById(t.accountId)?.currency ?? app.settings.currency
              : t.currency),
      convert: app.convertToMain,
      currencyOf: (r) =>
          app.accountById(r.accountId)?.currency ?? app.settings.currency,
      now: widget.now,
    ).fixedIncome;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return FutureBuilder<int>(
        future: _invested,
        builder: (context, snapshot) {
          final report = envelopeReport(
            categories: app.categories,
            transactions: app.transactions,
            metadata: app.transactionMetadata,
            contributions: app.savingsContributions,
            investedCents: snapshot.data ?? 0,
            shares: app.settings.envelopeShares,
            referenceIncome: _referenceIncome(app),
            toMain: (t) => app.convertToMain(
                t.amount,
                t.currency.isEmpty
                    ? app.accountById(t.accountId)?.currency ??
                        app.settings.currency
                    : t.currency),
            now: widget.now,
          );
          return EnvelopesView(
              report: report,
              money: widget.money,
              hidden: app.settings.hideBalance,
              onAdjust: () => showEnvelopeGoalsSheet(context, app),
              onClassify: () => showEnvelopeClassifySheet(context, app));
        });
  }
}

/// The grid itself (pure: testable without a database).
class EnvelopesView extends StatelessWidget {
  const EnvelopesView(
      {super.key,
      required this.report,
      required this.money,
      required this.hidden,
      required this.onAdjust,
      required this.onClassify});
  final EnvelopeReport report;
  final String Function(double) money;
  final bool hidden;
  final VoidCallback onAdjust, onClassify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      NexoSectionTitle('Por tipo de gasto',
          subtitle: report.hasBase
              ? 'Metas em % da renda de referência · ${hidden ? '••••' : money(report.referenceIncome)}'
              : 'Cadastre uma renda fixa recorrente ou informe a renda de referência',
          action: 'Ajustar',
          onAction: onAdjust),
      const SizedBox(height: 8),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // A fixed height that follows the text size: no empty space, no
        // overflow on narrow phones.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 112 * MediaQuery.textScalerOf(context).scale(1)),
        itemCount: report.lines.length,
        itemBuilder: (context, i) => _EnvelopeTile(
            line: report.lines[i],
            money: money,
            hidden: hidden,
            onTap: onClassify),
      ),
      if (report.unassigned.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onClassify,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(children: [
                Icon(Icons.label_off_outlined, size: 18, color: cs.tertiary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        '${hidden ? '••••' : money(report.unassignedSpent)} em ${report.unassigned.length} categoria(s) sem tipo',
                        style: theme.textTheme.bodySmall)),
                Text('Classificar',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.primary)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

class _EnvelopeTile extends StatelessWidget {
  const _EnvelopeTile(
      {required this.line,
      required this.money,
      required this.hidden,
      required this.onTap});
  final EnvelopeLine line;
  final String Function(double) money;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = line.usedRatio;
    final pct = line.planned <= 0 ? null : (ratio * 100).round();
    final tone = line.over
        ? NexoTones.expense(context)
        : line.isSaving && ratio >= 1
            ? NexoTones.income(context)
            : cs.onSurface;
    return NexoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(line.def.icon, size: 16, color: line.def.color),
            const SizedBox(width: 6),
            Expanded(
                child: Text(line.def.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Text(
                  pct == null
                      ? '—'
                      : '$pct%${line.over ? ' · passou' : line.isSaving && ratio >= 1 ? ' · feito' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                      fontFeatures: NexoTones.figures)),
            ),
            Flexible(
              child: Text('${line.share}% da renda',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ]),
          const SizedBox(height: 4),
          NexoProgress(
              value: ratio.clamp(0, 1).toDouble(), color: line.def.color),
          const SizedBox(height: 4),
          Text(
              hidden
                  ? '•••• de ••••'
                  : '${money(line.spent)} de ${money(line.planned)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Shares and the reference income. Sliders must add up to 100.
Future<void> showEnvelopeGoalsSheet(BuildContext context, AppProvider app) {
  return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EnvelopeGoalsSheet(app: app));
}

class _EnvelopeGoalsSheet extends StatefulWidget {
  const _EnvelopeGoalsSheet({required this.app});
  final AppProvider app;
  @override
  State<_EnvelopeGoalsSheet> createState() => _EnvelopeGoalsSheetState();
}

class _EnvelopeGoalsSheetState extends State<_EnvelopeGoalsSheet> {
  late Map<String, int> _shares;
  late final TextEditingController _income;

  @override
  void initState() {
    super.initState();
    _shares = Map.of(widget.app.settings.envelopeShares);
    final r = widget.app.settings.referenceIncome;
    _income = TextEditingController(
        text: r > 0 ? r.toStringAsFixed(2).replaceAll('.', ',') : '');
  }

  @override
  void dispose() {
    _income.dispose();
    super.dispose();
  }

  int get _total => _shares.values.fold(0, (s, v) => s + v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = _total == 100;
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Metas por tipo de gasto',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
              'Planejamento, não lançamento: nada aqui mexe em transações ou saldos.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          TextField(
            controller: _income,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Renda de referência (R\$)',
                helperText:
                    'Vazio: usa a renda fixa do mês (recorrentes de receita).'),
          ),
          const SizedBox(height: 12),
          for (final def in envelopeDefs) ...[
            Row(children: [
              Icon(def.icon, size: 18, color: def.color),
              const SizedBox(width: 8),
              Expanded(child: Text(def.name)),
              Text('${_shares[def.id] ?? def.defaultShare}%',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            Slider(
                value: (_shares[def.id] ?? def.defaultShare).toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: def.color,
                label: '${_shares[def.id] ?? def.defaultShare}%',
                onChanged: (v) => setState(() => _shares[def.id] = v.round())),
          ],
          Row(children: [
            Expanded(
                child: Text('Alocado $_total% / 100%',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ok ? null : theme.colorScheme.error))),
            TextButton(
                onPressed: () =>
                    setState(() => _shares = defaultEnvelopeShares),
                child: const Text('Padrão AUVP')),
          ]),
          const SizedBox(height: 8),
          FilledButton(
              onPressed: ok ? _save : null, child: const Text('Salvar metas')),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    final raw = _income.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final income = double.tryParse(raw) ?? 0;
    await widget.app.updateSetting('referenceIncome', income < 0 ? 0 : income);
    await widget.app.updateSetting('envelopeShares', _shares);
    if (mounted) Navigator.pop(context);
  }
}

/// Which categories belong to which kind. A suggestion fills the blanks;
/// the person confirms by saving.
Future<void> showEnvelopeClassifySheet(BuildContext context, AppProvider app) {
  return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EnvelopeClassifySheet(app: app));
}

class _EnvelopeClassifySheet extends StatefulWidget {
  const _EnvelopeClassifySheet({required this.app});
  final AppProvider app;
  @override
  State<_EnvelopeClassifySheet> createState() => _EnvelopeClassifySheetState();
}

class _EnvelopeClassifySheetState extends State<_EnvelopeClassifySheet> {
  late final List<AppCategory> _categories;
  late final Map<String, String?> _choice;

  @override
  void initState() {
    super.initState();
    _categories =
        widget.app.categories.where((c) => c.type == 'expense').toList();
    _choice = {for (final c in _categories) c.id: c.envelope};
  }

  void _suggest() => setState(() {
        for (final c in _categories) {
          _choice[c.id] ??= suggestEnvelope(c.name);
        }
      });

  Future<void> _save() async {
    for (final c in _categories) {
      if (_choice[c.id] == c.envelope) continue;
      await widget.app.updateCategory(c.copyWith(
          envelope: _choice[c.id], clearEnvelope: _choice[c.id] == null));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(children: [
            Expanded(
                child: Text('Tipo de cada categoria',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900))),
            TextButton.icon(
                onPressed: _suggest,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Sugerir')),
          ]),
          Text('A sugestão olha o nome da categoria; você decide.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(spacing: 6, children: [
                        ChoiceChip(
                            label: const Text('Sem tipo'),
                            selected: _choice[c.id] == null,
                            onSelected: (_) =>
                                setState(() => _choice[c.id] = null)),
                        for (final e in envelopeDefs)
                          ChoiceChip(
                              label: Text(e.name),
                              avatar: Icon(e.icon, size: 16, color: e.color),
                              selected: _choice[c.id] == e.id,
                              onSelected: (_) =>
                                  setState(() => _choice[c.id] = e.id)),
                      ]),
                    ),
                  ]),
            ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Salvar')),
        ],
      ),
    );
  }
}
