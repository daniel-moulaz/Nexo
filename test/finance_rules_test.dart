import 'package:flutter_test/flutter_test.dart';
import 'package:expensy/utils/finance_input.dart';
import 'package:expensy/services/billing_cycle.dart';
import 'package:expensy/services/ofx_parser.dart';
import 'package:expensy/models/models.dart';

void main() {
  test('Brazilian and decimal money input, rejecting malformed values', () {
    for (final value in ['1234,56', '1.234,56', '1234.56', 'R\$ 1.234,56']) {
      expect(parseMoney(value), 1234.56);
    }
    expect(parseMoney('100'), 100);
    expect(parseMoney('100,50'), 100.5);
    expect(parseMoney('1.234'), 1234);
    for (final value in ['', 'abc100', '1,2,3', 'NaN', 'Infinity', '1e3']) {
      expect(parseMoney(value), isNull);
    }
  });
  test('Closing day includes purchases until midnight, due in same month', () {
    final cycle = BillingCycle.forDate(DateTime(2026, 9, 20, 23, 59), 20, 27);
    expect(cycle.end, DateTime(2026, 9, 20));
    expect(cycle.due, DateTime(2026, 9, 27));
    expect(BillingCycle.forDate(DateTime(2026, 9, 21), 20, 10).due,
        DateTime(2026, 11, 10));
  });
  test('Short months, year boundary and unconfigured card', () {
    expect(BillingCycle.forDate(DateTime(2026, 2, 28, 12), 31, 5).end,
        DateTime(2026, 2, 28));
    expect(BillingCycle.forDate(DateTime(2026, 12, 31), 20, 10).due,
        DateTime(2027, 2, 10));
    final cycle = BillingCycle.forDate(DateTime(2026, 2, 12), null, null);
    expect(cycle.start, DateTime(2026, 2));
    expect(cycle.end, DateTime(2026, 2, 28));
    expect(cycle.due, isNull);
  });
  test('Monthly recurrence preserves original day after February', () {
    final r = RecurringPayment(
        id: 'r',
        name: 'Conta',
        accountId: 'a',
        categoryId: 'bills',
        amount: 20,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(2026, 1, 31),
        nextDate: DateTime(2026, 1, 31));
    r.nextDate = r.calcNextDate();
    expect(r.nextDate, DateTime(2026, 2, 28));
    expect(r.calcNextDate(), DateTime(2026, 3, 31));
  });
  test('OFX signs, dates and duplicate FITID', () {
    const row =
        '<STMTTRN><DTPOSTED>20260925120000[-3:BRT]<TRNAMT>-1234.56<FITID>one<NAME>Mercado<MEMO>Compra</STMTTRN>';
    final entries =
        parseOfx('<OFX><BANKTRANLIST>$row$row</BANKTRANLIST></OFX>');
    expect(entries, hasLength(1));
    expect(entries.single.amount, -1234.56);
    expect(entries.single.date, DateTime(2026, 9, 25));
  });
}
