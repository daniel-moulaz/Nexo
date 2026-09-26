import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';

/// Compatibility adapter: central reminders replace unconditional bill alerts.
class CreditReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void> initialize() async {
    await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification')));
  }

  Future<bool> hasPermission() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled() ??
      false;
  Future<void> cancelReminder(String id) async {
    var hash = 0;
    for (final c in id.codeUnits) {
      hash = 31 * hash + c;
    }
    await _plugin.cancel((hash & 0x7fffffff) + 800000);
    await _plugin.cancel((hash & 0x7fffffff) + 900000);
  }

  Future<void> scheduleReminder(Account account) => cancelReminder(account.id);
  Future<void> rescheduleAll(List<Account> accounts) async {
    for (final a in accounts.where((a) => a.type == 'credit')) {
      await cancelReminder(a.id);
    }
  }
}
