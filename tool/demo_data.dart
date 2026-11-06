// Fictitious data for screenshots and layout checks: no profile, database or
// account of anyone.
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/investments/investment_models.dart';
import 'package:nexo/investments/investment_repository.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/providers/app_provider.dart';

/// [scale] multiplies every amount, to test how layouts take big numbers.
AppProvider demoApp({double scale = 1}) {
  final now = DateTime.now();
  DateTime day(int d) => DateTime(now.year, now.month, d.clamp(1, now.day));
  final app = AppProvider()
    ..settings.currency = 'BRL'
    ..settings.languageCode = 'pt'
    ..settings.userName = 'Alex'
    ..settings.onboarded = true
    ..settings.budgetAlertsEnabled = false;
  app.accounts = [
    Account(
        id: 'main',
        name: 'Conta principal',
        type: 'bank',
        balance: 4850.32 * scale,
        currency: 'BRL',
        colorValue: 0xff00695c),
    Account(
        id: 'reserve',
        name: 'Reserva',
        type: 'savings',
        balance: 12400 * scale,
        currency: 'BRL',
        colorValue: 0xff1565c0),
    Account(
        id: 'card',
        name: 'Cartão roxo',
        type: 'credit',
        balance: -1240.5 * scale,
        currency: 'BRL',
        colorValue: 0xff6a1b9a,
        statementDay: 19,
        dueDay: 26,
        creditLimit: 3000 * scale,
        linkedAccountId: 'main'),
  ];
  AppCategory cat(String id, String name, int color,
          [String type = 'expense']) =>
      AppCategory(id: id, name: name, type: type, colorValue: color);
  app.categories = [
    cat('food', 'Alimentação', 0xff2e7d32),
    cat('home', 'Moradia', 0xff1565c0),
    cat('transport', 'Transporte', 0xffef6c00),
    cat('fun', 'Lazer', 0xff8e24aa),
    cat('health', 'Saúde', 0xffc62828),
    cat('subs', 'Assinaturas', 0xff00838f),
    cat('salary', 'Salário', 0xff2e7d32, 'income'),
  ];
  var n = 0;
  AppTransaction tx(String desc, double amount, String category, int d,
          {String account = 'main', String type = 'expense'}) =>
      AppTransaction(
          id: 'demo${n++}',
          type: type,
          amount: amount * scale,
          description: desc,
          accountId: account,
          categoryId: category,
          currency: 'BRL',
          date: day(d));
  app.transactions = [
    tx('Salário', 6200, 'salary', 1, type: 'income'),
    tx('Aluguel', 1650, 'home', 1),
    tx('Mercado da semana', 312.4, 'food', 2),
    tx('Padaria', 18.9, 'food', 2, account: 'card'),
    tx('Combustível', 210, 'transport', 3, account: 'card'),
    tx('Farmácia', 64.3, 'health', 3),
    tx('Cinema', 58, 'fun', 4, account: 'card'),
    tx('Mercado da semana', 287.15, 'food', 4),
    tx('Aplicativo de transporte', 32.7, 'transport', 5, account: 'card'),
    tx('Restaurante', 96.5, 'food', 5, account: 'card'),
    tx('Internet', 99.9, 'subs', 5),
    tx('Streaming', 39.9, 'subs', 5, account: 'card'),
    tx('Livraria', 67.8, 'fun', now.day, account: 'card'),
    tx('Café', 12.5, 'food', now.day, account: 'card'),
  ];
  app.transactionMetadata = {
    for (final t in app.transactions)
      t.id: TransactionMetadata(
          transactionId: t.id,
          source:
              const {'Salário', 'Aluguel', 'Internet'}.contains(t.description)
                  ? 'recurring'
                  : 'manual')
  };
  app.recurring = [
    RecurringPayment(
        id: 'rent',
        name: 'Aluguel',
        accountId: 'main',
        categoryId: 'home',
        amount: 1650 * scale,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(now.year, now.month - 6, 1),
        nextDate: DateTime(now.year, now.month + 1, 1)),
    RecurringPayment(
        id: 'net',
        name: 'Internet',
        accountId: 'main',
        categoryId: 'subs',
        amount: 99.9 * scale,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(now.year, now.month - 6, 17),
        nextDate: DateTime(now.year, now.month, 17)),
    RecurringPayment(
        id: 'salary',
        name: 'Salário',
        accountId: 'main',
        categoryId: 'salary',
        amount: 6200 * scale,
        paymentType: 'income',
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(now.year, now.month - 6, 1),
        nextDate: DateTime(now.year, now.month + 1, 1)),
  ];
  app.budgets = [
    Budget(
        id: 'b-food',
        categoryId: 'food',
        amount: 1200 * scale,
        period: 'monthly',
        createdAt: DateTime(now.year, now.month - 2, 1)),
    Budget(
        id: 'b-fun',
        categoryId: 'fun',
        amount: 300 * scale,
        period: 'monthly',
        createdAt: DateTime(now.year, now.month - 2, 1)),
  ];
  app.savingsGoals = [
    SavingsGoal(
        id: 'trip',
        name: 'Viagem',
        targetAmount: 8000 * scale,
        currentAmount: 3200 * scale,
        currency: 'BRL',
        colorValue: 0xffef6c00),
  ];
  return app;
}

Future<void> seedDemoInvestments() async {
  final db = await DBHelper.database;
  await db.delete('investment_operations');
  await db.delete('investments');
  final repo = InvestmentRepository();
  final start = DateTime(DateTime.now().year, DateTime.now().month - 4, 3);
  const names = [
    'Empresa de demonstração',
    'Fundo imobiliário de exemplo',
    'Tesouro de exemplo',
    'Fundo de índice de exemplo',
  ];
  for (var i = 0; i < names.length; i++) {
    final item = Investment(
        id: 'asset$i',
        name: names[i],
        assetClass: investmentClasses[i % investmentClasses.length],
        priceMicros: (32 + i * 11) * investmentScale,
        priceAt: DateTime.now(),
        ticker: i == 0 ? 'DEMO3' : '',
        institution: 'Corretora de teste');
    await repo.create(
        item,
        InvestmentOperation(
            id: 'op$i',
            investmentId: item.id,
            kind: 'buy',
            quantity: (10 + i * 4) * investmentScale,
            cents: 28000 + i * 21000,
            date: start,
            createdAt: start));
  }
}
