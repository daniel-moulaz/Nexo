import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/db_helper.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/cancel_intents.dart';
import '../services/recurring_projection.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import '../utils/snackbar.dart';
import 'recurring_screen.dart';

class RecurringDetailScreen extends StatefulWidget {
  final RecurringPayment recurring;
  final String Function(double) fmt;

  const RecurringDetailScreen({
    super.key,
    required this.recurring,
    required this.fmt,
  });

  @override
  State<RecurringDetailScreen> createState() => _RecurringDetailScreenState();
}

class _RecurringDetailScreenState extends State<RecurringDetailScreen> {
  List<RecurringHistoryEntry>? _history;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await DBHelper.getRecurringHistory(widget.recurring.id);
    if (mounted) setState(() => _history = history);
  }

  String _frequency(RecurringPayment r) {
    final n = r.freqVal <= 0 ? 1 : r.freqVal;
    if (n == 1) {
      return switch (r.freqUnit) {
        'days' => 'Diária',
        'weeks' => 'Semanal',
        'years' => 'Anual',
        _ => 'Mensal',
      };
    }
    final unit = switch (r.freqUnit) {
      'days' => 'dias',
      'weeks' => 'semanas',
      'years' => 'anos',
      _ => 'meses',
    };
    return 'A cada $n $unit';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final r = app.recurring.firstWhere(
      (item) => item.id == widget.recurring.id,
      orElse: () => widget.recurring,
    );
    final account = app.accountById(r.accountId);
    final category = app.categoryById(r.categoryId);
    final currency = account?.currency ?? app.settings.currency;
    String money(double value, [String? originalCurrency]) =>
        app.settings.hideBalance
            ? '••••'
            : formatAmount(value, originalCurrency ?? currency);
    final upcoming = RecurringProjection.calculate([r],
        until: DateTime(
            DateTime.now().year + 1, DateTime.now().month, DateTime.now().day),
        registeredIds: app.transactions.map((t) => t.id).toSet());
    final total = r.totalPayments;
    final progress = total != null && total > 0 ? r.progress : null;
    final today = DateTime.now();
    final startToday = DateTime(today.year, today.month, today.day);
    final next = DateTime(
        r.nextActionDate.year, r.nextActionDate.month, r.nextActionDate.day);
    final days = next.difference(startToday).inDays;
    final overdue = days < 0;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: () => openRecurringSheet(context, existing: r),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: () => _delete(context, app, r),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.paymentType == 'income'
                            ? 'Receita recorrente'
                            : r.recurringType == 'installment'
                                ? 'Despesa parcelada'
                                : 'Despesa fixa',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: overdue
                            ? cs.errorContainer
                            : cs.surface.withValues(alpha: .75),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        !r.canComplete
                            ? 'Encerrada'
                            : overdue
                                ? 'Atrasada'
                                : days == 0
                                    ? 'Vence hoje'
                                    : 'Em $days dia${days == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: overdue ? cs.error : cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  r.canComplete
                      ? money(r.nextActionAmount)
                      : 'Cronograma concluído',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(r.canComplete
                    ? '${_frequency(r)} • próxima em ${ptDate(r.nextActionDate)}'
                    : _frequency(r)),
                Text('${r.paidPayments} pagas • ${r.skippedPayments} puladas'),
                if (r.remainingPayments != null)
                  Text(
                      '${r.remainingPayments} ${r.canSkip ? 'ocorrências' : 'parcelas'} restantes'),
                if (r.hasSkippedInstallments)
                  const Text(
                      'Parcelas puladas anteriormente continuam devidas. Pagar regulariza a mais antiga sem avançar o cronograma.'),
                if (progress != null) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:
                        LinearProgressIndicator(value: progress, minHeight: 7),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${r.progressPayments} de $total ${r.canSkip ? 'ocorrências concluídas' : 'parcelas pagas'} • ${(progress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (r.paymentType == 'expense' && r.recurringType != 'installment')
            _CancelIntentTile(recurring: r),
          Card(
            elevation: 0,
            child: ExpansionTile(
              title: const Text('Dados do compromisso'),
              subtitle: Text(
                  '${account?.name ?? 'Conta removida'} • ${_frequency(r)}'),
              children: [
                _InfoTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Conta',
                  value: account?.name ?? 'Conta removida',
                ),
                _InfoTile(
                  icon: Icons.category_outlined,
                  label: 'Categoria',
                  value: category?.name ?? 'Sem categoria',
                ),
                _InfoTile(
                  icon: Icons.repeat_rounded,
                  label: 'Periodicidade',
                  value: _frequency(r),
                ),
                _InfoTile(
                  icon: Icons.play_circle_outline_rounded,
                  label: 'Início',
                  value: ptDate(r.startDate),
                ),
                if (r.endDate != null)
                  _InfoTile(
                    icon: Icons.stop_circle_outlined,
                    label: 'Fim',
                    value: ptDate(r.endDate!),
                  ),
                if (r.notes.trim().isNotEmpty)
                  _InfoTile(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Observação',
                    value: r.notes,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (r.canSkip)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !r.canComplete
                        ? null
                        : () async {
                            await confirmRecurringAction(context, app, r,
                                skip: true);
                            await _loadHistory();
                          },
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Pular próxima'),
                  ),
                ),
              if (r.canSkip) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: !r.canComplete
                      ? null
                      : () async {
                          await confirmRecurringAction(context, app, r);
                          await _loadHistory();
                        },
                  icon: const Icon(Icons.done_all_rounded),
                  label: Text(r.paymentType == 'income'
                      ? 'Registrar recebimento'
                      : 'Registrar pagamento'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (r.canComplete)
            Card(
                child: ExpansionTile(
              title: const Text('Próximos vencimentos'),
              subtitle: const Text(
                  'Até 12 meses • previsão, sem registrar lançamentos'),
              children: [
                for (final e in upcoming.occurrences.take(12))
                  ListTile(
                      title: Text(ptDate(e.date)),
                      subtitle: Text(e.date.isBefore(startToday)
                          ? 'Em atraso'
                          : 'Previsto'),
                      trailing: Text(money(e.amount))),
                if (upcoming.occurrences.length > 12)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                          'Primeiros 12 vencimentos. Consulte Próximos meses na lista para ver os totais.')),
                if (upcoming.incomplete)
                  const Text(
                      'Projeção parcial. Revise a frequência e as datas.'),
              ],
            )),
          if (_history != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    'Registrado como ${r.paymentType == 'income' ? 'recebido' : 'pago'}: ${money(_history!.where((h) => h.action == 'paid').fold<double>(0, (s, h) => s + app.convertToMain(h.amount, h.currency)), app.settings.currency)}')),
          Text(
            'Histórico',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (_history == null)
            const Center(child: CircularProgressIndicator())
          else if (_history!.isEmpty)
            const Card(
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Ainda não há histórico.')),
              ),
            )
          else
            ..._history!.map((entry) => _HistoryTile(
                entry: entry,
                installment: !r.canSkip,
                income: r.paymentType == 'income',
                hide: app.settings.hideBalance)),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    AppProvider app,
    RecurringPayment recurring,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir recorrente?'),
        content: Text(
          '“${recurring.name}” deixará de aparecer nas previsões. Os lançamentos que já foram registrados não serão apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final undo = await app.deleteRecurringWithUndo(recurring.id);
    if (!context.mounted) return;
    Navigator.pop(context);
    showAppSnackbar(context, 'Recorrente excluído', onUndo: undo);
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final RecurringHistoryEntry entry;
  final bool installment;
  final bool income, hide;

  const _HistoryTile(
      {required this.entry,
      required this.installment,
      required this.income,
      required this.hide});

  @override
  Widget build(BuildContext context) {
    final paid = entry.action == 'paid';
    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(paid ? Icons.check_rounded : Icons.skip_next_rounded),
        ),
        title: Text(
          paid
              ? (income ? 'Registrada como recebida' : 'Registrada como paga')
              : installment
                  ? 'Parcela não paga'
                  : 'Ocorrência pulada',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(ptDate(entry.date)),
        trailing: Text(
          hide ? '••••' : formatAmount(entry.amount, entry.currency),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

/// "Não vou renovar": a reminder to cancel a few days before the next charge.
class _CancelIntentTile extends StatefulWidget {
  const _CancelIntentTile({required this.recurring});
  final RecurringPayment recurring;
  @override
  State<_CancelIntentTile> createState() => _CancelIntentTileState();
}

class _CancelIntentTileState extends State<_CancelIntentTile> {
  int? _days;
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    CancelIntents.load().then((all) {
      if (mounted) {
        setState(() {
          _days = all[widget.recurring.id];
          _loaded = true;
        });
      }
    });
  }

  Future<void> _set(int? days) async {
    await CancelIntents.set(widget.recurring.id, days);
    if (mounted) setState(() => _days = days);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(children: [
        SwitchListTile.adaptive(
            title: const Text('Não vou renovar'),
            subtitle: Text(_days == null
                ? 'Lembrar de cancelar antes da próxima cobrança'
                : 'Aviso no início $_days dia(s) antes de ${ptShortDate(widget.recurring.nextDate)}. A cobrança continua prevista até você cancelar.'),
            value: _days != null,
            onChanged: (on) => _set(on ? 3 : null)),
        if (_days != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(spacing: 8, children: [
              for (final d in [1, 3, 7])
                ChoiceChip(
                    label: Text('$d dia(s) antes'),
                    selected: _days == d,
                    onSelected: (_) => _set(d)),
            ]),
          ),
      ]),
    );
  }
}
