import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/services/receipt_parser.dart';

void main() {
  final now = DateTime(2026, 10, 28);

  test('a supermarket cupom: total line wins over item prices', () {
    final r = ReceiptParser.parse('''
SUPERMERCADO BOM PRECO LTDA
CNPJ 12.345.678/0001-90
Rua das Flores 10
CUPOM FISCAL ELETRONICO
ARROZ 5KG 1 x 24,90 24,90
LEITE 2 x 4,59 9,18
SUBTOTAL 34,08
DESCONTO 2,00
VALOR TOTAL R\$ 32,08
DINHEIRO 50,00
TROCO 17,92
27/10/2026 18:42:10
''', now: now);
    expect(r.total, 32.08);
    expect(r.date, DateTime(2026, 10, 27));
    expect(r.merchant, 'SUPERMERCADO BOM PRECO LTDA');
    expect(r.hasTotal, isTrue);
  });

  test('a card slip without a total word takes the largest amount', () {
    final r = ReceiptParser.parse('''
PADARIA DA ESQUINA
VENDA CREDITO
AUT 123456
VALOR: 18,50
''', now: now);
    expect(r.total, 18.5);
    expect(r.merchant, 'PADARIA DA ESQUINA');
    expect(r.date, isNull);
  });

  test('thousands and a two-digit year', () {
    final r = ReceiptParser.parse('TOTAL A PAGAR 1.250,00\nVENCIMENTO 05/11/26',
        now: DateTime(2026, 11, 10));
    expect(r.total, 1250.0);
    expect(r.date, DateTime(2026, 11, 5));
  });

  test('a future date is ignored; nothing useful yields no total', () {
    expect(ReceiptParser.parse('Data 30/12/2026 valor 10,00', now: now).date,
        isNull);
    final empty = ReceiptParser.parse('sem numeros aqui', now: now);
    expect(empty.hasTotal, isFalse);
    expect(empty.merchant, 'sem numeros aqui');
  });
}
