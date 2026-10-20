// Interactive QA entrypoint. Never ship this target; requires the nativeqa ID.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../lib/database/db_helper.dart';
import '../lib/models/models.dart';
import '../lib/providers/app_provider.dart';
import '../lib/l10n/app_localizations.dart';
import '../lib/screens/notification_inbox_screen.dart';
import '../lib/services/notification_inbox.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if ((await PackageInfo.fromPlatform()).packageName !=
      'com.ma.expensy.nativeqa') {
    throw StateError('Requires isolated nativeqa application');
  }
  await initializeDateFormatting('pt_BR');
  final app = AppProvider();
  app.settings.currency = 'BRL';
  app.settings.languageCode = 'pt';
  app.settings.budgetAlertsEnabled = false;
  var accounts = await DBHelper.getAccounts();
  if (accounts.isEmpty) {
    await DBHelper.insertAccount(Account(
        id: 'qa-bank',
        name: 'Conta de teste',
        type: 'bank',
        balance: 100,
        currency: 'BRL',
        colorValue: 0xff00695c));
    await DBHelper.insertCategory(AppCategory(
        id: 'qa-food',
        name: 'Alimentação',
        type: 'expense',
        colorValue: 0xff00695c));
    accounts = await DBHelper.getAccounts();
  }
  app.accounts = accounts;
  app.categories = await DBHelper.getCategories();
  app.transactions = await DBHelper.getTransactions();
  await NotificationInbox.channel.invokeMethod('configure', {
    'enabled': true,
    'apps': ['com.android.shell']
  });
  final folder = await getApplicationSupportDirectory();
  var writing = false;
  Future<void> report() async {
    if (writing) return;
    writing = true;
    try {
      final db = await DBHelper.database;
      await File('${folder.path}/notification-qa.json').writeAsString(
          jsonEncode({
            'accounts': await db.query('accounts', columns: ['id', 'balance']),
            'transactions': await db.query('transactions'),
            'suggestions': await db.query('notification_suggestions'),
          }),
          flush: true);
    } finally {
      writing = false;
    }
  }

  await report();
  Timer.periodic(const Duration(seconds: 1), (_) => report());
  runApp(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NotificationInboxScreen())));
}
