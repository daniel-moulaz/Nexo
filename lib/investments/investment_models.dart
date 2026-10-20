/// Operations may explicitly link to cash. All persisted portfolio money is
/// integer cents; quantities and unit prices use six decimal places.
const investmentScale = 1000000;
const investmentClasses = [
  'Ações',
  'FIIs',
  'ETFs',
  'Renda fixa',
  'Cripto',
  'Outros'
];

int? parseInvestmentQuantity(String text) {
  final value = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 1000000) return null;
  final units = whole * investmentScale +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(6, '0')));
  return units > 0 && units <= 1000000000000 ? units : null;
}

int roundedRatio(int a, int b, int divisor) =>
    ((BigInt.from(a) * BigInt.from(b) + BigInt.from(divisor ~/ 2)) ~/
            BigInt.from(divisor))
        .toInt();

class Investment {
  final String id, name, assetClass, ticker, institution, priceSource;
  final int priceMicros;
  final DateTime priceAt;
  final bool archived;
  const Investment(
      {required this.id,
      required this.name,
      required this.assetClass,
      this.ticker = '',
      this.institution = '',
      required this.priceMicros,
      required this.priceAt,
      this.priceSource = 'manual',
      this.archived = false});
  bool get canQuote =>
      ['Ações', 'FIIs', 'ETFs'].contains(assetClass) && ticker.isNotEmpty;
  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'asset_class': assetClass,
        'ticker': ticker,
        'institution': institution,
        'price_micros': priceMicros,
        'price_at': priceAt.toUtc().toIso8601String(),
        'price_source': priceSource,
        'archived': archived ? 1 : 0
      };
  factory Investment.fromMap(Map<String, dynamic> m) {
    final item = Investment(
        id: m['id'] as String,
        name: m['name'] as String,
        assetClass: m['asset_class'] as String,
        ticker: m['ticker'] as String,
        institution: m['institution'] as String,
        priceMicros: m['price_micros'] as int,
        priceAt: DateTime.parse(m['price_at'] as String),
        priceSource: m['price_source'] as String,
        archived: (m['archived'] as int? ?? 0) == 1);
    item.validate();
    return item;
  }
  void validate() {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        name.length > 120 ||
        institution.length > 120 ||
        !investmentClasses.contains(assetClass) ||
        (ticker.isNotEmpty && !RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(ticker)) ||
        priceMicros < 0 ||
        priceMicros > 1000000000000 ||
        !['manual', 'entrada', 'brapi'].contains(priceSource)) {
      throw const FormatException('Dados do investimento inválidos.');
    }
  }
}

class InvestmentOperation {
  final String id, investmentId, kind;
  final int quantity, cents;
  final DateTime date, createdAt;
  final String? cashAccountId;
  const InvestmentOperation(
      {required this.id,
      required this.investmentId,
      required this.kind,
      required this.quantity,
      required this.cents,
      required this.date,
      required this.createdAt,
      this.cashAccountId});
  String get label => switch (kind) {
        'buy' => 'Compra / aporte',
        'sell' => 'Venda / resgate',
        'opening' => 'Posição inicial',
        _ => 'Provento recebido'
      };
  Map<String, Object?> toMap() => {
        'id': id,
        'investment_id': investmentId,
        'kind': kind,
        'quantity': quantity,
        'cents': cents,
        'date': date.toUtc().toIso8601String(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'cash_account_id': cashAccountId
      };
  factory InvestmentOperation.fromMap(Map<String, dynamic> m) {
    final op = InvestmentOperation(
        id: m['id'] as String,
        investmentId: m['investment_id'] as String,
        kind: m['kind'] as String,
        quantity: m['quantity'] as int,
        cents: m['cents'] as int,
        date: DateTime.parse(m['date'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
        cashAccountId: m['cash_account_id'] as String?);
    op.validate();
    return op;
  }
  void validate() {
    if (id.isEmpty ||
        investmentId.isEmpty ||
        !['buy', 'sell', 'opening', 'income'].contains(kind) ||
        cents < 0 ||
        cents > 100000000000000 ||
        quantity < 0 ||
        quantity > 1000000000000 ||
        (cashAccountId != null && (cashAccountId!.isEmpty || cents == 0)) ||
        (kind == 'income' ? quantity != 0 || cents == 0 : quantity == 0)) {
      throw const FormatException('Operação de investimento inválida.');
    }
  }
}

class InvestmentPosition {
  final Investment investment;
  final List<InvestmentOperation> operations;
  int quantity = 0,
      cost = 0,
      realized = 0,
      income = 0,
      purchases = 0,
      sales = 0;
  InvestmentPosition(this.investment, Iterable<InvestmentOperation> entries)
      : operations = entries.toList() {
    investment.validate();
    operations.sort((a, b) {
      var c = a.date.compareTo(b.date);
      if (c == 0) c = a.createdAt.compareTo(b.createdAt);
      return c == 0 ? a.id.compareTo(b.id) : c;
    });
    final ids = <String>{};
    for (final op in operations) {
      op.validate();
      if (!ids.add(op.id) || op.investmentId != investment.id) {
        throw const FormatException('Operação duplicada ou sem investimento.');
      }
      switch (op.kind) {
        case 'buy':
        case 'opening':
          quantity += op.quantity;
          cost += op.cents;
          if (op.kind == 'buy') purchases += op.cents;
        case 'sell':
          if (op.quantity > quantity) {
            throw const FormatException(
                'A venda supera a quantidade disponível nessa data.');
          }
          final removed = roundedRatio(cost, op.quantity, quantity);
          cost -= removed;
          quantity -= op.quantity;
          realized += op.cents - removed;
          sales += op.cents;
        case 'income':
          income += op.cents;
      }
      if (quantity > 1000000000000 || cost > 100000000000000) {
        throw const FormatException('A posição excede o limite suportado.');
      }
    }
  }
  int get value => roundedRatio(quantity, investment.priceMicros, 10000000000);
  int get unrealized => value - cost;
  int get result => unrealized + realized + income;
}
