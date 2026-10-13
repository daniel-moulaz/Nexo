import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/services/transaction_metadata_service.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/services/financial_checkup.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  final now = DateTime(2026, 10, 13, 15);
  AppProvider fixture() {
    final app = AppProvider()..settings.currency = 'BRL';
    app.accounts = [
      Account(
          id: 'bank',
          name: 'Banco privado',
          type: 'bank',
          balance: 2280,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'card',
          name: 'Cartão privado',
          type: 'credit',
          balance: 0,
          currency: 'BRL',
          colorValue: 0,
          statementDay: 10,
          dueDay: 18),
    ];
    AppTransaction tx(String id, double value,
            {String type = 'expense',
            String account = 'bank',
            DateTime? date}) =>
        AppTransaction(
            id: id,
            description: 'Descrição privada $id',
            amount: value,
            type: type,
            accountId: account,
            categoryId: 'food',
            date: date ?? now,
            currency: 'BRL');
    app.transactions = [
      tx('income', 1500, type: 'income'),
      tx('market', 100),
      tx('pending', 80),
      tx('transfer-out', 200),
      tx('transfer-in', 200, type: 'income'),
      tx('purchase', 120, account: 'card', date: DateTime(2026, 10, 9)),
      tx('invoice-out', 120),
      tx('invoice-in', 120, account: 'card', type: 'income'),
      tx('refund', 20, type: 'income'),
      tx('previous', 200, date: DateTime(2026, 10, 6)),
      tx('future', 999, date: DateTime(2026, 10, 14)),
    ];
    app.transactionMetadata = {
      for (final id in [
        'transfer-out',
        'transfer-in',
        'invoice-out',
        'invoice-in'
      ])
        id: TransactionMetadata(transactionId: id, excludeFromSpending: true),
      'pending': TransactionMetadata(
          transactionId: 'pending', status: 'pending', dueDate: now),
      'refund': const TransactionMetadata(
          transactionId: 'refund', source: 'notification_refund'),
    };
    app.budgets = [
      Budget(
          id: 'b',
          categoryId: 'food',
          amount: 2000,
          period: 'monthly',
          createdAt: now)
    ];
    return app;
  }

  FinancialCheckup report(AppProvider app,
          {int days = 7, bool names = false}) =>
      FinancialCheckup.build(app,
          now: now,
          days: days,
          includeNames: names,
          invoicePayments: [
            {'card_id': 'card', 'cycle_end': '2026-10-10', 'amount': 120}
          ]);

  test(
      'Real consumption excludes transfers, invoice payments, pending and future',
      () {
    final app = fixture();
    final r = report(app);
    final lines = r.sections['O que aconteceu']!.join('\n');
    expect(lines, contains('Receitas realizadas: R\$ 1.500,00'));
    expect(lines, contains('Consumo registrado: R\$ 220,00'));
    expect(lines, contains('Reembolsos: R\$ 20,00'));
    expect(lines, contains('Resultado do período: R\$ 1.300,00'));
    expect(lines, contains('no período: R\$ 80,00'));
    expect(lines, contains('anteriores: R\$ 200,00'));
    expect(lines, contains('Variação do consumo: 10,0%'));
    expect(r.from, DateTime(2026, 10, 7));
    app.dispose();
  });
  test('Forecast deducts pending once and does not repay a settled invoice',
      () {
    final app = fixture();
    final r = report(app);
    expect(
        r.sections['Próximos compromissos']!.first, contains('R\$ 2.200,00'));
    expect(app.accounts.first.balance, 2280);
    expect(app.transactions, hasLength(11));
    app.dispose();
  });
  test(
      'Three-day period and prior comparable interval include calendar boundaries',
      () {
    final app = fixture();
    final r = report(app, days: 3);
    expect(r.from, DateTime(2026, 10, 11));
    expect(r.sections['O que aconteceu']!.join('\n'),
        contains('Consumo registrado: R\$ 100,00'));
    expect(r.sections['O que aconteceu']!.join('\n'),
        contains('anteriores: R\$ 120,00'));
    app.dispose();
  });
  test('Names are opt-in and free text notes are never exported', () {
    final app = fixture();
    expect(report(app).text, isNot(contains('Banco privado')));
    expect(report(app).text, isNot(contains('Cartão privado')));
    expect(report(app).text, isNot(contains('Descrição privada')));
    expect(report(app, names: true).text, contains('Banco privado'));
    expect(report(app, names: true).text,
        isNot(contains('Descrição privada market')));
    expect(report(app).text, contains('não há sincronização'));
    app.dispose();
  });
  test('Budget separates pending and uses entire budget period consistently',
      () {
    final app = fixture();
    final text = report(app).sections['Orçamentos atuais']!.join('\n');
    expect(text, contains('realizado R\$ 1.419,00; pendente R\$ 80,00'));
    expect(text, contains('disponível após pendências R\$ 501,00'));
    app.dispose();
  });
  test('Empty report and zero comparison do not invent percentages', () {
    final app = AppProvider()..settings.currency = 'BRL';
    final text = report(app).text;
    expect(text, contains('Sem base anterior'));
    expect(text, isNot(contains('NaN')));
    expect(text, contains('Nenhuma despesa realizada'));
    expect(() => report(app, days: 0), throwsArgumentError);
    app.dispose();
  });
}
