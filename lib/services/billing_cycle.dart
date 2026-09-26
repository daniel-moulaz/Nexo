/// Closing day belongs to the invoice being closed, regardless of time of day.
class BillingCycle {
  final DateTime start;
  final DateTime end;
  final DateTime? due;
  const BillingCycle(this.start, this.end, this.due);

  static DateTime date(int year, int month, int day) {
    final base = DateTime(year, month);
    return DateTime(base.year, base.month,
        day.clamp(1, DateTime(base.year, base.month + 1, 0).day));
  }

  static BillingCycle forDate(DateTime purchase, int? closingDay, int? dueDay) {
    final day = DateTime(purchase.year, purchase.month, purchase.day);
    final closing = closingDay ?? DateTime(day.year, day.month + 1, 0).day;
    var end = date(day.year, day.month, closing);
    if (day.isAfter(end)) end = date(day.year, day.month + 1, closing);
    final start = closingDay == null
        ? DateTime(end.year, end.month)
        : date(end.year, end.month - 1, closing).add(const Duration(days: 1));
    DateTime? due;
    if (dueDay != null) {
      due = date(end.year, end.month, dueDay);
      if (!due.isAfter(end)) due = date(end.year, end.month + 1, dueDay);
    }
    return BillingCycle(start, end, due);
  }
}
