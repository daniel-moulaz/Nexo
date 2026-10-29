import '../database/db_helper.dart';
import '../investments/investment_repository.dart';
import '../models/models.dart';
import '../models/transaction_metadata.dart';
import '../providers/app_provider.dart';
import '../services/budget_insights.dart';
import '../services/envelopes.dart';
import '../services/import_rules_service.dart';
import '../services/pluggy_inbox.dart';
import '../widgets/shared_widgets.dart' show kCategoryIconOptions;
import 'assistant_settings.dart';

/// Assistant requests that bring the connector to parity with the screens
/// (29/10/2026): kinds of spending, settings, category edits and merges,
/// full and batch edits of entries, budgets counted in full, card details,
/// bookkeeping-only goals, recurring details, investments, loans, people,
/// automatic category rules and Open Finance. Each one goes through the same
/// provider, repository or ledger call as the screens; creations use ids
/// fixed by the request, so applying a request twice changes nothing.
class AssistantParityCommands {
  AssistantParityCommands(this.app, {InvestmentRepository? investments})
      : investments = investments ?? InvestmentRepository();
  final AppProvider app;
  final InvestmentRepository investments;

  /// Every kind handled here; the server lists the same ones.
  static const kinds = [
    'category.envelope', 'category.edit', 'category.merge', //
    'settings.set', 'transaction.create', 'transaction.edit',
    'transaction.bulk_update',
    'transaction.bulk_delete', 'transaction.neutralize', 'transaction.split',
    'budget.save', 'account.edit', 'goal.adjust', 'goal.edit',
    'recurring.edit', 'investment.archive', 'investment.unrecord',
    'investment.link', 'loan.add', 'loan.edit', 'loan.delete', 'loan.unpay',
    'lended.edit', 'lended.delete', 'person.edit', 'person.delete',
    'rule.save', 'rule.delete', 'suggestion.transfer', 'suggestion.accept',
    'bank.refresh',
  ];

  static double _reais(Object? cents) => (cents as num).toInt() / 100;
  static DateTime _day(Object? iso, [DateTime? keepTime]) {
    final d = DateTime.parse(iso as String);
    return DateTime(
        d.year, d.month, d.day, keepTime?.hour ?? 12, keepTime?.minute ?? 0);
  }

  static List<String> _ids(Object? v) {
    if (v is! List || v.isEmpty || v.any((e) => e is! String)) {
      throw ArgumentError('Lista de ids vazia ou inválida.');
    }
    return List<String>.from(v).toSet().toList();
  }

  Account _account(Object? id) =>
      app.accountById(id as String? ?? '') ??
      (throw StateError('A conta não existe mais no Nexo.'));

  AppCategory _category(Object? id) =>
      app.categories.where((c) => c.id == id).firstOrNull ??
      (throw StateError('A categoria não existe mais no Nexo.'));

  String? _envelope(Object? v) {
    if (v == null) return null;
    if (envelopeById(v as String) == null) {
      throw ArgumentError('Tipo de gasto desconhecido: $v.');
    }
    return v;
  }

  Future<AppTransaction> _transaction(Object? id) async {
    for (final t in await DBHelper.getTransactions()) {
      if (t.id == id) return t;
    }
    throw StateError('O lançamento não existe mais.');
  }

