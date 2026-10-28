import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/utils/finance_input.dart';
import 'package:nexo/services/billing_cycle.dart';
import 'package:nexo/services/ofx_parser.dart';
import 'package:nexo/models/models.dart';

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
  test('A purchase on the closing day is already in the next invoice', () {
    // Closes on the 20th ("melhor dia de compra"), due on the 27th.
    final before = BillingCycle.forDate(DateTime(2026, 9, 19, 23, 59), 20, 27);
    expect(before.end, DateTime(2026, 9, 20));
    expect(before.start, DateTime(2026, 8, 20));
    expect(before.lastDay, DateTime(2026, 9, 19));
    expect(before.due, DateTime(2026, 9, 27));
    final onClosing = BillingCycle.forDate(DateTime(2026, 9, 20, 8), 20, 27);
    expect(onClosing.end, DateTime(2026, 10, 20));
    expect(onClosing.contains(DateTime(2026, 9, 20)), isTrue);
    expect(before.contains(DateTime(2026, 9, 20)), isFalse);
    expect(BillingCycle.forDate(DateTime(2026, 9, 21), 20, 10).due,
        DateTime(2026, 11, 10));
    // The invoice that closes on a date (payment key) is the one before it.
    expect(BillingCycle.endingOn(DateTime(2026, 9, 20), 20, 27).start,
        DateTime(2026, 8, 20));
  });
  test('Short months, year boundary and unconfigured card', () {
    // Closing on the 31st closes on the 28th in February.
    expect(BillingCycle.forDate(DateTime(2026, 2, 27, 12), 31, 5).end,
        DateTime(2026, 2, 28));
    expect(BillingCycle.forDate(DateTime(2026, 2, 28, 12), 31, 5).end,
        DateTime(2026, 3, 31));
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
