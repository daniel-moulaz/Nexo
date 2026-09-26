import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import '../providers/app_provider.dart';
import '../database/db_helper.dart';
import 'cash_forecast.dart';

class ReminderPlan {
  final String key, body;
  final DateTime at;
  const ReminderPlan(this.key, this.body, this.at);
  int get id {
    var hash = 2166136261;
    for (final c in key.codeUnits) {
      hash = ((hash ^ c) * 16777619) & 0x7fffffff;
    }
    return 1000000000 + hash % 900000000;
  }
}

class ReminderPlanner {
  static List<ReminderPlan> build(
      CashForecast forecast, Map<String, dynamic> prefs, DateTime now) {
    final plans = <ReminderPlan>[];
    void add(String key, String body, DateTime date, int days) {
      final day = date.subtract(Duration(days: days));
      final at = DateTime(day.year, day.month, day.day, 9);
      final customTimeToday = key.startsWith('recurring:') &&
          at.year == now.year &&
          at.month == now.month &&
          at.day == now.day;
      if ((at.isAfter(now) || customTimeToday) &&
          at.isBefore(now.add(const Duration(days: 32))))
        plans.add(ReminderPlan('$key:${at.toIso8601String()}', body, at));
    }

    for (final event in forecast.events) {
      final type = switch (event.kind) {
        'closing' => 'closing',
        'invoice' => 'invoice',
        'recurring' => 'recurring',
        _ => event.amount >= 0 ? 'income' : 'bills'
      };
      if (prefs[type] != true) continue;
      final body = switch (type) {
        'closing' => 'Um cartão fecha hoje. Confira a agenda.',
        'invoice' => 'Há uma fatura aguardando pagamento. Confira a agenda.',
        'income' => 'Há uma receita prevista. Confirme o recebimento no Nexo.',
        'recurring' => 'Há uma ocorrência aguardando sua confirmação.',
        _ => 'Há uma conta a vencer. Confira a agenda.'
      };
      final offsets = (type == 'bills' || type == 'invoice')
          ? ((prefs['days'] as List?) ?? [3, 1, 0]).cast<int>()
          : [0];
      for (final offset in offsets) {
        add('${event.kind}:${event.id}:${event.date.toIso8601String()}:$offset',
            body, event.date, offset);
      }
      // One follow-up per date, never an automatic financial settlement.
      if (type != 'closing' &&
          event.date.isBefore(DateTime(now.year, now.month, now.day)))
        add(
            'overdue:${event.kind}:${event.id}',
            'Há um compromisso em aberto. Revise a agenda do Nexo.',
            now.add(const Duration(days: 1)),
            0);
    }
    if (prefs['forecast'] == true && forecast.projected < 0)
      add(
          'negative',
          'Seu saldo previsto pode ficar negativo. Revise os próximos compromissos.',
          now.add(const Duration(days: 1)),
          0);
    return plans;
  }
}

