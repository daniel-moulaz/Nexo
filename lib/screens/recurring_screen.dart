import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import 'recurring_detail_screen.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _expenseFilter = 'subscription';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  double _monthlyValue(Iterable<RecurringPayment> items) {
    double total = 0;
    for (final r in items) {
      final freq = r.freqVal <= 0 ? 1 : r.freqVal;
      switch (r.freqUnit) {
        case 'days':
          total += r.amount * 30.44 / freq;
          break;
        case 'weeks':
          total += r.amount * 4.345 / freq;
          break;
        case 'years':
          total += r.amount / (12 * freq);
          break;
        default:
          total += r.amount / freq;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final expenses = app.recurring
        .where((r) => r.paymentType == 'expense')
        .toList()
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final incomes = app.recurring
        .where((r) => r.paymentType == 'income')
        .toList()
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final filteredExpenses =
        expenses.where((r) => r.recurringType == _expenseFilter).toList();
    final shown = _tabs.index == 0 ? filteredExpenses : incomes;
    final monthly = _monthlyValue(shown);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Recorrentes',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Receitas / despesas',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${formatAmount(_monthlyValue(incomes), app.settings.currency)} / ${formatAmount(_monthlyValue(expenses), app.settings.currency)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Despesas (${expenses.length})'),
            Tab(text: 'Receitas (${incomes.length})'),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 76),
        child: FloatingActionButton.extended(
          onPressed: () => openRecurringSheet(
            context,
            defaultType: _tabs.index == 0 ? 'expense' : 'income',
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Adicionar'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Mensal',
                    value: formatAmount(monthly, app.settings.currency),
                    icon: Icons.calendar_month_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryCard(
                    title: 'Semanal',
                    value: formatAmount(monthly / 4.345, app.settings.currency),
                    icon: Icons.date_range_outlined,
                  ),
                ),
              ],
            ),
          ),
          if (_tabs.index == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'subscription',
                    label: Text('Fixas / assinaturas'),
                    icon: Icon(Icons.autorenew_rounded),
                  ),
                  ButtonSegment(
                    value: 'installment',
                    label: Text('Parceladas'),
                    icon: Icon(Icons.payments_outlined),
                  ),
                ],
                selected: {_expenseFilter},
                onSelectionChanged: (value) {
                  setState(() => _expenseFilter = value.first);
                },
              ),
            ),
          Expanded(
            child: shown.isEmpty
                ? _EmptyRecurring(
                    isIncome: _tabs.index == 1,
                    installment: _expenseFilter == 'installment',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 150),
                    itemCount: shown.length,
                    itemBuilder: (_, index) => _RecurringTile(
                      recurring: shown[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: cs.primary),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecurring extends StatelessWidget {
  final bool isIncome;
  final bool installment;

  const _EmptyRecurring({
    required this.isIncome,
    required this.installment,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = isIncome
        ? 'Nenhuma receita recorrente'
        : installment
            ? 'Nenhuma compra parcelada'
            : 'Nenhuma despesa fixa';
    final subtitle = isIncome
        ? 'Cadastre salário, aluguel recebido ou outra entrada que se repete.'
        : installment
            ? 'Use parceladas para compromissos com quantidade definida.'
            : 'Cadastre assinaturas, internet, aluguel e outras contas fixas.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.repeat_rounded,
              size: 62,
              color: cs.onSurfaceVariant.withValues(alpha: .35),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  final RecurringPayment recurring;

  const _RecurringTile({required this.recurring});

  String _frequency() {
    final n = recurring.freqVal <= 0 ? 1 : recurring.freqVal;
    if (n == 1) {
      switch (recurring.freqUnit) {
        case 'days':
          return 'Diária';
        case 'weeks':
          return 'Semanal';
        case 'years':
          return 'Anual';
        default:
          return 'Mensal';
      }
    }
    final unit = switch (recurring.freqUnit) {
      'days' => 'dias',
      'weeks' => 'semanas',
      'years' => 'anos',
      _ => 'meses',
    };
    return 'A cada $n $unit';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final account = app.accountById(recurring.accountId);
    final category = app.categoryById(recurring.categoryId);
    final currency = account?.currency ?? app.settings.currency;
    final today = DateTime.now();
    final now = DateTime(today.year, today.month, today.day);
    final due = DateTime(
      recurring.nextDate.year,
      recurring.nextDate.month,
      recurring.nextDate.day,
    );
    final days = due.difference(now).inDays;
    final overdue = days < 0;
    final total = recurring.totalPayments;
    final progress = total != null && total > 0
        ? (recurring.paidPayments / total).clamp(0.0, 1.0)
        : null;

    final dueLabel = overdue
        ? 'Atrasada há ${days.abs()} dia${days.abs() == 1 ? '' : 's'}'
        : days == 0
            ? 'Vence hoje'
            : 'Vence em $days dia${days == 1 ? '' : 's'}';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          ExpensyRoute(
            builder: (_) => RecurringDetailScreen(
              recurring: recurring,
              fmt: (value) => formatAmount(value, currency),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: category == null
                        ? cs.primaryContainer
                        : Color(category.colorValue).withValues(alpha: .16),
                    child: Icon(
                      recurring.paymentType == 'income'
                          ? Icons.south_west_rounded
                          : recurring.recurringType == 'installment'
                              ? Icons.payments_outlined
                              : Icons.autorenew_rounded,
                      color: category == null
                          ? cs.primary
                          : Color(category.colorValue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recurring.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (account != null) account.name,
                            if (category != null) category.name,
                            _frequency(),
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatAmount(recurring.amount, currency),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        dueLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: overdue ? cs.error : cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: progress, minHeight: 5),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${recurring.paidPayments}/$total • ${(progress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: recurring.endDate != null &&
                            recurring.nextDate.isAfter(recurring.endDate!)
                        ? null
                        : () async {
                            await app.skipNextRecurring(recurring);
                          },
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: const Text('Pular'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonalIcon(
                    onPressed: recurring.endDate != null &&
                            recurring.nextDate.isAfter(recurring.endDate!)
                        ? null
                        : () async {
                            await app.markRecurringPaid(recurring);
                          },
                    icon: Icon(
                      recurring.paymentType == 'income'
                          ? Icons.check_rounded
                          : Icons.done_all_rounded,
                      size: 18,
                    ),
                    label: Text(
                      recurring.paymentType == 'income' ? 'Recebida' : 'Paga',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void openRecurringSheet(
  BuildContext context, {
  RecurringPayment? existing,
  String defaultType = 'expense',
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RecurringEditor(
      existing: existing,
      defaultType: defaultType,
    ),
  );
}

class _RecurringEditor extends StatefulWidget {
  final RecurringPayment? existing;
  final String defaultType;

  const _RecurringEditor({
    this.existing,
    required this.defaultType,
  });

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _frequencyCtrl = TextEditingController(text: '1');
  final _installmentsCtrl = TextEditingController(text: '12');
  final _notesCtrl = TextEditingController();

  late String _type;
  String _recurringType = 'subscription';
  String _frequencyUnit = 'months';
  DateTime _firstDate = DateTime.now();
  String? _accountId;
  String? _categoryId;
  bool _reminder = false;
  bool _earlyReminder = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);
  bool _submitted = false;
  bool _saving = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _type = widget.defaultType;
    final app = context.read<AppProvider>();
    final accounts = app.accounts.where((a) => !a.isGold).toList();
    if (accounts.isNotEmpty) _accountId = accounts.first.id;
    final categories = app.categories.where((c) => c.type == _type).toList();
    if (categories.isNotEmpty) _categoryId = categories.first.id;

    final e = widget.existing;
    if (e != null) {
      _type = e.paymentType;
      _recurringType = e.recurringType;
      _nameCtrl.text = e.name;
      _amountCtrl.text = e.amount.toStringAsFixed(2).replaceAll('.', ',');
      _frequencyCtrl.text = '${e.freqVal}';
      _frequencyUnit = e.freqUnit;
      _firstDate = e.startDate;
      _accountId = e.accountId;
      _categoryId = e.categoryId;
      _reminder = e.reminderEnabled;
      _earlyReminder = e.earlyReminderEnabled;
      _notesCtrl.text = e.notes;
      final parts = e.reminderTime.split(':');
      _reminderTime = TimeOfDay(
        hour: int.tryParse(parts.firstOrNull ?? '') ?? 9,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      );
      if (e.recurringType == 'installment') {
        _installmentsCtrl.text = '${e.totalPayments ?? 1}';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _frequencyCtrl.dispose();
    _installmentsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _setType(String type) {
    final app = context.read<AppProvider>();
    final categories = app.categories.where((c) => c.type == type).toList();
    setState(() {
      _type = type;
      _categoryId = categories.firstOrNull?.id;
      if (type == 'income') _recurringType = 'subscription';
    });
  }

  DateTime _addPeriods(DateTime start, int count) {
    if (count <= 0) return start;
    final freq = int.tryParse(_frequencyCtrl.text) ?? 1;
    final steps = count * (freq <= 0 ? 1 : freq);
    switch (_frequencyUnit) {
      case 'days':
        return start.add(Duration(days: steps));
      case 'weeks':
        return start.add(Duration(days: steps * 7));
      case 'years':
        return DateTime(start.year + steps, start.month, start.day);
      default:
        final targetMonth = start.month + steps;
        final year = start.year + (targetMonth - 1) ~/ 12;
        final month = ((targetMonth - 1) % 12) + 1;
        final maxDay = DateTime(year, month + 1, 0).day;
        return DateTime(year, month, start.day.clamp(1, maxDay));
    }
  }

  Future<void> _toggleReminder(bool enabled) async {
    if (!enabled) {
      setState(() => _reminder = false);
      return;
    }
    final service = NotificationService();
    final allowed =
        await service.hasPermission() || await service.requestPermissions();
    if (!mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permita notificações para ativar lembretes.')),
      );
      return;
    }
    setState(() => _reminder = true);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final amount = parseMoney(_amountCtrl.text);
    final frequency = int.tryParse(_frequencyCtrl.text.trim());
    final installments = int.tryParse(_installmentsCtrl.text.trim());

    final validInstallments = _type != 'expense' ||
        _recurringType != 'installment' ||
        (installments != null && installments > 0);
    if (_nameCtrl.text.trim().isEmpty ||
        amount == null ||
        amount <= 0 ||
        frequency == null ||
        frequency <= 0 ||
        _accountId == null ||
        _categoryId == null ||
        !validInstallments) {
      final errors = <String>[
        if (_nameCtrl.text.trim().isEmpty) 'descrição',
        if (amount == null || amount <= 0) 'valor',
        if (frequency == null || frequency <= 0) 'frequência',
        if (_accountId == null) 'conta',
        if (_categoryId == null) 'categoria',
        if (!validInstallments) 'quantidade de parcelas',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Revise: ${errors.join(', ')}.')));
      return;
    }

    setState(() => _saving = true);
    final app = context.read<AppProvider>();
    final existing = widget.existing;
    final count = _recurringType == 'installment' ? installments! : null;
    final endDate = count == null ? null : _addPeriods(_firstDate, count - 1);
    final reminderText =
        '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}';

    final recurring = RecurringPayment(
      id: existing?.id ?? app.newId(),
      name: _nameCtrl.text.trim(),
      accountId: _accountId!,
      categoryId: _categoryId!,
      amount: amount,
      paymentType: _type,
      recurringType: _type == 'expense' ? _recurringType : 'subscription',
      freqVal: frequency,
      freqUnit: _frequencyUnit,
      startDate: _firstDate,
      nextDate: existing == null || existing.paidPayments == 0
          ? _firstDate
          : existing.nextDate,
      endDate: endDate,
      paidPayments: existing?.paidPayments ?? 0,
      reminderEnabled: _reminder,
      reminderTime: reminderText,
      earlyReminderEnabled: _reminder && _earlyReminder,
      notes: _notesCtrl.text.trim(),
    );

    try {
      if (existing == null) {
        await app.addRecurring(recurring);
      } else {
        await app.updateRecurring(recurring);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Não foi possível salvar o recorrente. Tente novamente.')));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts = app.accounts.where((a) => !a.isGold).toList();
    final categories = app.categories.where((c) => c.type == _type).toList();
    final amount = parseMoney(_amountCtrl.text);
    final frequency = int.tryParse(_frequencyCtrl.text.trim());
    final installments = int.tryParse(_installmentsCtrl.text.trim());

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Editar recorrente' : 'Novo recorrente',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'expense',
                        label: Text('Despesa'),
                        icon: Icon(Icons.north_east_rounded),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text('Receita'),
                        icon: Icon(Icons.south_west_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (value) => _setType(value.first),
                  ),
                  if (_type == 'expense') ...[
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'subscription',
                          label: Text('Fixa/assinatura'),
                          icon: Icon(Icons.autorenew_rounded),
                        ),
                        ButtonSegment(
                          value: 'installment',
                          label: Text('Parcelada'),
                          icon: Icon(Icons.payments_outlined),
                        ),
                      ],
                      selected: {_recurringType},
                      onSelectionChanged: (value) {
                        setState(() => _recurringType = value.first);
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Ex.: Internet, salário, Netflix...',
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                      errorText: _submitted && _nameCtrl.text.trim().isEmpty
                          ? 'Informe uma descrição.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Valor por ocorrência',
                      prefixText:
                          '${currencyInfo(app.settings.currency).symbol} ',
                      errorText: _submitted && (amount == null || amount <= 0)
                          ? 'Informe um valor válido.'
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _frequencyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'A cada',
                            errorText: _submitted &&
                                    (frequency == null || frequency <= 0)
                                ? 'Inválido'
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _frequencyUnit,
                          decoration:
                              const InputDecoration(labelText: 'Período'),
                          items: const [
                            DropdownMenuItem(
                                value: 'days', child: Text('dia(s)')),
                            DropdownMenuItem(
                                value: 'weeks', child: Text('semana(s)')),
                            DropdownMenuItem(
                                value: 'months', child: Text('mês(es)')),
                            DropdownMenuItem(
                                value: 'years', child: Text('ano(s)')),
                          ],
                          onChanged: (value) {
                            if (value != null)
                              setState(() => _frequencyUnit = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_type == 'expense' &&
                      _recurringType == 'installment') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _installmentsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Quantidade de parcelas',
                        hintText: 'Ex.: 12',
                        prefixIcon:
                            const Icon(Icons.format_list_numbered_rounded),
                        errorText: _submitted &&
                                (installments == null || installments <= 0)
                            ? 'Informe a quantidade de parcelas.'
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Primeira ocorrência'),
                    subtitle: Text(ptDate(_firstDate)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _firstDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2140),
                        cancelText: 'Cancelar',
                        confirmText: 'Selecionar',
                      );
                      if (picked != null) setState(() => _firstDate = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conta',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  if (accounts.isEmpty)
                    const _MissingDataCard(
                      icon: Icons.account_balance_wallet_outlined,
                      text: 'Cadastre uma conta antes de criar um recorrente.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: accounts.any((a) => a.id == _accountId)
                          ? _accountId
                          : null,
                      decoration: InputDecoration(
                        labelText: _type == 'income'
                            ? 'Onde o dinheiro entra'
                            : 'De onde sai o dinheiro',
                        errorText: _submitted && _accountId == null
                            ? 'Escolha uma conta.'
                            : null,
                      ),
                      items: accounts
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _accountId = value),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    'Categoria',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  if (categories.isEmpty)
                    _MissingDataCard(
                      icon: Icons.category_outlined,
                      text: _type == 'income'
                          ? 'Cadastre uma categoria de receita.'
                          : 'Cadastre uma categoria de despesa.',
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories.map((category) {
                        return ChoiceChip(
                          selected: _categoryId == category.id,
                          label: Text(category.name),
                          avatar: CircleAvatar(
                            radius: 4,
                            backgroundColor: Color(category.colorValue),
                          ),
                          onSelected: (_) =>
                              setState(() => _categoryId = category.id),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lembrete no vencimento'),
                    subtitle: Text(
                      _reminder
                          ? 'Avisar às ${_reminderTime.format(context)}'
                          : 'Receba uma notificação quando chegar a data.',
                    ),
                    value: _reminder,
                    onChanged: _toggleReminder,
                  ),
                  if (_reminder) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time_rounded),
                      title: const Text('Horário do lembrete'),
                      trailing: Text(
                        _reminderTime.format(context),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _reminderTime,
                        );
                        if (picked != null)
                          setState(() => _reminderTime = picked);
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Avisar também 2 dias antes'),
                      value: _earlyReminder,
                      onChanged: (value) =>
                          setState(() => _earlyReminder = value),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Observação (opcional)',
                      prefixIcon: Icon(Icons.sticky_note_2_outlined),
                    ),
                  ),
                  if (_type == 'expense' &&
                      _recurringType == 'installment' &&
                      installments != null &&
                      installments > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$installments parcelas • termina em ${ptDate(_addPeriods(_firstDate, installments - 1))}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(isEdit ? Icons.save_outlined : Icons.check_rounded),
                label: Text(isEdit ? 'Salvar alterações' : 'Salvar recorrente'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingDataCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MissingDataCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.error),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
