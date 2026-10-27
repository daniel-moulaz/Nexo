import '../models/models.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import 'cash_forecast.dart';
import 'financial_analysis.dart';
import 'finance_rules.dart';

/// A read-only snapshot. No network, persistence or automatic recommendations.
class FinancialCheckup {
  final DateTime generatedAt, from, to;
  final Map<String, List<String>> sections;
  const FinancialCheckup(this.generatedAt, this.from, this.to, this.sections);

  String get text => [
        'NEXO — REVISÃO FINANCEIRA',
        'Período: ${ptDate(from)} a ${ptDate(to)} (inclui hoje)',
        'Gerado em: ${generatedAt.toIso8601String()} (horário local)',
        'Somente dados deste dispositivo; não há sincronização entre PC e celular.',
        for (final section in sections.entries) ...[
          '\n${section.key.toUpperCase()}',
          ...section.value.map((line) => '- $line'),
        ],
      ].join('\n');

  static FinancialCheckup build(AppProvider app,
      {required DateTime now,
      required int days,
      required List<Map<String, dynamic>> invoicePayments,
      bool includeNames = false}) {
    if (days != 3 && days != 7) throw ArgumentError.value(days, 'days');
    final today = DateTime(now.year, now.month, now.day);
    final from = DateTime(now.year, now.month, now.day - days + 1);
    String money(double value, [String? currency]) =>
        formatAmount(value, currency ?? app.settings.currency)
            .replaceAll(RegExp(r'[\s\u00a0]+'), ' ');
    String label(String raw, String fallback) => includeNames
        ? raw.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim()
        : fallback;
    double amount(AppTransaction t) => app.convertToMain(
        t.amount,
        t.currency.isNotEmpty
            ? t.currency
            : app.accountById(t.accountId)?.currency ?? app.settings.currency);
    FinancialAnalysis analyze(DateTime start, DateTime end) =>
        FinancialAnalysis(
            transactions: app.transactions,
            metadata: app.transactionMetadata,
            filter: AnalysisFilter(from: start, to: end),
            amount: amount);
    final current = analyze(from, today);
    final previous = analyze(DateTime(from.year, from.month, from.day - days),
        DateTime(from.year, from.month, from.day - 1));
    final forecast = CashForecast.calculate(
        now: today,
        until: DateTime(today.year, today.month, today.day + 7),
        accounts: app.accounts,
        transactions: app.transactions,
        recurring: app.recurring,
        metadata: app.transactionMetadata,
        invoicePayments: invoicePayments,
        convert: app.convertToMain);
    final month = CashForecast.calculate(
        now: today,
        until: DateTime(today.year, today.month + 1, 0),
        accounts: app.accounts,
        transactions: app.transactions,
        recurring: app.recurring,
        metadata: app.transactionMetadata,
        invoicePayments: invoicePayments,
        convert: app.convertToMain);
    final sections = <String, List<String>>{};
    sections['O que aconteceu'] = [
      'Receitas realizadas: ${money(current.income)}',
      'Consumo registrado: ${money(current.expense)}',
      'Reembolsos: ${money(current.refunds)}',
      'Resultado do período: ${money(current.result)} (não é o saldo bancário)',
      'Despesas pendentes com data no período: ${money(current.pendingExpense)}',
      'Consumo nos $days dias anteriores: ${money(previous.expense)}',
      if (current.changeFrom(previous) case final double change)
        'Variação do consumo: ${change.toStringAsFixed(1).replaceAll('.', ',')}%',
      if (previous.expense == 0)
        'Sem base anterior para calcular variação percentual.',
      'Compras no cartão contam no consumo. Transferências, reservas e pagamentos de fatura não contam novamente.',
      'Datas seguem os lançamentos cadastrados; não necessariamente a data de liquidação no banco.',
    ];
    sections['Para onde foi o dinheiro'] = [
      if (current.categories.isEmpty) 'Nenhuma despesa realizada no período.',
      for (final (index, entry) in current.topCategories.indexed)
        '${label(app.categoryById(entry.key)?.name ?? 'Sem categoria', 'Categoria ${index + 1}')}: ${money(entry.value)} (${(entry.value / current.expense * 100).toStringAsFixed(1).replaceAll('.', ',')}%)',
      'Recorrentes realizadas: ${money(current.recurring)}',
      'Pontuais (fora das comparações): ${money(current.extraordinary)}',
      'Recorrente e extraordinária podem se sobrepor; não some esses grupos.',
    ];
    sections['Situação de hoje'] = [
      'Saldo em contas incluídas: ${money(forecast.current)} (sem cartões e ouro)',
      for (final (index, account) in app.accounts.indexed)
        '${label(account.name, '${account.type == 'credit' ? 'Cartão' : 'Conta'} ${index + 1}')}: ${money(account.balance, account.currency)}${account.excludeFromTotal ? ' • fora do saldo geral' : ''}${account.type == 'credit' ? ' • saldo negativo representa dívida' : ''}',
      for (final (index, loan) in app.loans.where((l) => !l.isSettled).indexed)
        '${label(loan.name, 'Empréstimo ${index + 1}')}: falta ${money(app.loanRemaining(loan), loan.currency)}; pago ${money(app.loanTotalPaid(loan), loan.currency)}; fim do contrato ${ptDate(loan.endDate)}',
      '${app.lended.where((l) => !l.isSettled).length} registros em aberto de dinheiro emprestado entre pessoas; consulte os detalhes no app.',
      'Empréstimos, faturas e parcelamentos podem representar o mesmo compromisso. Não há soma única dessas dívidas.',
    ];
    sections['Orçamentos atuais'] = [
      if (app.budgets.isEmpty) 'Nenhum orçamento cadastrado.',
      for (final (index, b) in app.budgets.indexed)
        ..._budget(
            app,
            b,
            today,
            amount,
            label(app.categoryById(b.categoryId)?.name ?? 'Sem categoria',
                'Orçamento ${index + 1}'),
            money),
    ];
    sections['Objetivos'] = [
      if (app.savingsGoals.isEmpty) 'Nenhum objetivo cadastrado.',
      for (final (index, g) in app.savingsGoals.indexed)
        '${label(g.name, 'Objetivo ${index + 1}')}: ${money(g.currentAmount, g.currency)} de ${money(g.targetAmount, g.currency)}${g.targetDate == null ? '' : '; prazo ${ptDate(g.targetDate!)}'}${g.isCompleted ? '; concluído' : ''}',
      'Valores reservados não são despesas de consumo.',
    ];
    sections['Próximos compromissos'] = [
      'Saldo previsto até ${ptDate(DateTime(today.year, today.month, today.day + 7))}: ${money(forecast.projected)}',
      'Saldo previsto no fim do mês: ${money(month.projected)}',
      'Previsão inclui atrasados ainda em aberto, lançamentos pendentes, recorrentes e faturas com vencimento configurado.',
      if (forecast.events.where((e) => e.amount != 0).isEmpty)
        'Nenhum movimento de caixa previsto nos próximos 7 dias.',
      for (final (index, event)
          in forecast.events.where((e) => e.amount != 0).indexed)
        '${ptDate(event.date)}${event.date.isBefore(today) ? ' • em atraso' : ''}: ${label(event.title, 'Compromisso ${index + 1}')} • ${money(event.amount, event.currency)}',
    ];
    final warnings = {...forecast.warnings, ...month.warnings};
    sections['Limites e atenção'] = [
      if (warnings.isNotEmpty)
        includeNames
            ? warnings.map((w) => label(w, '')).join(' ')
            : '${warnings.length} avisos de configuração na previsão. Consulte a Agenda no app.',
      'Previsão não inclui automaticamente contratos de empréstimo nem dinheiro emprestado entre pessoas. Cadastre os vencimentos sem duplicar compromissos existentes.',
      'O relatório não consulta bancos, notificações brutas, PIN ou credenciais. Não é backup e não altera dinheiro.',
      'Conversões usam as taxas disponíveis no app; valores futuros dependem do que foi cadastrado.',
      'Patrimônio em bens e histórico completo de cada contrato ficam nas telas específicas e não estão consolidados neste resumo.',
      includeNames
          ? 'Nomes incluídos por escolha do usuário.'
          : 'Nomes substituídos por rótulos neste relatório. Valores e datas continuam sendo informações financeiras privadas.',
    ];
    return FinancialCheckup(now, from, today, sections);
  }

