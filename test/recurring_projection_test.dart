import 'package:flutter_test/flutter_test.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/services/recurring_projection.dart';

void main() {
  RecurringPayment recurring(
          {DateTime? next,
          DateTime? end,
          int frequency = 1,
          String unit = 'months',
          List<RecurringHistoryEntry> skipped = const []}) =>
      RecurringPayment(
          id: 'r',
          name: 'Exemplo',
          accountId: 'a',
          categoryId: 'c',
          amount: 100,
          freqVal: frequency,
          freqUnit: unit,
          startDate: DateTime(2026, 1, 31),
          nextDate: next ?? DateTime(2026, 1, 31),
          endDate: end,
          recurringType: 'installment',
          skippedOccurrences: skipped);
  test(
      'Calendar preserves month-end and never mutates or creates ledger entries',
      () {
    final r = recurring(end: DateTime(2026, 3, 31));
    final before = r.toMap();
    final p = RecurringProjection.calculate([r], until: DateTime(2026, 12, 31));
    expect(p.occurrences.map((e) => e.date),
        [DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31)]);
    expect(p.occurrences.fold<double>(0, (s, e) => s + e.amount), 300);
    expect(r.toMap(), before);
    expect(p.incomplete, false);
  });
  test(
      'Skipped installment remains due at its historical amount; known rows do not duplicate',
      () {
    final missed = RecurringHistoryEntry(
        id: 'recurring:r:2026-01-31T00:00:00.000',
        recurringId: 'r',
        action: 'skipped',
        date: DateTime(2026, 1, 31),
        amount: 80,
        currency: 'BRL');
    final r = recurring(
        next: DateTime(2026, 2, 28),
        end: DateTime(2026, 3, 31),
        skipped: [missed]);
    final p = RecurringProjection.calculate([r],
        until: DateTime(2026, 3, 31),
        registeredIds: {'recurring:r:2026-02-28T00:00:00.000'});
    expect(p.occurrences.map((e) => e.amount), [80, 100]);
    expect(p.occurrences.first.date, DateTime(2026, 1, 31));
    r.recurringType = 'subscription';
    expect(
        RecurringProjection.calculate([r], until: DateTime(2026, 3, 31))
            .occurrences
            .length,
        2);
  });
  test(
      'Completed schedule contributes nothing; invalid or excessive schedules are explicit',
      () {
    expect(
        RecurringProjection.calculate([
          recurring(next: DateTime(2026, 4, 30), end: DateTime(2026, 3, 31))
        ], until: DateTime(2026, 12, 31))
            .occurrences,
        isEmpty);
    expect(
        RecurringProjection.calculate([recurring(frequency: 0)],
                until: DateTime(2026, 12, 31))
            .incomplete,
        true);
    final p = RecurringProjection.calculate([recurring(unit: 'days')],
        until: DateTime(2050));
    expect(p.occurrences, hasLength(3660));
    expect(p.incomplete, true);
  });
  test('Weekly projections use actual dates rather than monthly averages', () {
    final p = RecurringProjection.calculate(
        [recurring(next: DateTime(2026, 10, 1), unit: 'weeks')],
        until: DateTime(2026, 10, 31));
    expect(p.occurrences.length, 5);
    expect(p.occurrences.fold<double>(0, (s, e) => s + e.amount), 500);
  });
}