class FinancialReminders {
  static final instance = FinancialReminders();
  final plugin = FlutterLocalNotificationsPlugin();
  Timer? _debounce;
  bool _running = false;
  Completer<void>? _completion;
  String? lastError;
  static const defaults = <String, dynamic>{
    'bills': false,
    'income': false,
    'recurring': false,
    'closing': false,
    'invoice': false,
    'forecast': false,
    'days': [3, 1, 0]
  };
  Future<Map<String, dynamic>> preferences() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('nexo_reminders');
    return {
      ...defaults,
      if (raw != null) ...Map<String, dynamic>.from(jsonDecode(raw))
    };
  }

  Future<void> save(Map<String, dynamic> values, AppProvider app) async {
    await (await SharedPreferences.getInstance())
        .setString('nexo_reminders', jsonEncode(values));
    await refresh(app);
  }

  void requestRefresh(AppProvider app) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => refresh(app));
  }

  Future<void> refresh(AppProvider app) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_running) {
      await _completion!.future;
      return refresh(app);
    }
    _running = true;
    _completion = Completer<void>();
    try {
      final p = await SharedPreferences.getInstance();
      if (!p.containsKey('nexo_reminders'))
        await p.setString(
            'nexo_reminders',
            jsonEncode({
              ...defaults,
              'recurring': app.recurring.any((r) => r.reminderEnabled),
              'invoice': app.accounts.any((a) => a.creditReminderEnabled)
            }));
      final prefs = await preferences();
      final db = await DBHelper.database;
      final payments = await db.query('card_invoice_payments');
      final now = DateTime.now();
      CashForecast calculate(int days) => CashForecast.calculate(
          now: now,
          until: now.add(Duration(days: days)),
          accounts: app.accounts,
          transactions: app.transactions,
          recurring: app.recurring,
          metadata: app.transactionMetadata,
          invoicePayments: payments,
          convert: app.convertToMain);
      final forecast = calculate(31);
      // Only the next actionable occurrence can need human confirmation.
      final events = forecast.events
          .where((e) =>
              e.kind != 'recurring' ||
              app.recurring.any((r) =>
                  r.id == e.id &&
                  r.reminderEnabled &&
                  DateTime(r.nextActionDate.year, r.nextActionDate.month,
                          r.nextActionDate.day) ==
                      e.date))
          .toList();
      final plans = ReminderPlanner.build(
              CashForecast(forecast.current, calculate(7).projected, events,
                  forecast.warnings),
              prefs,
              now)
          .map((plan) {
            final recurring = app.recurring
                .where((r) =>
                    plan.key.startsWith('recurring:${r.id}:') ||
                    plan.key.startsWith('overdue:recurring:${r.id}:'))
                .firstOrNull;
            if (recurring == null) return plan;
            final time = recurring.reminderTime.split(':');
            final at = DateTime(
                plan.at.year,
                plan.at.month,
                plan.at.day,
                int.tryParse(time.first) ?? 9,
                time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0);
            return ReminderPlan('${plan.key}:$at', plan.body, at);
          })
          .where((plan) => plan.at.isAfter(now))
          .toList();
      if (prefs['recurring'] == true) {
        for (final r in app.recurring.where((r) =>
            r.reminderEnabled && r.earlyReminderEnabled && r.canComplete)) {
          final date = r.nextActionDate.subtract(const Duration(days: 2));
          final time = r.reminderTime.split(':');
          final at = DateTime(
              date.year,
              date.month,
              date.day,
              int.tryParse(time.first) ?? 9,
              time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0);
          if (at.isAfter(now) && at.isBefore(now.add(const Duration(days: 32))))
            plans.add(ReminderPlan('recurring-early:${r.id}:$at',
                'Uma ocorrência vence em 2 dias. Confira no Nexo.', at));
        }
      }
      final old = Map<String, dynamic>.from(
          jsonDecode(p.getString('nexo_reminder_jobs') ?? '{}'));
      final wanted = {for (final plan in plans) '${plan.id}': plan};
      for (final id in old.keys.where((id) => !wanted.containsKey(id))) {
        await plugin.cancel(int.parse(id));
      }
      tz_data.initializeTimeZones();
      for (final entry in wanted.entries) {
        final plan = entry.value;
        if (old[entry.key] == plan.key) continue;
        await plugin.zonedSchedule(
            plan.id,
            'Nexo',
            plan.body,
            tz.TZDateTime.from(plan.at.toUtc(), tz.UTC),
            const NotificationDetails(
                android: AndroidNotificationDetails(
                    'nexo_financial_reminders', 'Lembretes financeiros',
                    channelDescription:
                        'Contas, receitas, recorrentes e cartões',
                    visibility: NotificationVisibility.private,
                    importance: Importance.defaultImportance)),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime);
      }
      await p.setString('nexo_reminder_jobs',
          jsonEncode({for (final e in wanted.entries) e.key: e.value.key}));
      lastError = null;
    } catch (_) {
      lastError =
          'Não foi possível atualizar os lembretes. Confira a permissão de notificações.';
    } finally {
      _running = false;
      _completion!.complete();
    }
  }
}
