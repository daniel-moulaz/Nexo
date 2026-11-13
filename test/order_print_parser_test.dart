import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/services/order_print_parser.dart';

// Synthetic OCR text shaped like iFood order screens; no real orders.
void main() {
  final now = DateTime(2026, 11, 13, 20);

  test('a Pix order: total, restaurant, date and payment, reliable', () {
    const text = '''
14:02
Detalhes do pedido
Lanchonete Fictícia Centro
Pedido nº 4821 • Concluído
13/11/2026 • 12:34
1x X-Salada
R\$ 29,90
1x Refrigerante lata
R\$ 6,00
Subtotal R\$ 35,90
Taxa de entrega Grátis
Taxa de serviço R\$ 0,99
Desconto -R\$ 2,00
Total R\$ 34,89
Pagamento
Pago pelo app
Pix
''';
    final r = OrderPrintParser.parse(text, now: now);
    expect(r.app, 'ifood');
    expect(r.total, 34.89);
    expect(r.merchant, 'Lanchonete Fictícia Centro');
    expect(r.date, DateTime(2026, 11, 13));
    expect(r.payment, PrintPayment.pix);
    expect(r.reliable, isTrue, reason: r.doubts.join('; '));
  });

  test('total on the next line, card by its last digits, word date', () {
    const text = '''
iFood
Pizzaria do Exemplo
Pedido entregue
Realizado em 9 de nov
Subtotal
R\$ 52,00
Taxa de entrega
R\$ 7,99
Total
R\$ 59,99
Forma de pagamento
Mastercard •••• 1234
''';
    final r = OrderPrintParser.parse(text, now: now);
    expect(r.total, 59.99);
    expect(r.merchant, 'Pizzaria do Exemplo');
    expect(r.date, DateTime(2026, 11, 9));
    expect(r.payment, PrintPayment.credit);
    expect(r.reliable, isTrue, reason: r.doubts.join('; '));
  });

  test('parts that do not add up make the reading unsure, with the reason', () {
    const text = '''
Detalhes do pedido
Restaurante Teste
Pedido nº 10
Subtotal R\$ 40,00
Taxa de entrega R\$ 5,00
Total R\$ 54,00
Pix
''';
    final r = OrderPrintParser.parse(text, now: now);
    expect(r.total, 54);
    expect(r.reliable, isFalse);
    expect(r.doubts.join(), contains('não fecham'));
  });

  test('without a Total line: the largest amount, flagged', () {
    const text = '''
iFood
Mercadinho Teste
Pedido nº 77
1x Pão R\$ 8,00
1x Leite R\$ 6,50
Taxa de entrega R\$ 4,00
''';
    final r = OrderPrintParser.parse(text, now: now);
    expect(r.total, 8);
    expect(r.reliable, isFalse);
    expect(r.doubts.first, contains('Total'));
  });

  test('"ontem", a December date read in January and a debit card', () {
    final january = DateTime(2027, 1, 5);
    final yesterday = OrderPrintParser.parse(
        'iFood\nCafé Teste\nPedido\nOntem, 19:10\nTotal R\$ 12,00\nCartão de débito',
        now: january);
    expect(yesterday.date, DateTime(2027, 1, 4));
    expect(yesterday.payment, PrintPayment.debit);
    final december = OrderPrintParser.parse(
        'iFood\nCafé Teste\nPedido\n28 de dez\nTotal R\$ 12,00\nPix',
        now: january);
    expect(december.date, DateTime(2026, 12, 28));
  });

  test('something that is not an order is read as a receipt, not trusted', () {
    const text = 'SUPERMERCADO EXEMPLO LTDA\nCNPJ 00.000.000/0001-00\n'
        'VALOR TOTAL R\$ 23,40\n12/11/2026\nPIX';
    final r = OrderPrintParser.parse(text, now: now);
    expect(r.app, isNull);
    expect(r.total, 23.4);
    expect(r.reliable, isFalse);
    expect(r.payment, PrintPayment.pix);
  });
}
