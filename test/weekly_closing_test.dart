import 'package:expensy/services/cash_forecast.dart';
import 'package:expensy/services/financial_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final forecast = CashForecast(1000, 1000, const [], const []);
  Map<String, dynamic> prefs({bool weekly = true, String? time}) => {
        ...FinancialReminders.defaults,
        'weekly': weekly,
        if (time != null) 'weeklyTime': time,
      };

  test('off by default and when disabled', () {
    expect(FinancialReminders.defaults['weekly'], false);
    expect(
        ReminderPlanner.build(
            forecast, prefs(weekly: false), DateTime(2026, 10, 20, 9)),
        isEmpty);
  });

  test('next four Sundays at 22:00, routed to the 7-day review', () {
    final plans =
        ReminderPlanner.build(forecast, prefs(), DateTime(2026, 10, 20, 9));
    expect(plans.map((p) => p.at), [
      DateTime(2026, 10, 25, 22),
      DateTime(2026, 11, 1, 22),
      DateTime(2026, 11, 8, 22),
      DateTime(2026, 11, 15, 22),
    ]);
    expect(plans.every((p) => p.at.weekday == DateTime.sunday), true);
    expect(plans.every((p) => p.route == weeklyReviewRoute), true);
    expect(plans.map((p) => p.id).toSet().length, 4, reason: 'stable ids');
  });

  test('on Sunday: still tonight before 22h, next week after', () {
    final before =
        ReminderPlanner.weekly(prefs(), DateTime(2026, 10, 25, 21, 59));
    expect(before.first.at, DateTime(2026, 10, 25, 22));
    final after = ReminderPlanner.weekly(prefs(), DateTime(2026, 10, 25, 22));
    expect(after.first.at, DateTime(2026, 11, 1, 22));
  });

  test('custom time is respected and invalid values fall back safely', () {
    expect(
        ReminderPlanner.weekly(prefs(time: '20:30'), DateTime(2026, 10, 20))
            .first
            .at,
        DateTime(2026, 10, 25, 20, 30));
    expect(
        ReminderPlanner.weekly(prefs(time: 'x'), DateTime(2026, 10, 20))
            .first
            .at,
        DateTime(2026, 10, 25, 22));
  });

  test('notification text never carries amounts or names', () {
    final body =
        ReminderPlanner.weekly(prefs(), DateTime(2026, 10, 20)).first.body;
    expect(RegExp(r'\d').hasMatch(body.replaceAll('7 dias', '')), false);
    expect(body.contains('R\$'), false);
  });

  test('same plan keys across refreshes avoid rescheduling churn', () {
    final a = ReminderPlanner.weekly(prefs(), DateTime(2026, 10, 20, 9));
    final b = ReminderPlanner.weekly(prefs(), DateTime(2026, 10, 21, 18));
    expect(a.map((p) => p.key), b.map((p) => p.key));
  });
}
