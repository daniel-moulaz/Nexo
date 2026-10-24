/// An invoice period of a credit card. [end] is the closing date and the key
/// of the invoice (payments are recorded against it).
///
/// The closing day is the "melhor dia de compra" of Brazilian cards: a
/// purchase made on it already belongs to the next invoice. So a cycle holds
/// purchases from the previous closing day up to the day before [end]; use
/// [contains] or [until] instead of comparing with [end] directly.
class BillingCycle {
  final DateTime start;
  final DateTime end;
  final DateTime? due;

  /// First day that is no longer part of this invoice (exclusive bound).
  final DateTime until;
  const BillingCycle(this.start, this.end, this.due, {DateTime? until})
      : until = until ?? end;

  /// Last day with purchases in this invoice.
  DateTime get lastDay => until.subtract(const Duration(days: 1));

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(until);

  static DateTime date(int year, int month, int day) {
    final base = DateTime(year, month);
    return DateTime(base.year, base.month,
        day.clamp(1, DateTime(base.year, base.month + 1, 0).day));
  }

  /// The invoice that closes on [end] (a closing date, e.g. a payment key).
  static BillingCycle endingOn(DateTime end, int? closingDay, int? dueDay) =>
      forDate(DateTime(end.year, end.month, end.day - 1), closingDay, dueDay);

  static BillingCycle forDate(DateTime purchase, int? closingDay, int? dueDay) {
    final day = DateTime(purchase.year, purchase.month, purchase.day);
    DateTime? dueAfter(DateTime end) {
      if (dueDay == null) return null;
      final due = date(end.year, end.month, dueDay);
      return due.isAfter(end) ? due : date(end.year, end.month + 1, dueDay);
    }

    // Without a closing day the invoice is the calendar month.
    if (closingDay == null) {
      final start = DateTime(day.year, day.month);
      final end = DateTime(day.year, day.month + 1, 0);
      return BillingCycle(start, end, dueAfter(end),
          until: DateTime(day.year, day.month + 1));
    }
    var end = date(day.year, day.month, closingDay);
    if (!day.isBefore(end)) end = date(day.year, day.month + 1, closingDay);
    final start = date(end.year, end.month - 1, closingDay);
    return BillingCycle(start, end, dueAfter(end));
  }
}
