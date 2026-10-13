import '../models/models.dart';

/// Read-only occurrences. These are commitments, never transactions or cash.
class RecurringOccurrence {
  final RecurringPayment recurring;
  final DateTime date;
  final double amount;
  const RecurringOccurrence(this.recurring, this.date, this.amount);
}

class RecurringProjection {
  final List<RecurringOccurrence> occurrences;
  final bool incomplete;
  const RecurringProjection(this.occurrences, this.incomplete);

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static RecurringProjection calculate(Iterable<RecurringPayment> items,
      {required DateTime until, Set<String> registeredIds = const {}}) {
    final result = <RecurringOccurrence>[];
    var incomplete = false;
    for (final original in items) {
      if (original.freqVal < 1) {
        incomplete = true;
        continue;
      }
      final seen = <String>{...registeredIds};
      void add(String id, DateTime date, double amount) {
        if (!day(date).isAfter(day(until)) && seen.add(id)) {
          result.add(RecurringOccurrence(original, day(date), amount));
        }
      }

      if (original.hasSkippedInstallments) {
        for (final skipped in original.skippedOccurrences) {
          add(skipped.id, skipped.date, skipped.amount);
        }
      }
      final cursor = RecurringPayment.fromMap(original.toMap());
      var count = 0;
      while (!day(cursor.nextDate).isAfter(day(until)) &&
          (cursor.endDate == null ||
              !day(cursor.nextDate).isAfter(day(cursor.endDate!)))) {
        if (++count > 3660) {
          incomplete = true;
          break;
        }
        add('recurring:${cursor.id}:${cursor.nextDate.toIso8601String()}',
            cursor.nextDate, cursor.amount);
        final next = cursor.calcNextDate();
        if (!next.isAfter(cursor.nextDate)) {
          incomplete = true;
          break;
        }
        cursor.nextDate = next;
      }
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return RecurringProjection(List.unmodifiable(result), incomplete);
  }
}
