import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BudgetNotificationService {
  static final BudgetNotificationService _instance =
      BudgetNotificationService._internal();
  factory BudgetNotificationService() => _instance;
  BudgetNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const androidInit =
        AndroidInitializationSettings('ic_notification');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  Future<bool> hasPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return (await android?.areNotificationsEnabled()) ?? false;
  }

  Future<void> showBudgetExceeded(
      Budget budget, AppCategory category, double spentAmount) async {
    if (!(await hasPermission())) return;
    final overAmount = spentAmount - budget.amount;
    if (overAmount <= 0) return;


    // Stable ID that resets daily so budget alerts don't spam.
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    final seenKey = 'nexo_budget_alert_${budget.id}';
    if (prefs.getString(seenKey) == today) return;
    final id = ('budget_${budget.id}_$today').hashCode & 0x7FFFFFFF;

    const androidDetails = AndroidNotificationDetails(
      'expensy_budget',
      'Alertas de orçamento e objetivos',
      channelDescription:
          'Avisos de orçamentos ultrapassados e objetivos alcançados.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      enableVibration: true,
      playSound: true,
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id,
      'Orçamento ultrapassado',
      'Um orçamento ultrapassou o limite. Confira os detalhes no Nexo.',
      details,
    );
    await prefs.setString(seenKey, today);
  }

  Future<void> showGoalCompleted(SavingsGoal goal) async {
    if (!(await hasPermission())) return;


    // Stable ID that resets daily.
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final id = ('goal_${goal.id}_$today').hashCode & 0x7FFFFFFF;

    const androidDetails = AndroidNotificationDetails(
      'expensy_budget',
      'Alertas de orçamento e objetivos',
      channelDescription:
          'Avisos de orçamentos ultrapassados e objetivos alcançados.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      enableVibration: true,
      playSound: true,
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id,
      'Objetivo alcançado',
      'Você alcançou um objetivo. Confira os detalhes no Nexo!',
      details,
    );
  }
}