  /// Null when [kind] is not one of these requests.
  Future<Map<String, Object?>?> handle(
      String commandId, String kind, Map<String, dynamic> a) async {
    switch (kind) {
      // ── Kinds of spending, settings and categories ──────────────────────
      case 'category.envelope':
        final list = (a['assignments'] as List?) ??
            (throw ArgumentError('Nada para classificar.'));
        final changes = <(AppCategory, String?)>[];
        for (final item in list.cast<Map>()) {
          final c = _category(item['id']);
          if (c.type != 'expense') {
            throw StateError('${c.name} é de receita; só despesas têm tipo.');
          }
          changes.add((c, _envelope(item['envelope'])));
        }
        for (final (c, envelope) in changes) {
          if (c.envelope == envelope) continue;
          await app.updateCategory(
              c.copyWith(envelope: envelope, clearEnvelope: envelope == null));
        }
        return {
          'message': '${changes.length} categoria(s) classificada(s).',
        };
      case 'category.edit':
        final c = _category(a['id']);
        final icon = a['icon'] as int?;
        if (icon != null && (icon < 1 || icon > kCategoryIconOptions.length)) {
          throw ArgumentError('Ícone inválido.');
        }
        final hasEnvelope = a.containsKey('envelope');
        final envelope = hasEnvelope ? _envelope(a['envelope']) : null;
        if (hasEnvelope && envelope != null && c.type != 'expense') {
          throw StateError('Só categorias de despesa têm tipo de gasto.');
        }
        final name = (a['name'] as String?)?.trim();
        if (name != null &&
            app.categories.any((x) =>
                x.id != c.id &&
                x.type == c.type &&
                x.name.toLowerCase() == name.toLowerCase())) {
          throw StateError('Já existe uma categoria com esse nome.');
        }
        await app.updateCategory(c.copyWith(
            name: name,
            colorValue: a['color'] as int?,
            iconCodePoint: icon,
            envelope: envelope,
            clearEnvelope: hasEnvelope && envelope == null));
        return {'category_id': c.id, 'message': 'Categoria alterada.'};
      case 'category.merge':
        final from = _category(a['from_id']);
        final into = _category(a['into_id']);
        final moved = await app.mergeCategory(from.id, into.id);
        return {
          'category_id': into.id,
          'message':
              '${from.name} juntada a ${into.name}: $moved lançamento(s) movido(s).',
        };
      case 'settings.set':
        final values = (a['values'] as Map?)?.cast<String, Object?>() ??
            (throw ArgumentError('Nenhuma configuração informada.'));
        final goals = app.savingsGoals.map((g) => g.id).toSet();
        final checked = {
          for (final e in values.entries)
            e.key: validateAssistantSetting(e.key, e.value, goalIds: goals)
        };
        await app.updateSettings(checked);
        return {
          'message': 'Configuração salva: ${checked.keys.join(', ')}.',
          'shared': [
            for (final k in checked.keys)
              if (assistantSetting(k)!.shared) k
          ],
        };

      // ── Entries ─────────────────────────────────────────────────────────
      case 'transaction.create':
        // Like the form: subcategory, pending with due date, one-off spending
        // and installments (the total split in monthly parts).
        final id = 'assistant:$commandId';
        if (app.transactions.any((t) => t.id == id) ||
            (await DBHelper.getTransactions()).any((t) => t.id == id)) {
          return {'transaction_id': id, 'message': 'Já estava lançado.'};
        }
        final account = _account(a['account_id']);
        final c = _category(a['category_id']);
        final type = a['type'] as String;
        if (c.type != type) throw StateError('A categoria é de outro tipo.');
        final date = _day(a['date']);
        final status = a['status'] as String? ?? 'paid';
        if (!['paid', 'pending'].contains(status)) {
          throw ArgumentError('Situação inválida.');
        }
        final installments = (a['installments'] as num?)?.toInt();
        await app.addTransaction(
            AppTransaction(
                id: id,
                type: type,
                amount: _reais(a['amount_cents']),
                description: (a['description'] as String).trim(),
                accountId: account.id,
                categoryId: c.id,
                date: date,
                note: a['note'] as String? ?? '',
                currency: account.currency),
            metadata: TransactionMetadata(
                transactionId: id,
                subcategory: (a['subcategory'] as String?)?.trim() ?? '',
                status: status,
                dueDate: status == 'pending'
                    ? (a['due_date'] == null ? date : _day(a['due_date']))
                    : null,
                expenseClass: a['expense_class'] as String? ?? 'normal',
                source: 'assistant'));
        if (installments != null && installments > 1) {
          await app.splitTransaction(id, installments);
        }
        return {
          'transaction_id': id,
          'message': installments != null && installments > 1
              ? 'Lançado em $installments parcelas.'
              : 'Lançado.',
        };
      case 'transaction.edit':
        final original = await _transaction(a['id']);
        final old = app.transactionMetadata[original.id] ??
            TransactionMetadata(transactionId: original.id);
        final type = a['type'] as String? ?? original.type;
        if (!['expense', 'income'].contains(type)) {
          throw ArgumentError('Tipo inválido.');
        }
        final account = a.containsKey('account_id')
            ? _account(a['account_id'])
            : app.accountById(original.accountId);
        final categoryId = a['category_id'] as String? ?? original.categoryId;
        if (a.containsKey('category_id') || a.containsKey('type')) {
          final c = _category(categoryId);
          if (c.type != type) {
            throw StateError(
                'A categoria ${c.name} é de ${c.type == 'income' ? 'receita' : 'despesa'}.');
          }
        }
        final status = a['status'] as String? ?? old.status;
        if (!['paid', 'pending'].contains(status)) {
          throw ArgumentError('Situação inválida.');
        }
        final expenseClass = a['expense_class'] as String? ?? old.expenseClass;
        if (!['normal', 'extraordinary'].contains(expenseClass)) {
          throw ArgumentError('Classe de gasto inválida.');
        }
        final date = a.containsKey('date')
            ? _day(a['date'], original.date)
            : original.date;
        final DateTime? due = a.containsKey('due_date')
            ? (a['due_date'] == null ? null : _day(a['due_date']))
            : status == 'pending'
                ? old.dueDate ?? date
                : old.dueDate;
        final recurringIncome = a['recurring_income_id'] as String?;
        if (recurringIncome != null &&
            !app.recurring.any(
                (r) => r.id == recurringIncome && r.paymentType == 'income')) {
          throw StateError('A receita recorrente não existe mais.');
        }
        await app.updateTransaction(
            AppTransaction(
                id: original.id,
                type: type,
                amount: a.containsKey('amount_cents')
                    ? _reais(a['amount_cents'])
                    : original.amount,
                description: (a['description'] as String?)?.trim() ??
                    original.description,
                accountId: account?.id ?? original.accountId,
                categoryId: categoryId,
                date: date,
                note: a['note'] as String? ?? original.note,
                currency: a.containsKey('account_id')
                    ? account!.currency
                    : original.currency),
            original,
            metadata: TransactionMetadata(
                transactionId: original.id,
                subcategory:
                    (a['subcategory'] as String?)?.trim() ?? old.subcategory,
                status: status,
                dueDate: due,
                expenseClass: expenseClass,
                excludeFromSpending: old.excludeFromSpending,
                installmentCurrent: old.installmentCurrent,
                installmentTotal: old.installmentTotal,
                source: recurringIncome != null
                    ? 'recurring:$recurringIncome'
                    : old.source,
                affectsBalance: old.affectsBalance));
        return {
          'transaction_id': original.id,
          'message': 'Lançamento alterado.'
        };
      case 'transaction.bulk_update':
        final ids = _ids(a['ids']);
        if (a['category_id'] != null) _category(a['category_id']);
        final n = await app.updateTransactionsBulk(ids,
            categoryId: a['category_id'] as String?,
            subcategory: a['subcategory'] as String?,
            expenseClass: a['expense_class'] as String?);
        return {'count': n, 'message': '$n lançamento(s) alterado(s).'};
      case 'transaction.bulk_delete':
        final n = await app.deleteTransactions(_ids(a['ids']));
        return {'count': n, 'message': '$n lançamento(s) apagado(s).'};
      case 'transaction.neutralize':
        final n = await app.markAsBalanceAdjustment(_ids(a['ids']));
        return {
          'count': n,
          'message':
              '$n lançamento(s) agora são ajuste de saldo: não contam como receita nem gasto.',
        };
      case 'transaction.split':
        final t = await _transaction(a['id']);
        final n = (a['installments'] as num).toInt();
        await app.splitTransaction(t.id, n);
        return {'transaction_id': t.id, 'message': 'Dividido em $n parcelas.'};

      // ── Budgets, accounts, goals, recurring ─────────────────────────────
      case 'budget.save':
        final c = _category(a['category_id']);
        if (c.type != 'expense') {
          throw StateError('Orçamento é só para categorias de despesa.');
        }
        final period = a['period'] as String? ?? 'monthly';
        if (!['monthly', 'weekly'].contains(period)) {
          throw ArgumentError('Período inválido.');
        }
        final existing = a['id'] != null
            ? (app.budgets.where((b) => b.id == a['id']).firstOrNull ??
                (throw StateError('O orçamento não existe mais.')))
            : app.budgetForCategory(c.id);
        final now = DateTime.now();
        // "Cheio" counts the whole current period: the budget starts on its
        // first day. Otherwise it keeps its date (or starts today, if new).
        final full = a['full_period'] as bool?;
        DateTime created = existing?.createdAt ?? now;
        if (full == true) {
          created = budgetWindow(
                  Budget(
                      id: '',
                      categoryId: c.id,
                      amount: 1,
                      period: period,
                      createdAt: now),
                  now,
                  weekStart: app.settings.weekStart)
              .start;
        } else if (full == false) {
          created = now;
        }
        final budget = Budget(
            id: existing?.id ?? 'assistant-budget:$commandId',
            categoryId: c.id,
            amount: _reais(a['amount_cents'] ?? (existing!.amount * 100)),
            period: period,
            createdAt: created);
        if (existing != null) {
          await app.updateBudget(budget);
        } else if (!app.budgets.any((b) => b.id == budget.id)) {
          await app.addBudget(budget);
        }
        return {
          'budget_id': budget.id,
          'message':
              existing == null ? 'Orçamento criado.' : 'Orçamento alterado.',
          'limit_now': app.budgetLimit(budget),
        };
      case 'account.edit':
        final acc = _account(a['id']);
        final credit = acc.type == 'credit';
        if (!credit &&
            [
              'statement_day',
              'due_day',
              'credit_limit_cents',
              'min_payment_cents',
              'min_payment_percent',
              'reminder_enabled',
              'reminder_time',
              'linked_account_id'
            ].any(a.containsKey)) {
          throw StateError('Esses campos são só de cartão de crédito.');
        }
        if (a['linked_account_id'] != null) {
          final linked = _account(a['linked_account_id']);
          if (linked.type == 'credit' || linked.id == acc.id) {
            throw StateError(
                'A conta de pagamento deve ser uma conta, não um cartão.');
          }
        }
        double? reais(String key) => a[key] == null ? null : _reais(a[key]);
        await app.updateAccount(
            Account(
                id: acc.id,
                name: (a['name'] as String?)?.trim() ?? acc.name,
                type: acc.type,
                balance: acc.balance,
                currency: acc.currency,
                colorValue: a['color'] as int? ?? acc.colorValue,
                excludeFromTotal:
                    a['exclude_from_total'] as bool? ?? acc.excludeFromTotal,
                excludeFromBankTotal: a['exclude_from_bank_total'] as bool? ??
                    acc.excludeFromBankTotal,
                createdAt: acc.createdAt,
                goldKarat: acc.goldKarat,
                goldGrams: acc.goldGrams,
                cardHolderName: acc.cardHolderName,
                cardNumberLast4: acc.cardNumberLast4,
                cardExpiry: acc.cardExpiry,
                statementDay: a.containsKey('statement_day')
                    ? a['statement_day'] as int?
                    : acc.statementDay,
                dueDay: a.containsKey('due_day')
                    ? a['due_day'] as int?
                    : acc.dueDay,
                creditLimit: a.containsKey('credit_limit_cents')
                    ? reais('credit_limit_cents')
                    : acc.creditLimit,
                minPaymentAmount: a.containsKey('min_payment_cents')
                    ? reais('min_payment_cents')
                    : acc.minPaymentAmount,
                minPaymentPercent: a.containsKey('min_payment_percent')
                    ? (a['min_payment_percent'] as num?)?.toDouble()
                    : acc.minPaymentPercent,
                creditReminderEnabled:
                    a['reminder_enabled'] as bool? ?? acc.creditReminderEnabled,
                creditReminderTime:
                    a['reminder_time'] as String? ?? acc.creditReminderTime,
                creditEarlyReminderEnabled: acc.creditEarlyReminderEnabled,
                linkedAccountId: a.containsKey('linked_account_id')
                    ? a['linked_account_id'] as String?
                    : acc.linkedAccountId,
                orderIndex: acc.orderIndex),
            original: acc);
        return {'account_id': acc.id, 'message': 'Conta alterada.'};
      case 'goal.adjust':
        if (!app.savingsGoals.any((g) => g.id == a['goal_id'])) {
          throw StateError('O objetivo não existe mais.');
        }
        final deposit = a['direction'] == 'deposit';
        await app.adjustGoal(
            goalId: a['goal_id'] as String,
            amount: _reais(a['amount_cents']),
            deposit: deposit,
            note: a['note'] as String? ?? '');
        return {
          'message': deposit
              ? 'Somado ao objetivo, sem mexer em conta.'
              : 'Tirado do objetivo, sem mexer em conta.'
        };
      case 'goal.edit':
        final g = app.savingsGoals.where((g) => g.id == a['id']).firstOrNull ??
            (throw StateError('O objetivo não existe mais.'));
        final completed = a['completed'] as bool?;
        await app.updateSavingsGoal(g.copyWith(
            name: (a['name'] as String?)?.trim(),
            targetAmount:
                a['target_cents'] == null ? null : _reais(a['target_cents']),
            targetDate:
                a['target_date'] == null ? null : _day(a['target_date']),
            clearTargetDate:
                a.containsKey('target_date') && a['target_date'] == null,
            colorValue: a['color'] as int?,
            isCompleted: completed,
            completedAt: completed == true ? DateTime.now() : null,
            clearCompletedAt: completed == false));
        return {'goal_id': g.id, 'message': 'Objetivo alterado.'};
      case 'recurring.edit':
        final r = app.recurring.where((r) => r.id == a['id']).firstOrNull ??
            (throw StateError('A recorrente não existe mais.'));
        final next = RecurringPayment.fromMap(r.toMap(),
            skippedOccurrences: r.skippedOccurrences);
        if (a['name'] != null) next.name = (a['name'] as String).trim();
        if (a['amount_cents'] != null) next.amount = _reais(a['amount_cents']);
        if (a['account_id'] != null) {
          next.accountId = _account(a['account_id']).id;
        }
        if (a['category_id'] != null) {
          final c = _category(a['category_id']);
          if (c.type != next.paymentType) {
            throw StateError('A categoria é de outro tipo.');
          }
          next.categoryId = c.id;
        }
        if (a['next_date'] != null) next.nextDate = _day(a['next_date']);
        if (a.containsKey('end_date')) {
          next.endDate = a['end_date'] == null ? null : _day(a['end_date']);
        }
        if (a['freq_unit'] != null) {
          if (!['days', 'weeks', 'months', 'years'].contains(a['freq_unit'])) {
            throw ArgumentError('Frequência inválida.');
          }
          next.freqUnit = a['freq_unit'] as String;
        }
        if (a['freq_val'] != null)
          next.freqVal = (a['freq_val'] as num).toInt();
        if (a['kind'] != null) {
          if (!['subscription', 'installment'].contains(a['kind'])) {
            throw ArgumentError('Tipo de recorrente inválido.');
          }
          next.recurringType = a['kind'] as String;
        }
        if (a['notes'] != null) next.notes = a['notes'] as String;
        if (a['reminder_enabled'] != null) {
          next.reminderEnabled = a['reminder_enabled'] as bool;
        }
        if (a['reminder_time'] != null) {
          next.reminderTime = a['reminder_time'] as String;
        }
        if (next.recurringType == 'installment' && next.endDate == null) {
          throw StateError('Parcelamento precisa de data final.');
        }
        await app.updateRecurring(next);
        return {'recurring_id': r.id, 'message': 'Recorrente alterada.'};

      // ── Investments ─────────────────────────────────────────────────────
      case 'investment.archive':
        await investments.archive(a['id'] as String,
            archived: a['archived'] as bool? ?? true);
        await app.refreshInvestmentCash();
        return {
          'message': a['archived'] == false
              ? 'De volta à carteira.'
              : 'Retirado da carteira (histórico mantido).'
        };
      case 'investment.unrecord':
        final id = a['operation_id'] as String;
        if (!(await investments.load())
            .any((p) => p.operations.any((e) => e.id == id))) {
          return {'message': 'A operação já não existia.'};
        }
        await investments.removeOperation(id);
        await app.refreshInvestmentCash();
        return {
          'message': 'Operação apagada; a conta vinculada foi estornada.'
        };
      case 'investment.link':
        final account = _account(a['account_id']);
        await investments.linkCash(a['operation_id'] as String, account.id);
        await app.refreshInvestmentCash();
        return {'message': 'Operação vinculada a ${account.name}.'};

      // ── Loans, money lent, people ───────────────────────────────────────
      case 'loan.add':
        final id = 'assistant-loan:$commandId';
        if (app.loans.any((l) => l.id == id)) {
          return {'loan_id': id, 'message': 'Já estava cadastrado.'};
        }
        await app.addLoan(_loan(id, a, null));
        return {'loan_id': id, 'message': 'Empréstimo cadastrado.'};
      case 'loan.edit':
        final loan = app.loans.where((l) => l.id == a['id']).firstOrNull ??
            (throw StateError('O empréstimo não existe mais.'));
        await app.updateLoan(_loan(loan.id, a, loan));
        return {'loan_id': loan.id, 'message': 'Empréstimo alterado.'};
      case 'loan.delete':
        final id = a['id'] as String;
        if (!app.loans.any((l) => l.id == id)) {
          return {'loan_id': id, 'message': 'Já não existia.'};
        }
        await app.deleteLoan(id);
        return {'loan_id': id, 'message': 'Empréstimo excluído.'};
      case 'loan.unpay':
        final id = a['payment_id'] as String;
        if (!app.loanPayments.any((p) => p.id == id)) {
          return {'message': 'O pagamento já não existia.'};
        }
        await app.deleteLoanPayment(id);
        return {'message': 'Pagamento apagado; a conta foi estornada.'};
      case 'lended.edit':
        final l = app.lended.where((l) => l.id == a['id']).firstOrNull ??
            (throw StateError('O registro não existe mais.'));
        await app.updateLended(
            l.copyWith(
                amount: a['amount_cents'] == null
                    ? null
                    : _reais(a['amount_cents']),
                dueDate: a['due_date'] == null ? null : _day(a['due_date']),
                clearDueDate:
                    a.containsKey('due_date') && a['due_date'] == null,
                notes: a['notes'] as String?),
            l);
        return {'lended_id': l.id, 'message': 'Registro alterado.'};
      case 'lended.delete':
        final id = a['id'] as String;
        if (!app.lended.any((l) => l.id == id)) {
          return {'lended_id': id, 'message': 'Já não existia.'};
        }
        await app.deleteLended(id);
        return {'lended_id': id, 'message': 'Registro excluído.'};
      case 'person.edit':
        final p = app.lendedPeople.where((p) => p.id == a['id']).firstOrNull ??
            (throw StateError('A pessoa não existe mais.'));
        await app.updateLendedPerson(p.copyWith(
            name: (a['name'] as String?)?.trim(),
            notes: a['notes'] as String?));
        return {'person_id': p.id, 'message': 'Pessoa alterada.'};
      case 'person.delete':
        final id = a['id'] as String;
        if (!app.lendedPeople.any((p) => p.id == id)) {
          return {'person_id': id, 'message': 'Já não existia.'};
        }
        if (app.lended.any((l) => l.personId == id && !l.isSettled)) {
          throw StateError(
              'Há valores em aberto com essa pessoa. Quite ou exclua antes.');
        }
        await app.deleteLendedPerson(id);
        return {'person_id': id, 'message': 'Pessoa excluída.'};

      // ── Automatic category rules and Open Finance ───────────────────────
      case 'rule.save':
        final id = a['id'] as String? ?? 'assistant-rule:$commandId';
        final c = _category(a['category_id']);
        await ImportRulesService.save(ImportRule(
            id: id,
            pattern: a['pattern'] as String,
            type: a['type'] as String? ?? c.type,
            categoryId: c.id,
            subcategory: a['subcategory'] as String? ?? ''));
        return {'rule_id': id, 'message': 'Regra salva.'};
      case 'rule.delete':
        await ImportRulesService.delete(a['id'] as String);
        return {'rule_id': a['id'], 'message': 'Regra excluída.'};
      case 'suggestion.transfer':
      case 'suggestion.accept':
        return _suggestion(kind, a);
      case 'bank.refresh':
        final inbox = PluggyInbox.instance;
        if (inbox == null) {
          throw StateError('Open Finance não está ativo neste aparelho.');
        }
        await inbox.sync();
        return {
          'message':
              'Leitura pedida aos bancos. O Open Finance atualiza no máximo uma vez por hora.'
        };
    }
    return null;
  }