  static List<String> _budget(
      AppProvider app,
      Budget b,
      DateTime today,
      double Function(AppTransaction) amount,
      String name,
      String Function(double, [String?]) money) {
    final offset = app.settings.weekStart == 'monday'
        ? today.weekday - 1
        : today.weekday % 7;
    final start = b.period == 'weekly'
        ? DateTime(today.year, today.month, today.day - offset)
        : DateTime(today.year, today.month);
    final end = b.period == 'weekly'
        ? DateTime(start.year, start.month, start.day + 7)
        : DateTime(today.year, today.month + 1);
    double used = 0, pending = 0;
    for (final t in app.transactions) {
      if (t.type != 'expense' ||
          t.categoryId != b.categoryId ||
          t.date.isBefore(start) ||
          !t.date.isBefore(end) ||
          FinanceRules.isNeutral(t, app.transactionMetadata[t.id])) continue;
      if (app.transactionMetadata[t.id]?.isPending == true) {
        pending += amount(t);
      } else {
        used += amount(t);
      }
    }
    final remaining = b.amount - used - pending;
    return [
      '$name (${ptDate(start)} a ${ptDate(DateTime(end.year, end.month, end.day - 1))}): realizado ${money(used)}; pendente ${money(pending)}; limite ${money(b.amount)}; ${remaining < 0 ? 'excedido' : 'disponível após pendências'} ${money(remaining.abs())}'
    ];
  }
}
