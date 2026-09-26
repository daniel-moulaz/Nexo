import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';

/// Compatibility adapter: removes legacy jobs. FinancialReminders owns new jobs.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void> initialize() async {
    await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification')));
  }

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return false;
    return await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<bool> hasPermission() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled() ??
      false;
  Future<void> cancelReminder(String id) async {
    await _plugin.cancel(id.hashCode & 0x7fffffff);
    await _plugin.cancel('${id}_adv'.hashCode & 0x7fffffff);
  }

  Future<void> scheduleReminder(RecurringPayment r, String currency) =>
      cancelReminder(r.id);
  Future<void> rescheduleAll(
      List<RecurringPayment> payments, String currency) async {
    for (final r in payments) {
      await cancelReminder(r.id);
    }
  }
}