  Loan _loan(String id, Map<String, dynamic> a, Loan? old) {
    String? account(String key) => a.containsKey(key)
        ? (a[key] == null ? null : _account(a[key]).id)
        : (key == 'account_id' ? old?.accountId : old?.transferAccountId);
    final start =
        a['start_date'] != null ? _day(a['start_date']) : old?.startDate;
    final end = a['end_date'] != null ? _day(a['end_date']) : old?.endDate;
    if (start == null || end == null || !end.isAfter(start)) {
      throw ArgumentError('Informe início e fim, com o fim depois do início.');
    }
    final principal = a['principal_cents'] != null
        ? _reais(a['principal_cents'])
        : old?.principal ?? (throw ArgumentError('Informe o valor.'));
    return Loan(
        id: id,
        name: (a['name'] as String?)?.trim() ?? old?.name ?? 'Empréstimo',
        principal: principal,
        currency: old?.currency ?? app.settings.currency,
        startDate: start,
        endDate: end,
        interestRate: a.containsKey('interest_rate')
            ? (a['interest_rate'] as num?)?.toDouble()
            : old?.interestRate,
        accountId: account('account_id'),
        transferAccountId: account('transfer_account_id'),
        reminderEnabled:
            a['reminder_enabled'] as bool? ?? old?.reminderEnabled ?? false,
        reminderDay: a['reminder_day'] as int? ?? old?.reminderDay ?? 1,
        reminderTime: old?.reminderTime ?? '09:00',
        isSettled: a['settled'] as bool? ?? old?.isSettled ?? false,
        notes: a['notes'] as String? ?? old?.notes ?? '',
        createdAt: old?.createdAt);
  }

  /// Open Finance suggestion as a transfer between two own accounts, or as
  /// an entry with subcategory and note (the review screen's options).
  Future<Map<String, Object?>> _suggestion(
      String kind, Map<String, dynamic> a) async {
    final sid = a['id'] as String;
    Future<Map<String, Object?>?> row() async {
      final rows = await (await DBHelper.database)
          .query('notification_suggestions', where: 'id = ?', whereArgs: [sid]);
      return rows.isEmpty ? null : rows.single;
    }

    var s = await row();
    if (s == null) {
      await PluggyInbox.instance?.sync();
      s = await row();
    }
    if (s == null) throw StateError('Sugestão não encontrada neste aparelho.');
    if (s['status'] == 'confirmed') {
      return {'message': 'Já estava confirmada.'};
    }
    if (s['status'] != 'pending') {
      throw StateError('A sugestão já foi ignorada ou expirou.');
    }
    final amount = (s['amount_cents'] as int) / 100;
    final date = DateTime.fromMillisecondsSinceEpoch(s['occurred_at'] as int);
    if (kind == 'suggestion.transfer') {
      final from = _account(a['from_account_id']);
      final to = _account(a['to_account_id']);
      await app.addTransfer(
          fromId: from.id,
          toId: to.id,
          fromAmount: amount,
          note: s['description'] as String? ?? '',
          occurredAt: date,
          suggestionId: sid);
      return {'message': 'Transferência registrada a partir da sugestão.'};
    }
    final type = a['type'] as String;
    final account = _account(a['account_id']);
    final c = _category(a['category_id']);
    if (c.type != type) throw StateError('A categoria é de outro tipo.');
    final refund = s['kind'] == 'refund' && type == 'income';
    final txId = 'notification:$sid';
    await app.addTransaction(
        AppTransaction(
            id: txId,
            type: type,
            amount: amount,
            description: (a['description'] as String?)?.trim() ??
                s['description'] as String,
            accountId: account.id,
            categoryId: c.id,
            date: date,
            currency: account.currency,
            note: a['note'] as String? ??
                (refund ? 'Estorno / reembolso revisado' : '')),
        metadata: TransactionMetadata(
            transactionId: txId,
            subcategory: a['subcategory'] as String? ?? '',
            source: refund ? 'notification_refund' : 'notification'),
        suggestionId: sid);
    return {
      'transaction_id': txId,
      'message': 'Sugestão confirmada e lançada.'
    };
  }
}
