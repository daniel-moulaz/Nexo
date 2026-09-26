// lib/providers/app_provider.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import '../database/db_helper.dart';
import '../services/transaction_metadata_service.dart';
import '../services/finance_rules.dart';
import '../services/billing_cycle.dart';
import '../services/exchange_rate_service.dart';
import '../services/notification_service.dart';
import '../services/lended_notification_service.dart';
import '../services/budget_notification_service.dart';
import '../services/daily_reminder_service.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import 'package:home_widget/home_widget.dart';
import '../services/credit_reminder_service.dart';
import '../services/loan_reminder_service.dart';
import '../theme/app_theme.dart';

class AppSettings {
  String currency;
  String themeSeed;
  String themeMode; // system|light|dark  ('amoled' is migrated on load)
  String weekStart; // monday|sunday
  bool hideBalance;
  String userName;
  bool onboarded;
  String appFont; // key into kFonts; 'default' = system/Roboto
  bool amoledSurfaces;
  bool
      dynamicColorEnabled; // pure-black surfaces when dark — decoupled from themeMode
  String languageCode; // 'system'|'en'|'ar'|'fr'|'de'|'hi'
  bool budgetAlertsEnabled;
  bool dailyReminderEnabled;
  String dailyReminderTime;
  bool hapticsEnabled;
  List<String> pinnedWidgetAccountIds;

  AppSettings({
    this.currency = 'BRL',
    this.themeSeed = 'violet',
    this.themeMode = 'dark',
    this.weekStart = 'monday',
    this.hideBalance = false,
    this.userName = '',
    this.onboarded = false,
    this.appFont = 'default',
    this.amoledSurfaces = false,
    this.dynamicColorEnabled = false,
    this.languageCode = 'pt',
    this.budgetAlertsEnabled = true,
    this.dailyReminderEnabled = false,
    this.dailyReminderTime = '22:00',
    this.hapticsEnabled = true,
    this.pinnedWidgetAccountIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'themeSeed': themeSeed,
        'themeMode': themeMode,
        'weekStart': weekStart,
        'hideBalance': hideBalance,
        'userName': userName,
        'onboarded': onboarded,
        'appFont': appFont,
        'amoledSurfaces': amoledSurfaces,
        'dynamicColorEnabled': dynamicColorEnabled,
        'languageCode': languageCode,
        'budgetAlertsEnabled': budgetAlertsEnabled,
        'dailyReminderEnabled': dailyReminderEnabled,
        'dailyReminderTime': dailyReminderTime,
        'hapticsEnabled': hapticsEnabled,
        'pinnedWidgetAccountIds': pinnedWidgetAccountIds,
      };

  static const _validThemeModes = {'system', 'light', 'dark'};
  // 'amoled' is legacy — migrated to themeMode:'dark' + amoledSurfaces:true
  static const _validSeeds = {
    'violet',
    'blue',
    'green',
    'rose',
    'amber',
    'teal',
    'orange',
    'indigo',
    'cyan',
    'pink',
    'lime',
    'deep_purple',
    'crimson',
    'midnight',
    'forest',
    'mint',
    'olive',
    'sage',
    'sky',
    'navy',
    'cobalt',
    'ocean',
    'coral',
    'gold',
    'slate',
    'magenta',
    'turquoise',
    'brown',
    'lavender',
  };
  static const _validFonts = {
    'default',
    'plus_jakarta_sans',
    'dm_sans',
    'inter',
    'nunito_sans',
    'space_grotesk',
    'outfit',
    'sora',
    'poppins',
    'nunito',
  };
  static final _validLanguages = {
    'system',
    ...AppLocalizations.supportedLocales.map((l) => l.languageCode),
  };

  static AppSettings fromJson(Map<String, dynamic> j) {
    String seed = (j['themeSeed'] as String?) ?? 'violet';
    bool wasAmoled = seed == 'pitch_black';
    if (wasAmoled) seed = 'midnight';
    if (!_validSeeds.contains(seed)) seed = 'violet';

    String mode;
    bool legacyAmoled = false;
    if (j.containsKey('themeMode') && j['themeMode'] != null) {
      mode = j['themeMode'] as String;
      // Migrate legacy 'amoled' themeMode → 'dark' + amoledSurfaces:true
      if (mode == 'amoled') {
        mode = 'dark';
        legacyAmoled = true;
      } else if (!_validThemeModes.contains(mode)) mode = 'dark';
    } else {
      mode = (j['darkMode'] as bool? ?? false) ? 'dark' : 'system';
    }
    if (wasAmoled) mode = 'dark';

    // amoledSurfaces: prefer stored value; fall back to any legacy amoled flag.
    final amoled =
        (j['amoledSurfaces'] as bool?) ?? (wasAmoled || legacyAmoled);

    String font = (j['appFont'] as String?) ?? 'default';
    if (!_validFonts.contains(font)) font = 'default';

    String lang = (j['languageCode'] as String?) ?? 'system';
    if (!_validLanguages.contains(lang)) lang = 'system';

    return AppSettings(
      currency: (j['currency'] as String?) ?? 'EGP',
      themeSeed: seed,
      themeMode: mode,
      weekStart: (j['weekStart'] as String?) ?? 'monday',
      hideBalance: (j['hideBalance'] as bool?) ?? false,
      userName: (j['userName'] as String?) ?? '',
      onboarded: (j['onboarded'] as bool?) ?? false,
      appFont: font,
      amoledSurfaces: amoled,
      dynamicColorEnabled: (j['dynamicColorEnabled'] as bool?) ?? false,
      languageCode: lang,
      budgetAlertsEnabled: (j['budgetAlertsEnabled'] as bool?) ?? true,
      dailyReminderEnabled: (j['dailyReminderEnabled'] as bool?) ?? false,
      dailyReminderTime: (j['dailyReminderTime'] as String?) ?? '22:00',
      hapticsEnabled: (j['hapticsEnabled'] as bool?) ?? true,
      pinnedWidgetAccountIds: (j['pinnedWidgetAccountIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class AppProvider extends ChangeNotifier {
  AppSettings settings = AppSettings();
  List<Account> accounts = [];
  List<AppCategory> categories = [];
  List<AppTransaction> transactions = [];
  List<RecurringPayment> recurring = [];
  List<WishlistItem> wishlist = [];
  List<LendedPerson> lendedPeople = [];
  List<LendedMoney> lended = [];
  List<AssetItem> assets = [];
  List<Budget> budgets = [];
  List<SavingsGoal> savingsGoals = [];
  List<SavingsContribution> savingsContributions = [];
  List<NetWorthSnapshot> netWorthSnapshots = [];

  /// Total row count in `recurring_history` — kept for display purposes
  /// (e.g. the Backup screen's "what's included" list) without needing to
  /// load every history row for every recurring payment into memory.
  int recurringHistoryCount = 0;

  // ── Exchange rates ────────────────────────────────────────────────────
  Map<String, double> exchangeRates = {};
  bool ratesLoaded = false;
  bool ratesFetching = false;
  DateTime? ratesLastFetched;

  // ── Recurring history (lazy cache) ────────────────────────────────────
  final Map<String, List<RecurringHistoryEntry>> _historyCache = {};

  List<Loan> loans = [];
  List<LoanPayment> loanPayments = [];

  final _erService = ExchangeRateService();
  final _notif = NotificationService();
  final _lendedNotif = LendedNotificationService();
  final _budgetNotif = BudgetNotificationService();
  final _dailyNotif = DailyReminderService();
  final _loanNotif = LoanReminderService();

  bool _loaded = false;
  bool get loaded => _loaded;

  final _uuid = const Uuid();
  String newId() => _uuid.v4();

  // ── Boot ─────────────────────────────────────────────────────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('settings');
    if (raw != null) {
      settings = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    accounts = await DBHelper.getAccounts();
    categories = await DBHelper.getCategories();
    transactions = await DBHelper.getTransactions();
    transactionMetadata = await TransactionMetadataService.instance
        .getForMany(transactions.map((t) => t.id));
    recurring = await DBHelper.getRecurring();
    wishlist = await DBHelper.getWishlist();
    lendedPeople = await DBHelper.getLendedPeople();
    lended = await DBHelper.getLended();
    assets = await DBHelper.getAssets();
    budgets = await DBHelper.getBudgets();
    savingsGoals = await DBHelper.getSavingsGoals();
    savingsContributions = await DBHelper.getAllSavingsContributions();
    loans = await DBHelper.getLoans();
    loanPayments = await DBHelper.getAllLoanPayments();
    netWorthSnapshots = await DBHelper.getNetWorthSnapshots();
    recurringHistoryCount = await DBHelper.getRecurringHistoryCount();
    _loaded = true;
    notifyListeners();

    _lendedNotif.rescheduleAllLended(lended, settings.currency);
    _notif.rescheduleAll(recurring, settings.currency);
    _loanNotif.rescheduleAllLoans(loans, settings.currency);
    CreditReminderService().rescheduleAll(accounts);
    if (settings.dailyReminderEnabled) {
      await _dailyNotif.scheduleDailyReminder(settings.dailyReminderTime);
    } else {
      await _dailyNotif.cancelDailyReminder();
    }

    _loadRates();
    await _recordNetWorthSnapshot();
    await updateHomeWidgets();
  }

  Future<void> updateHomeWidgets() async {
    try {
      final pinnedIds = settings.pinnedWidgetAccountIds;
      final pinnedAccounts =
          accounts.where((a) => pinnedIds.contains(a.id)).take(3).toList();
      if (pinnedAccounts.isEmpty) {
        pinnedAccounts.addAll(accounts.take(3));
      }
      final accountsJson = jsonEncode(pinnedAccounts
          .map((a) => {
                'name': a.name,
                'balance': settings.hideBalance
                    ? '••••'
                    : formatAmount(a.balance,
                        a.currency.isNotEmpty ? a.currency : settings.currency),
              })
          .toList());
      await HomeWidget.saveWidgetData('accounts_widget_data', accountsJson);
      await HomeWidget.updateWidget(name: 'AccountsWidgetProvider');

      final budgetData = budgets.map((b) {
        final spent = budgetSpent(b);
        return {
          'hidden': settings.hideBalance,
          'category': settings.hideBalance
              ? 'Valores ocultos'
              : categoryById(b.categoryId)?.name ?? 'Orçamento',
          'spent': settings.hideBalance ? 0.0 : spent,
          'amount': settings.hideBalance ? 0.0 : b.amount,
          'progress':
              !settings.hideBalance && b.amount > 0 ? spent / b.amount : 0.0,
          'exceeded': !settings.hideBalance && spent > b.amount,
          'currency': settings.currency,
        };
      }).toList();
      await HomeWidget.saveWidgetData(
          'budget_widget_data', jsonEncode(budgetData));
      await HomeWidget.updateWidget(name: 'BudgetWidgetProvider');
    } catch (e) {
      debugPrint('Error updating home widgets');
    }
  }

  Future<void> _recordNetWorthSnapshot() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final existing = await DBHelper.getNetWorthSnapshotForDate(today);
      if (existing != null) return;
      final snap = NetWorthSnapshot(
        id: const Uuid().v4(),
        date: today,
        totalAccounts: totalBalanceAll,
        totalAssets: totalAssetsValue,
        netWorth: totalBalanceAll + totalAssetsValue,
        currency: settings.currency,
      );
      await DBHelper.insertNetWorthSnapshot(snap);
      netWorthSnapshots.add(snap);
    } catch (e) {
      debugPrint('Error recording net worth snapshot');
    }
  }

  Future<void> _loadRates({bool forceNetwork = false}) async {
    ratesFetching = true;
    notifyListeners();

    if (forceNetwork) {
      // Full blocking refresh — fetch main rates + gold, then update UI once.
      final fresh = await _erService.forceRefresh();
      Map<String, double> rates = fresh ?? exchangeRates;
      final hasXau = rates.containsKey('XAU') && (rates['XAU'] ?? 0) > 0;
      if (!hasXau) {
        final xauRate = await _erService.fetchGoldRate();
        if (xauRate != null) {
          rates = Map.from(rates)..['XAU'] = xauRate;
          await _erService.patchCachedXau(xauRate);
        }
      }
      exchangeRates = rates;
      ratesLoaded = true;
      ratesFetching = false;
      ratesLastFetched = await _erService.lastFetchedAt();
      notifyListeners();
      await _refreshGoldBalances();
    } else {
      // 1. Serve cached rates immediately so the UI is not blocked.
      final cached = await _erService.getCached();
      if (cached != null && cached.isNotEmpty) {
        var rates = cached;
        final hasXauCached =
            rates.containsKey('XAU') && (rates['XAU'] ?? 0) > 0;
        if (!hasXauCached) {
          final xauRate = await _erService.fetchGoldRate();
          if (xauRate != null) {
            rates = Map.from(rates)..['XAU'] = xauRate;
            await _erService.patchCachedXau(xauRate);
          }
        }
        exchangeRates = rates;
        ratesLoaded = true;
        ratesFetching = false;
        ratesLastFetched = await _erService.lastFetchedAt();
        notifyListeners();
        await _refreshGoldBalances();
      }

      // 2. If cache is stale (or empty), fetch fresh in the background and
      //    update the provider when done — this is what was missing before.
      final isStale = !(await _erService.isFresh());
      if (isStale) {
        // Re-set fetching flag so UI shows spinner during background fetch.
        ratesFetching = true;
        notifyListeners();
        final fresh = await _erService.forceRefresh();
        if (fresh != null && fresh.isNotEmpty) {
          var rates = fresh;
          final hasXau = rates.containsKey('XAU') && (rates['XAU'] ?? 0) > 0;
          if (!hasXau) {
            final xauRate = await _erService.fetchGoldRate();
            if (xauRate != null) {
              rates = Map.from(rates)..['XAU'] = xauRate;
              await _erService.patchCachedXau(xauRate);
            }
          }
          exchangeRates = rates;
          ratesLoaded = true;
          ratesLastFetched = await _erService.lastFetchedAt();
        }
        ratesFetching = false;
        notifyListeners();
        await _refreshGoldBalances();
      }
    }
  }

  Future<void> refreshRates() => _loadRates(forceNetwork: true);

  Future<void> _refreshGoldBalances() async {
    if (exchangeRates.isEmpty) return;
    if (!exchangeRates.containsKey('XAU')) return;

    bool changed = false;
    for (int i = 0; i < accounts.length; i++) {
      final acc = accounts[i];
      if (!acc.isGold) continue;
      final grams = acc.goldGrams;
      final karat = acc.goldKarat;
      if (grams == null || grams <= 0 || karat == null) continue;

      final xauAmount = grams * (karat / 24) / 31.1035;
      final newBalance =
          _erService.convert(xauAmount, 'XAU', acc.currency, exchangeRates) ??
              acc.balance;

      if ((newBalance - acc.balance).abs() < 0.001) continue;

      final updated = acc.copyWith(balance: newBalance);
      await DBHelper.updateAccount(updated);
      accounts[i] = updated;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(settings.toJson()));
    notifyListeners();
  }

  void updateSetting(String key, dynamic value) async {
    final oldDailyEnabled = settings.dailyReminderEnabled;
    final oldDailyTime = settings.dailyReminderTime;
    final oldLang = settings.languageCode;

    switch (key) {
      case 'currency':
        settings.currency = value as String;
        break;
      case 'themeSeed':
        settings.themeSeed = value as String;
        break;
      case 'themeMode':
        settings.themeMode = value as String;
        break;
      case 'weekStart':
        settings.weekStart = value as String;
        break;
      case 'hideBalance':
        settings.hideBalance = value as bool;
        break;
      case 'userName':
        settings.userName = value as String;
        break;
      case 'appFont':
        settings.appFont = value as String;
        break;
      case 'amoledSurfaces':
        settings.amoledSurfaces = value as bool;
        break;
      case 'dynamicColorEnabled':
        settings.dynamicColorEnabled = value as bool;
        break;
      case 'languageCode':
        settings.languageCode = value as String;
        break;
      case 'budgetAlertsEnabled':
        settings.budgetAlertsEnabled = value as bool;
        break;
      case 'dailyReminderEnabled':
        settings.dailyReminderEnabled = value as bool;
        break;
      case 'dailyReminderTime':
        settings.dailyReminderTime = value as String;
        break;
      case 'hapticsEnabled':
        settings.hapticsEnabled = value as bool;
        break;
      case 'pinnedWidgetAccountIds':
        settings.pinnedWidgetAccountIds = value as List<String>;
        break;
    }

    _saveSettings();
    notifyListeners();
    if (key == 'hideBalance' || key == 'pinnedWidgetAccountIds')
      await updateHomeWidgets();

    if (oldLang != settings.languageCode) {
      // Handled in main by restarting or notifying.
    }

    if (oldDailyEnabled != settings.dailyReminderEnabled ||
        oldDailyTime != settings.dailyReminderTime) {
      if (settings.dailyReminderEnabled) {
        await _dailyNotif.scheduleDailyReminder(settings.dailyReminderTime);
      } else {
        await _dailyNotif.cancelDailyReminder();
      }
    }
  }

  Future<void> completeOnboarding({
    required String name,
    required String currency,
  }) async {
    settings.userName = name;
    settings.currency = currency;
    settings.onboarded = true;
    await _saveSettings();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  double get totalBalance =>
      accounts.where((a) => !a.excludeFromTotal).fold(0.0, (sum, a) {
        final absBalance = a.balance;
        if (exchangeRates.isEmpty || a.currency == settings.currency) {
          return sum + absBalance;
        }
        return sum +
            (_erService.convert(
                    absBalance, a.currency, settings.currency, exchangeRates) ??
                absBalance);
      });

  double get totalBalanceAll => accounts.fold(0.0, (sum, a) {
        final absBalance = a.balance;
        if (exchangeRates.isEmpty || a.currency == settings.currency) {
          return sum + absBalance;
        }
        return sum +
            (_erService.convert(
                    absBalance, a.currency, settings.currency, exchangeRates) ??
                absBalance);
      });

  double convertToMain(double amount, String fromCurrency) {
    if (fromCurrency == settings.currency || exchangeRates.isEmpty) {
      return amount;
    }
    return _erService.convert(
            amount, fromCurrency, settings.currency, exchangeRates) ??
        amount;
  }

  double? convertBetween(double amount, String from, String to) {
    if (from == to) return amount;
    if (exchangeRates.isEmpty) return null;
    return _erService.convert(amount, from, to, exchangeRates);
  }

  bool canShowConverted(Account account) =>
      ratesLoaded &&
      exchangeRates.isNotEmpty &&
      account.currency != settings.currency &&
      exchangeRates.containsKey(account.currency) &&
      exchangeRates.containsKey(settings.currency);

  bool get goldRatesAvailable =>
      ratesLoaded &&
      exchangeRates.containsKey('XAU') &&
      (exchangeRates['XAU'] ?? 0) > 0;

  double? goldPricePerGram(String currency) {
    if (exchangeRates.isEmpty || !exchangeRates.containsKey('XAU')) return null;
    return _erService.convert(1 / 31.1035, 'XAU', currency, exchangeRates);
  }

  double? computeGoldValue({
    required double grams,
    required int karat,
    required String currency,
  }) {
    if (exchangeRates.isEmpty || !exchangeRates.containsKey('XAU')) return null;
    final xauAmount = grams * (karat / 24) / 31.1035;
    return _erService.convert(xauAmount, 'XAU', currency, exchangeRates);
  }

  Account? accountById(String id) =>
      accounts.where((a) => a.id == id).firstOrNull;
  AppCategory? categoryById(String id) =>
      categories.where((c) => c.id == id).firstOrNull;
  LendedPerson? personById(String id) =>
      lendedPeople.where((p) => p.id == id).firstOrNull;

  // ── Accounts ─────────────────────────────────────────────────────────
  bool toggleWidgetPin(String id) {
    final pins = List<String>.from(settings.pinnedWidgetAccountIds);
    if (pins.contains(id)) {
      pins.remove(id);
    } else {
      if (pins.length >= 3) return false;
      pins.add(id);
    }
    updateSetting('pinnedWidgetAccountIds', pins);
    return true;
  }

  Future<void> addAccount(Account a) => _persistAccount(a, create: true);
  Future<void> updateAccount(Account a) => _persistAccount(a, create: false);

  Future<void> _persistAccount(Account a, {required bool create}) async {
    final previouslyReminded =
        accountById(a.id)?.creditReminderEnabled ?? false;
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      final previous =
          await txn.query('accounts', where: 'id = ?', whereArgs: [a.id]);
      final oldBalance = previous.isEmpty
          ? 0.0
          : (previous.first['balance'] as num).toDouble();
      if (create) {
        await txn.insert('accounts', a.toMap());
      } else {
        await txn
            .update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
      }
      final difference = a.balance - oldBalance;
      if (a.type == 'credit' && difference.abs() > .005) {
        final tx = AppTransaction(
            id: newId(),
            type: difference < 0 ? 'expense' : 'income',
            amount: difference.abs(),
            description: create
                ? 'Saldo inicial do cartão'
                : 'Ajuste do saldo do cartão',
            accountId: a.id,
            categoryId: '',
            date: DateTime.now(),
            currency: a.currency);
        await txn.insert('transactions', tx.toMap());
        await txn.insert(
            'transaction_metadata',
            TransactionMetadata(
                    transactionId: tx.id,
                    excludeFromSpending: true,
                    source: 'opening_balance')
                .toMap());
      }
    });
    await _reloadLedger();
    if (previouslyReminded) await CreditReminderService().cancelReminder(a.id);
    if (a.type == 'credit' && a.creditReminderEnabled)
      await CreditReminderService().scheduleReminder(a);
  }

  Future<VoidCallback> deleteAccountWithUndo(String id) async {
    final a = accounts.firstWhere((acc) => acc.id == id);
    await deleteAccount(id);
    return () async {
      await addAccount(a);
    };
  }

  Future<void> deleteAccount(String id) async {
    await CreditReminderService().cancelReminder(id);
    await DBHelper.deleteAccount(id);
    accounts = await DBHelper.getAccounts();
    transactions = await DBHelper.getTransactions();
    notifyListeners();
  }

  Future<void> _updateAccountBalance(String id, double delta) async {
    final acc = accountById(id);
    if (acc == null) return;
    if (acc.isGold) return;
    await DBHelper.updateAccount(acc.copyWith(balance: acc.balance + delta));
    accounts = await DBHelper.getAccounts();
  }

  // ── Categories ────────────────────────────────────────────────────────
  Future<void> addCategory(AppCategory c) async {
    await DBHelper.insertCategory(c);
    categories = await DBHelper.getCategories();
    notifyListeners();
  }

  Future<void> updateCategory(AppCategory c) async {
    await DBHelper.updateCategory(c);
    categories = await DBHelper.getCategories();
    notifyListeners();
  }

  Future<void> deleteCategory(String id) async {
    await DBHelper.deleteCategory(id);
    categories = await DBHelper.getCategories();
    notifyListeners();
  }

  // ── Transactions ──────────────────────────────────────────────────────

  double _txDelta(AppTransaction t, {bool reverse = false}) {
    final acc = accountById(t.accountId);
    final accCurrency = acc?.currency ?? settings.currency;
    final txCurrency = t.currency.isEmpty ? accCurrency : t.currency;

    double amount = t.amount;
    if (txCurrency != accCurrency && exchangeRates.isNotEmpty) {
      amount =
          _erService.convert(amount, txCurrency, accCurrency, exchangeRates) ??
              amount;
    }
    final sign = t.type == 'income' ? 1.0 : -1.0;
    return (reverse ? -sign : sign) * amount;
  }

  Map<String, TransactionMetadata> transactionMetadata = {};

  Future<void> _reloadLedger() async {
    transactions = await DBHelper.getTransactions();
    accounts = await DBHelper.getAccounts();
    transactionMetadata = await TransactionMetadataService.instance
        .getForMany(transactions.map((t) => t.id));
    TransactionMetadataService.instance.revision.value++;
    notifyListeners();
    await updateHomeWidgets();
  }

  Future<void> addTransaction(AppTransaction t,
      {TransactionMetadata? metadata, bool generateInstallments = true}) async {
    final db = await DBHelper.database;
    if (!t.amount.isFinite ||
        t.amount <= 0 ||
        accountById(t.accountId) == null ||
        !['income', 'expense'].contains(t.type)) {
      throw ArgumentError('Conta, tipo ou valor inválido.');
    }
    final meta = metadata ?? TransactionMetadata(transactionId: t.id);
    await db.transaction((txn) async {
      final current = meta.installmentCurrent ?? 1;
      final total =
          generateInstallments ? meta.installmentTotal ?? current : current;
      if (current < 1 || total < current || total > 600)
        throw ArgumentError('Parcelas inválidas (máximo 600).');
      for (var installment = current; installment <= total; installment++) {
        final first = installment == current;
        final date = BillingCycle.date(
            t.date.year, t.date.month + installment - current, t.date.day);
        final tx = first
            ? t
            : AppTransaction(
                id: '${t.id}:installment:$installment',
                type: t.type,
                amount: t.amount,
                description: t.description,
                accountId: t.accountId,
                categoryId: t.categoryId,
                date: date,
                note: t.note,
                currency: t.currency);
        final itemMeta = first
            ? meta
            : TransactionMetadata(
                transactionId: tx.id,
                subcategory: meta.subcategory,
                status: accountById(t.accountId)?.type == 'credit'
                    ? 'paid'
                    : 'pending',
                dueDate: date,
                expenseClass: meta.expenseClass,
                excludeFromSpending: meta.excludeFromSpending,
                installmentCurrent: installment,
                installmentTotal: total,
                source: 'installment',
                affectsBalance: meta.affectsBalance);
        await txn.insert('transactions', tx.toMap());
        await txn.insert('transaction_metadata', itemMeta.toMap());
        if (!itemMeta.isPending && itemMeta.affectsBalance) {
          await txn.rawUpdate(
              'UPDATE accounts SET balance = balance + ? WHERE id = ?',
              [_txDelta(tx), tx.accountId]);
        }
      }
    });
    await _reloadLedger();
    await _checkBudgetAlert(t);
  }

  Future<void> updateTransaction(
      AppTransaction updated, AppTransaction original,
      {TransactionMetadata? metadata}) async {
    final old = await TransactionMetadataService.instance.getFor(original.id);
    if (old.source.startsWith('transfer:'))
      throw StateError(
          'Para alterar uma transferência, exclua o par e registre novamente.');
    final meta = metadata ?? old;
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      if (!old.isPending && old.affectsBalance) {
        await txn.rawUpdate(
            'UPDATE accounts SET balance = balance + ? WHERE id = ?',
            [_txDelta(original, reverse: true), original.accountId]);
      }
      if (!meta.isPending && meta.affectsBalance) {
        await txn.rawUpdate(
            'UPDATE accounts SET balance = balance + ? WHERE id = ?',
            [_txDelta(updated), updated.accountId]);
      }
      await txn.update('transactions', updated.toMap(),
          where: 'id = ?', whereArgs: [updated.id]);
      await txn.delete('transaction_metadata',
          where: 'transaction_id = ?', whereArgs: [updated.id]);
      await txn.insert('transaction_metadata', meta.toMap());
    });
    await _reloadLedger();
    await _checkBudgetAlert(updated);
  }

  Future<void> _checkBudgetAlert(AppTransaction t) async {
    if (!settings.budgetAlertsEnabled) return;
    if (t.type != 'expense') return;
    final b = budgetForCategory(t.categoryId);
    if (b == null) return;
    if (budgetExceeded(b)) {
      final cat = categoryById(t.categoryId);
      if (cat != null) {
        await _budgetNotif.showBudgetExceeded(b, cat, budgetSpent(b));
      }
    }
  }

  Future<void> deleteTransaction(String id) async {
    final meta = await TransactionMetadataService.instance.getFor(id);
    final db = await DBHelper.database;
    final ids = meta.source.startsWith('transfer:')
        ? (await db.query('transaction_metadata',
                where: 'source = ?', whereArgs: [meta.source]))
            .map((r) => r['transaction_id'] as String)
            .toList()
        : [id];
    await db.transaction((txn) async {
      for (final txId in ids) {
        final rows =
            await txn.query('transactions', where: 'id = ?', whereArgs: [txId]);
        if (rows.isEmpty) continue;
        final t = AppTransaction.fromMap(rows.first);
        final metas = await txn.query('transaction_metadata',
            where: 'transaction_id = ?', whereArgs: [txId]);
        final m = metas.isEmpty
            ? TransactionMetadata(transactionId: txId)
            : TransactionMetadata.fromMap(metas.first);
        if (!m.isPending && m.affectsBalance) {
          await txn.rawUpdate(
              'UPDATE accounts SET balance = balance + ? WHERE id = ?',
              [_txDelta(t, reverse: true), t.accountId]);
        }
        await txn.delete('card_invoice_payments',
            where: 'id = ?', whereArgs: [txId]);
        await txn.delete('transactions', where: 'id = ?', whereArgs: [txId]);
      }
    });
    await _reloadLedger();
  }

  Future<void> addTransfer({
    required String fromId,
    required String toId,
    required double fromAmount,
    double? toAmount,
    String note = '',
    DateTime? invoiceCycleEnd,
  }) async {
    if (fromId == toId ||
        !fromAmount.isFinite ||
        fromAmount <= 0 ||
        (toAmount != null && (!toAmount.isFinite || toAmount <= 0))) {
      throw ArgumentError('Selecione contas diferentes e um valor positivo.');
    }
    final fromAcc = accountById(fromId);
    final toAcc = accountById(toId);
    final fromCurrency = fromAcc?.currency ?? settings.currency;
    final toCurrency = toAcc?.currency ?? settings.currency;

    final double creditAmount;
    if (toAmount != null) {
      creditAmount = toAmount;
    } else if (fromCurrency == toCurrency) {
      creditAmount = fromAmount;
    } else {
      creditAmount =
          convertBetween(fromAmount, fromCurrency, toCurrency) ?? fromAmount;
    }

    final now = DateTime.now();
    final catId = categories.where((c) => c.type == 'expense').isNotEmpty
        ? categories.firstWhere((c) => c.type == 'expense').id
        : '';

    final debit = AppTransaction(
      id: newId(),
      type: 'expense',
      amount: fromAmount,
      description: 'Transferência enviada',
      accountId: fromId,
      categoryId: catId,
      date: now,
      note: note,
      currency: fromCurrency,
    );
    final credit = AppTransaction(
      id: newId(),
      type: 'income',
      amount: creditAmount,
      description: 'Transferência recebida',
      accountId: toId,
      categoryId: catId,
      date: now,
      note: note,
      currency: toCurrency,
    );
    if (fromAcc == null || toAcc == null)
      throw StateError('Conta não encontrada.');
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      if (invoiceCycleEnd != null) {
        final key = DateFormat('yyyy-MM-dd').format(invoiceCycleEnd);
        final cycle = BillingCycle.forDate(
            invoiceCycleEnd, toAcc.statementDay, toAcc.dueDay);
        final purchaseRows = await txn.rawQuery(
            "SELECT COALESCE(SUM(CASE WHEN t.type = 'income' THEN -t.amount ELSE t.amount END), 0) AS total FROM transactions t LEFT JOIN transaction_metadata m ON m.transaction_id = t.id WHERE t.account_id = ? AND t.date >= ? AND t.date < ? AND (COALESCE(m.exclude_from_spending, 0) = 0 OR m.source = 'opening_balance')",
            [
              toId,
              cycle.start.toIso8601String(),
              cycle.end.add(const Duration(days: 1)).toIso8601String()
            ]);
        final paidRows = await txn.rawQuery(
            'SELECT COALESCE(SUM(amount), 0) AS total FROM card_invoice_payments WHERE card_id = ? AND cycle_end = ?',
            [toId, key]);
        final remaining = (purchaseRows.first['total'] as num).toDouble() -
            (paidRows.first['total'] as num).toDouble();
        if (creditAmount > remaining + 0.005)
          throw StateError(
              'O valor supera a fatura em aberto. Atualize a tela.');
        await txn.insert('card_invoice_payments', {
          'id': debit.id,
          'card_id': toId,
          'cycle_end': key,
          'amount': creditAmount,
          'paid_at': now.toIso8601String()
        });
      }
      for (final tx in [debit, credit]) {
        await txn.insert('transactions', tx.toMap());
        await txn.insert(
            'transaction_metadata',
            TransactionMetadata(
                    transactionId: tx.id,
                    excludeFromSpending: true,
                    source: 'transfer:${debit.id}')
                .toMap());
      }
      await txn.rawUpdate(
          'UPDATE accounts SET balance = balance - ? WHERE id = ?',
          [fromAmount, fromId]);
      await txn.rawUpdate(
          'UPDATE accounts SET balance = balance + ? WHERE id = ?',
          [creditAmount, toId]);
    });
    await _reloadLedger();
  }

  // ── Recurring ─────────────────────────────────────────────────────────
  Future<void> addRecurring(RecurringPayment r) async {
    await DBHelper.insertRecurring(r);
    recurring = await DBHelper.getRecurring();
    notifyListeners();
    if (r.reminderEnabled) {
      await _notif.scheduleReminder(r, settings.currency);
    }
  }

  Future<void> updateRecurring(RecurringPayment r) async {
    await _notif.cancelReminder(r.id);
    await DBHelper.updateRecurring(r);
    recurring = await DBHelper.getRecurring();
    notifyListeners();
    if (r.reminderEnabled) {
      await _notif.scheduleReminder(r, settings.currency);
    }
  }

  Future<void> deleteRecurring(String id) async {
    await _notif.cancelReminder(id);
    await DBHelper.deleteRecurring(id);
    await DBHelper.deleteRecurringHistoryFor(id);
    _historyCache.remove(id);
    recurring = await DBHelper.getRecurring();
    recurringHistoryCount = await DBHelper.getRecurringHistoryCount();
    notifyListeners();
  }

  Future<void> markRecurringPaid(RecurringPayment r) =>
      _completeRecurring(r, false);

  Future<void> skipNextRecurring(RecurringPayment r) =>
      _completeRecurring(r, true);

  Future<void> _completeRecurring(RecurringPayment expected, bool skip) async {
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query('recurring_payments',
          where: 'id = ?', whereArgs: [expected.id]);
      if (rows.isEmpty) return;
      final r = RecurringPayment.fromMap(rows.first);
      // A stale screen or double tap must never complete another occurrence.
      if (r.nextDate != expected.nextDate ||
          (r.endDate != null && r.nextDate.isAfter(r.endDate!))) return;
      final occurrenceId = 'recurring:${r.id}:${r.nextDate.toIso8601String()}';
      if (!skip) {
        final tx = AppTransaction(
            id: occurrenceId,
            type: r.paymentType,
            amount: r.amount,
            description: r.name,
            accountId: r.accountId,
            categoryId: r.categoryId,
            date: r.nextDate,
            note: r.notes);
        await txn.insert('transactions', tx.toMap());
        await txn.insert(
            'transaction_metadata',
            TransactionMetadata(
              transactionId: tx.id,
              source: 'recurring',
              installmentCurrent:
                  r.recurringType == 'installment' ? r.paidPayments + 1 : null,
              installmentTotal:
                  r.recurringType == 'installment' ? r.totalPayments : null,
            ).toMap());
        await txn.rawUpdate(
            'UPDATE accounts SET balance = balance + ? WHERE id = ?',
            [_txDelta(tx), tx.accountId]);
      }
      await txn.insert(
          'recurring_history',
          RecurringHistoryEntry(
            id: occurrenceId,
            recurringId: r.id,
            action: skip ? 'skipped' : 'paid',
            date: r.nextDate,
            amount: r.amount,
            currency: accountById(r.accountId)?.currency ?? settings.currency,
          ).toMap());
      final next = r.calcNextDate();
      await txn.update(
          'recurring_payments',
          {
            'next_date': next.toIso8601String(),
            'paid_payments': r.paidPayments + 1
          },
          where: 'id = ?',
          whereArgs: [r.id]);
    });
    _historyCache.remove(expected.id);
    recurring = await DBHelper.getRecurring();
    recurringHistoryCount = await DBHelper.getRecurringHistoryCount();
    await _reloadLedger();
    if (expected.reminderEnabled) await _notif.cancelReminder(expected.id);
    final updated = recurring.where((r) => r.id == expected.id).firstOrNull;
    if (updated != null &&
        updated.reminderEnabled &&
        (updated.endDate == null ||
            !updated.nextDate.isAfter(updated.endDate!))) {
      await _notif.scheduleReminder(updated, settings.currency);
    }
  }

  /// Loads history for [recurringId] from DB, caching in memory.
  /// Returns immediately if already cached.
  Future<List<RecurringHistoryEntry>> getHistoryFor(String recurringId) async {
    if (_historyCache.containsKey(recurringId)) {
      return _historyCache[recurringId]!;
    }
    final entries = await DBHelper.getRecurringHistory(recurringId);
    _historyCache[recurringId] = entries;
    return entries;
  }

  // ── Wishlist ──────────────────────────────────────────────────────────
  Future<void> addWishlist(WishlistItem w) async {
    await DBHelper.insertWishlist(w);
    wishlist = await DBHelper.getWishlist();
    notifyListeners();
  }

  Future<void> updateWishlist(WishlistItem w) async {
    await DBHelper.updateWishlist(w);
    wishlist = await DBHelper.getWishlist();
    notifyListeners();
  }

  Future<void> deleteWishlist(String id) async {
    await DBHelper.deleteWishlist(id);
    wishlist = await DBHelper.getWishlist();
    notifyListeners();
  }

  // ── Lended People (per-person ledger "accounts") ────────────────────────
  Future<void> addLendedPerson(LendedPerson p) async {
    await DBHelper.insertLendedPerson(p);
    lendedPeople = await DBHelper.getLendedPeople();
    notifyListeners();
  }

  Future<void> updateLendedPerson(LendedPerson p) async {
    await DBHelper.updateLendedPerson(p);
    lendedPeople = await DBHelper.getLendedPeople();
    notifyListeners();
  }

  /// Deletes a person along with every lended-money entry that belongs to
  /// them, cancelling any pending reminders first.
  Future<void> deleteLendedPerson(String id) async {
    for (final l in lended.where((l) => l.personId == id)) {
      await _lendedNotif.cancelLendedReminder(l.id);
    }
    await DBHelper.deleteLendedForPerson(id);
    await DBHelper.deleteLendedPerson(id);
    lended = await DBHelper.getLended();
    lendedPeople = await DBHelper.getLendedPeople();
    notifyListeners();
  }

  /// All ledger entries belonging to [personId], most recent first.
  List<LendedMoney> lendedFor(String personId) =>
      lended.where((l) => l.personId == personId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// Net balance for a person: positive = they owe the user money,
  /// negative = the user owes them. Only unsettled entries count, mirroring
  /// how an [Account.balance] only reflects committed state.
  double personBalance(String personId) => lended
      .where((l) => l.personId == personId && !l.isSettled)
      .fold(0.0, (sum, l) => sum + (l.type == 'lent' ? l.amount : -l.amount));

  bool personHasOverdue(String personId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return lended.any((l) =>
        l.personId == personId &&
        !l.isSettled &&
        l.dueDate != null &&
        l.dueDate!.isBefore(today));
  }

  // ── Lended Money (ledger entries) ───────────────────────────────────────
  Future<void> addLended(LendedMoney l) async {
    await DBHelper.insertLended(l);
    if (l.accountId != null) {
      final delta = l.type == 'lent' ? -l.amount : l.amount;
      await _updateAccountBalance(l.accountId!, delta);
    }
    lended = await DBHelper.getLended();
    accounts = await DBHelper.getAccounts();
    notifyListeners();
    if (l.reminderEnabled && l.dueDate != null) {
      await _lendedNotif.scheduleLendedReminder(l, settings.currency,
          personName: personById(l.personId)?.name ?? '');
    }
  }

  Future<void> updateLended(LendedMoney updated, LendedMoney original) async {
    if (original.accountId != null && !original.isSettled) {
      final delta =
          original.type == 'lent' ? original.amount : -original.amount;
      await _updateAccountBalance(original.accountId!, delta);
    }
    if (updated.accountId != null && !updated.isSettled) {
      final delta = updated.type == 'lent' ? -updated.amount : updated.amount;
      await _updateAccountBalance(updated.accountId!, delta);
    }
    await DBHelper.updateLended(updated);
    lended = await DBHelper.getLended();
    accounts = await DBHelper.getAccounts();
    notifyListeners();
    // Always cancel old reminder, then reschedule if still enabled
    await _lendedNotif.cancelLendedReminder(original.id);
    if (updated.reminderEnabled &&
        updated.dueDate != null &&
        !updated.isSettled) {
      await _lendedNotif.scheduleLendedReminder(updated, settings.currency,
          personName: personById(updated.personId)?.name ?? '');
    }
  }

  Future<void> settleLended(LendedMoney l) async {
    if (l.accountId != null) {
      final delta = l.type == 'lent' ? l.amount : -l.amount;
      await _updateAccountBalance(l.accountId!, delta);
    }
    final settled = l.copyWith(isSettled: true);
    await DBHelper.updateLended(settled);
    lended = await DBHelper.getLended();
    accounts = await DBHelper.getAccounts();
    notifyListeners();
    await _lendedNotif
        .cancelLendedReminder(l.id); // no reminder needed after settlement
  }

  Future<void> deleteLended(String id) async {
    await _lendedNotif.cancelLendedReminder(id);
    await DBHelper.deleteLended(id);
    lended = await DBHelper.getLended();
    notifyListeners();
  }

  Future<VoidCallback> deleteLendedWithUndo(String id) async {
    final record = lended.firstWhere((l) => l.id == id);
    await deleteLended(id);
    return () async {
      await DBHelper.insertLended(record);
      lended = await DBHelper.getLended();
      if (!record.isSettled) {
        final p = lendedPeople.firstWhere((p) => p.id == record.personId);
        _lendedNotif.scheduleLendedReminder(record, settings.currency,
            personName: p.name);
      }
      notifyListeners();
    };
  }

  // ── Assets ────────────────────────────────────────────────────────────
  Future<void> addAsset(AssetItem a) async {
    await DBHelper.insertAsset(a);
    assets = await DBHelper.getAssets();
    notifyListeners();
  }

  Future<void> updateAsset(AssetItem a) async {
    await DBHelper.updateAsset(a);
    assets = await DBHelper.getAssets();
    notifyListeners();
  }

  Future<void> deleteAsset(String id) async {
    await DBHelper.deleteAsset(id);
    assets = await DBHelper.getAssets();
    notifyListeners();
  }

  Future<VoidCallback> deleteAssetWithUndo(String id) async {
    final asset = assets.firstWhere((a) => a.id == id);
    await deleteAsset(id);
    return () async {
      await DBHelper.insertAsset(asset);
      assets = await DBHelper.getAssets();
      notifyListeners();
    };
  }

  double get totalAssetsValue => assets.fold(0.0, (sum, a) {
        if (exchangeRates.isEmpty || a.currency == settings.currency) {
          return sum + a.value;
        }
        return sum +
            (_erService.convert(
                    a.value, a.currency, settings.currency, exchangeRates) ??
                a.value);
      });

  // ── Budgets ───────────────────────────────────────────────────────────
  Future<void> addBudget(Budget b) async {
    await DBHelper.insertBudget(b);
    budgets = await DBHelper.getBudgets();
    notifyListeners();
  }

  Future<void> updateBudget(Budget b) async {
    await DBHelper.updateBudget(b);
    budgets = await DBHelper.getBudgets();
    notifyListeners();
  }

  Future<void> deleteBudget(String id) async {
    await DBHelper.deleteBudget(id);
    budgets = await DBHelper.getBudgets();
    notifyListeners();
  }

  Future<VoidCallback> deleteBudgetWithUndo(String id) async {
    final b = budgets.firstWhere((b) => b.id == id);
    await deleteBudget(id);
    return () async {
      await addBudget(b);
    };
  }

  Budget? budgetForCategory(String categoryId) =>
      budgets.where((b) => b.categoryId == categoryId).firstOrNull;

  /// Sum of all expenses for [budget]'s category in the current period,
  /// converted to the main currency.
  double budgetSpent(Budget budget) {
    final now = DateTime.now();
    final DateTime periodStart;
    if (budget.period == 'weekly') {
      final dow = now.weekday; // 1=Mon, 7=Sun
      final offset = settings.weekStart == 'monday' ? (dow - 1) : (dow % 7);
      periodStart = DateTime(now.year, now.month, now.day - offset);
    } else {
      periodStart = DateTime(now.year, now.month, 1);
    }

    return transactions
        .where((t) =>
            t.type == 'expense' &&
            t.categoryId == budget.categoryId &&
            !FinanceRules.isNeutral(t, transactionMetadata[t.id]) &&
            t.date.isBefore(budget.period == 'weekly'
                ? periodStart.add(const Duration(days: 7))
                : DateTime(now.year, now.month + 1)) &&
            !t.date.isBefore(periodStart))
        .fold(0.0, (sum, t) {
      final acct = accountById(t.accountId);
      final txCur = t.currency.isNotEmpty
          ? t.currency
          : (acct?.currency ?? settings.currency);
      return sum + convertToMain(t.amount, txCur);
    });
  }

  double budgetProgress(Budget b) =>
      (budgetSpent(b) / b.amount).clamp(0.0, 1.0);

  double budgetRemaining(Budget b) {
    final rem = b.amount - budgetSpent(b);
    return rem < 0 ? 0 : rem;
  }

  bool budgetExceeded(Budget b) => budgetSpent(b) > b.amount;

  // ── Savings Goals ──────────────────────────────────────────────────────────

  double get totalSaved {
    double sum = 0.0;
    for (final g in savingsGoals) {
      sum += convertToMain(g.currentAmount, g.currency);
    }
    return sum;
  }

  double goalProgress(SavingsGoal g) {
    if (g.targetAmount <= 0) return 0.0;
    return (g.currentAmount / g.targetAmount).clamp(0.0, 1.0);
  }

  Future<void> addSavingsGoal(SavingsGoal g) async {
    await DBHelper.insertSavingsGoal(g);
    savingsGoals = await DBHelper.getSavingsGoals();
    notifyListeners();
  }

  Future<void> updateSavingsGoal(SavingsGoal g) async {
    await DBHelper.updateSavingsGoal(g);
    savingsGoals = await DBHelper.getSavingsGoals();
    notifyListeners();
  }

  Future<void> deleteSavingsGoal(String id) async {
    await DBHelper.deleteSavingsGoal(id);
    savingsGoals = await DBHelper.getSavingsGoals();
    notifyListeners();
  }

  Future<VoidCallback> deleteSavingsGoalWithUndo(String id) async {
    final s = savingsGoals.firstWhere((s) => s.id == id);
    await deleteSavingsGoal(id);
    return () async {
      await addSavingsGoal(s);
    };
  }

  List<SavingsContribution> contributionsFor(String goalId) {
    return savingsContributions.where((c) => c.goalId == goalId).toList();
  }

  Future<void> contributeToGoal(
          {required String goalId,
          required String fromAccountId,
          required double amount,
          String note = ''}) =>
      _moveGoal(goalId, fromAccountId, amount, note, true);

  Future<void> withdrawFromGoal(
          {required String goalId,
          required String toAccountId,
          required double amount,
          String note = ''}) =>
      _moveGoal(goalId, toAccountId, amount, note, false);

  Future<void> _moveGoal(String goalId, String accountId, double amount,
      String note, bool deposit) async {
    if (!amount.isFinite || amount <= 0)
      throw ArgumentError('Informe um valor positivo.');
    final account = accountById(accountId);
    if (account == null || account.type == 'credit' || account.isGold)
      throw StateError('Selecione uma conta válida.');
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      final rows = await txn
          .query('savings_goals', where: 'id = ?', whereArgs: [goalId]);
      if (rows.isEmpty) throw StateError('Objetivo não encontrado.');
      final goal = SavingsGoal.fromMap(rows.first);
      final goalAmount = deposit
          ? convertBetween(amount, account.currency, goal.currency) ?? amount
          : amount;
      final accountAmount = deposit
          ? amount
          : convertBetween(amount, goal.currency, account.currency) ?? amount;
      if (!deposit && goalAmount > goal.currentAmount)
        throw StateError('O valor supera o saldo guardado.');
      final newAmount =
          goal.currentAmount + (deposit ? goalAmount : -goalAmount);
      final completed = newAmount >= goal.targetAmount;
      await txn.insert(
          'savings_contributions',
          SavingsContribution(
                  id: newId(),
                  goalId: goalId,
                  accountId: accountId,
                  amount: goalAmount,
                  type: deposit ? 'contribution' : 'withdrawal',
                  date: DateTime.now(),
                  note: note)
              .toMap());
      await txn.rawUpdate(
          'UPDATE accounts SET balance = balance + ? WHERE id = ?',
          [deposit ? -accountAmount : accountAmount, accountId]);
      await txn.update(
          'savings_goals',
          goal
              .copyWith(
                  currentAmount: newAmount,
                  isCompleted: completed,
                  completedAt: completed ? DateTime.now() : null,
                  clearCompletedAt: !completed)
              .toMap(),
          where: 'id = ?',
          whereArgs: [goalId]);
    });
    savingsGoals = await DBHelper.getSavingsGoals();
    savingsContributions = await DBHelper.getAllSavingsContributions();
    accounts = await DBHelper.getAccounts();
    notifyListeners();
  }

  // ── Loans ────────────────────────────────────────────────────────────
  Future<void> addLoan(Loan l) async {
    await DBHelper.insertLoan(l);
    if (l.transferAccountId != null) {
      await _updateAccountBalance(l.transferAccountId!, l.principal);
    }
    loans = await DBHelper.getLoans();
    accounts = await DBHelper.getAccounts();
    notifyListeners();
    if (l.reminderEnabled) await _loanNotif.scheduleReminder(l);
  }

  Future<void> updateLoan(Loan l) async {
    await _loanNotif.cancelReminder(l.id);
    final oldL = loans.firstWhere((x) => x.id == l.id);

    // Reverse old principal transfer if any
    if (oldL.transferAccountId != null) {
      await _updateAccountBalance(oldL.transferAccountId!, -oldL.principal);
    }
    // Apply new principal transfer if any
    if (l.transferAccountId != null) {
      await _updateAccountBalance(l.transferAccountId!, l.principal);
    }

    await DBHelper.updateLoan(l);
    loans = await DBHelper.getLoans();
    accounts = await DBHelper.getAccounts();
    notifyListeners();
    if (l.reminderEnabled) await _loanNotif.scheduleReminder(l);
  }

  Future<void> deleteLoan(String id) async {
    await _loanNotif.cancelReminder(id);
    final l = loans.firstWhere((x) => x.id == id);

    // Reverse principal transfer if any
    if (l.transferAccountId != null) {
      await _updateAccountBalance(l.transferAccountId!, -l.principal);
    }

    for (final p in loanPaymentsFor(id)) {
      if (p.accountId != null) {
        await _updateAccountBalance(p.accountId!, p.amount); // reverse debit
      }
    }
    await DBHelper.deleteLoan(id);
    loans = await DBHelper.getLoans();
    loanPayments = await DBHelper.getAllLoanPayments();
    accounts = await DBHelper.getAccounts();
    notifyListeners();
  }

  Future<VoidCallback> deleteLoanWithUndo(String id) async {
    final l = loans.firstWhere((x) => x.id == id);
    final payments = loanPaymentsFor(id);
    await deleteLoan(id);
    return () async {
      await DBHelper.insertLoan(l);
      if (l.transferAccountId != null) {
        await _updateAccountBalance(l.transferAccountId!, l.principal);
      }
      for (final p in payments) {
        await DBHelper.insertLoanPayment(p);
        if (p.accountId != null) {
          await _updateAccountBalance(p.accountId!, -p.amount);
        }
      }
      loans = await DBHelper.getLoans();
      loanPayments = await DBHelper.getAllLoanPayments();
      accounts = await DBHelper.getAccounts();
      notifyListeners();
      if (l.reminderEnabled) await _loanNotif.scheduleReminder(l);
    };
  }

  Future<void> payLoanInstallment(Loan l,
      {double? amount, String? accountId, String notes = ''}) async {
    final payAmount = amount ?? l.monthlyPayment;
    final useAccount = accountId ?? l.accountId;

    final payment = LoanPayment(
      id: newId(),
      loanId: l.id,
      date: DateTime.now(),
      amount: payAmount,
      currency: l.currency,
      accountId: useAccount,
      notes: notes,
    );
    await DBHelper.insertLoanPayment(payment);
    if (useAccount != null) {
      await _updateAccountBalance(useAccount, -payAmount); // expense-like debit
    }
    loanPayments = await DBHelper.getAllLoanPayments();
    accounts = await DBHelper.getAccounts();

    // Auto-settle when the loan is fully paid off
    final totalPaid = loanTotalPaid(l) + payAmount;
    if (totalPaid >= l.totalPayable && !l.isSettled) {
      final settled = l.copyWith(isSettled: true);
      await DBHelper.updateLoan(settled);
      loans = await DBHelper.getLoans();
      await _loanNotif.cancelReminder(l.id);
    }
    notifyListeners();
  }

  Future<void> skipLoanInstallment(Loan l, {String notes = 'Skipped'}) async {
    final payment = LoanPayment(
      id: newId(),
      loanId: l.id,
      date: DateTime.now(),
      amount: 0.0,
      currency: l.currency,
      accountId: null,
      notes: notes,
    );
    await DBHelper.insertLoanPayment(payment);
    loanPayments = await DBHelper.getAllLoanPayments();
    notifyListeners();
  }

  Future<void> deleteLoanPayment(String id) async {
    final p = loanPayments.firstWhere((x) => x.id == id);
    if (p.accountId != null) {
      await _updateAccountBalance(p.accountId!, p.amount); // reverse the debit
    }
    await DBHelper.deleteLoanPayment(id);
    loanPayments = await DBHelper.getAllLoanPayments();
    accounts = await DBHelper.getAccounts();
    notifyListeners();
  }

  Future<VoidCallback> deleteLoanPaymentWithUndo(String id) async {
    final p = loanPayments.firstWhere((x) => x.id == id);
    await deleteLoanPayment(id);
    return () async {
      await DBHelper.insertLoanPayment(p);
      if (p.accountId != null) {
        await _updateAccountBalance(p.accountId!, -p.amount);
      }
      loanPayments = await DBHelper.getAllLoanPayments();
      accounts = await DBHelper.getAccounts();
      notifyListeners();
    };
  }

  List<LoanPayment> loanPaymentsFor(String loanId) =>
      loanPayments.where((p) => p.loanId == loanId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  double loanTotalPaid(Loan l) =>
      loanPaymentsFor(l.id).fold(0.0, (s, p) => s + p.amount);

  double loanRemaining(Loan l) =>
      (l.totalPayable - loanTotalPaid(l)).clamp(0.0, double.infinity);

  double loanProgress(Loan l) => l.totalPayable <= 0
      ? 0.0
      : (loanTotalPaid(l) / l.totalPayable).clamp(0.0, 1.0);

  double get totalMonthlyLoanObligation => loans
      .where((l) => !l.isSettled)
      .fold(0.0, (s, l) => s + convertToMain(l.monthlyPayment, l.currency));

  double get totalOutstandingLoanDebt => loans
      .where((l) => !l.isSettled)
      .fold(0.0, (s, l) => s + convertToMain(loanRemaining(l), l.currency));

  // ── Export ────────────────────────────────────────────────────────────
  Future<String?> createBackup() async {
    final data = await DBHelper.exportAll();
    data['settings'] = settings.toJson();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final uint8 = Uint8List.fromList(utf8.encode(json));
    final ts = DateTime.now().millisecondsSinceEpoch;

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Expensy Backup',
      fileName: 'expensy_backup_$ts.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: uint8,
    );
    return savePath;
  }

  Future<int> restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return 0;
    final ext = result.files.first.extension?.toLowerCase();
    if (ext != 'json') {
      throw const FormatException('Please select a .json file.');
    }

    final bytes = result.files.first.bytes;
    String jsonStr;
    if (bytes != null) {
      jsonStr = utf8.decode(bytes);
    } else {
      final path = result.files.first.path;
      if (path == null) return 0;
      jsonStr = await File(path).readAsString();
    }

    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map) {
      throw const FormatException(
          'Invalid backup file: top-level value is not a JSON object.');
    }
    final data = Map<String, dynamic>.from(decoded);

    const knownKeys = {
      'accounts',
      'categories',
      'transactions',
      'recurring_payments',
      'wishlist',
      'lended_people',
      'lended_money',
      'assets',
      'budgets',
      'recurring_history',
      'version',
      'settings',
    };
    if (!data.keys.any(knownKeys.contains)) {
      throw const FormatException(
          'Invalid backup file: no recognisable Expensy data found.');
    }

    await DBHelper.importAll(data);

    if (data['settings'] is Map) {
      settings = AppSettings.fromJson(
          Map<String, dynamic>.from(data['settings'] as Map));
      await _saveSettings();
    }

    _historyCache.clear();
    await load();
    // Re-register every recurring and lent/borrowed reminder from the
    // restored data — same call the original (pre-account-based-lending)
    // codebase made here.
    await _notif.rescheduleAll(recurring, settings.currency);
    await _lendedNotif.rescheduleAllLended(lended, settings.currency,
        personNameOf: (id) => personById(id)?.name ?? '');
    await _loanNotif.rescheduleAllLoans(loans, settings.currency);
    await CreditReminderService().rescheduleAll(accounts);

    return (data['_originalVersion'] as int?) ?? (data['version'] as int?) ?? 1;
  }

  // ── External Backups ──────────────────────────────────────────────────
  Future<bool> restoreExternalBackup(String source) async {
    final result = await FilePicker.platform.pickFiles(
      type: source == 'greenstash' ? FileType.custom : FileType.any,
      allowedExtensions: source == 'greenstash' ? ['json'] : null,
    );
    if (result == null || result.files.isEmpty) return false;

    final ext = result.files.first.extension?.toLowerCase();
    if (source == 'greenstash' && ext != 'json') {
      throw const FormatException('Please select a .json file.');
    }

    final bytes = result.files.first.bytes;
    if (bytes == null && result.files.first.path == null) return false;

    String contentStr = bytes != null
        ? utf8.decode(bytes)
        : await File(result.files.first.path!).readAsString();

    if (source == 'greenstash') {
      await _restoreGreenStash(contentStr);
    }
    return true;
  }

  Future<void> _restoreGreenStash(String jsonStr) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map || decoded['data'] is! List) {
      throw const FormatException('Invalid GreenStash format.');
    }

    for (var item in decoded['data']) {
      final goal = item['goal'];
      if (goal == null) continue;

      final sg = SavingsGoal(
        id: newId(),
        name: goal['title'] ?? 'GreenStash Goal',
        targetAmount: (goal['targetAmount'] ?? 0).toDouble(),
        currency: settings.currency,
        colorValue: 0xFF386A1F, // Greenish
        targetDate: goal['deadline'] != null && goal['deadline'] > 0
            ? DateTime.fromMillisecondsSinceEpoch(goal['deadline'])
            : null,
      );
      await addSavingsGoal(sg);

      double currentAmount = 0.0;
      if (item['transactions'] is List) {
        for (var tx in item['transactions']) {
          bool isDeposit = true;
          if (tx['type'] == 1 ||
              tx['type'] == 'withdrawal' ||
              tx['type'] == 'Withdraw' ||
              tx['isDeposit'] == false) {
            isDeposit = false;
          }
          double amt = (tx['amount'] ?? 0).toDouble().abs();

          await DBHelper.insertSavingsContribution(SavingsContribution(
            id: newId(),
            goalId: sg.id,
            amount: amt,
            accountId: '',
            type: isDeposit ? 'contribution' : 'withdrawal',
            date: DateTime.fromMillisecondsSinceEpoch(
                tx['timeStamp'] ?? DateTime.now().millisecondsSinceEpoch),
            note: tx['notes'] ?? '',
          ));
          if (isDeposit) {
            currentAmount += amt;
          } else {
            currentAmount -= amt;
          }
        }
      }
      sg.currentAmount = currentAmount;
      await DBHelper.updateSavingsGoal(sg);
    }
    await load();
  }

  bool isTransactionSelectionMode = false;
  void setTransactionSelectionMode(bool value) {
    if (isTransactionSelectionMode != value) {
      isTransactionSelectionMode = value;
      notifyListeners();
    }
  }

  final ValueNotifier<int> tabIndexNotifier = ValueNotifier<int>(0);

  List<Account> get cashAccounts =>
      accounts.where((a) => !a.isGold && a.type != 'credit').toList();

  void reorderCategories(int oldIndex, int newIndex, String type) {
    if (oldIndex < newIndex) newIndex -= 1;

    final typedCats = categories.where((c) => c.type == type).toList();
    if (oldIndex < 0 ||
        oldIndex >= typedCats.length ||
        newIndex < 0 ||
        newIndex >= typedCats.length) return;

    final item = typedCats[oldIndex];

    categories.remove(item);

    int insertionIndex = 0;
    int currentTypedIndex = 0;
    for (int i = 0; i < categories.length; i++) {
      if (categories[i].type == type) {
        if (currentTypedIndex == newIndex) {
          insertionIndex = i;
          break;
        }
        currentTypedIndex++;
      }
      insertionIndex = i + 1;
    }

    categories.insert(insertionIndex, item);
    notifyListeners();
  }

  Future<VoidCallback> deleteCategoryWithUndo(String id) async {
    final cat = categories.firstWhere((c) => c.id == id);
    final idx = categories.indexOf(cat);
    categories.removeAt(idx);
    await DBHelper.deleteCategory(id);
    notifyListeners();
    return () async {
      categories.insert(idx, cat);
      await DBHelper.insertCategory(cat);
      notifyListeners();
    };
  }

  void reorderAccounts(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = accounts.removeAt(oldIndex);
    accounts.insert(newIndex, item);
    notifyListeners();
  }

  double getBankTotalBalance(String id) {
    final acc = accountById(id);
    if (acc == null) return 0;
    return acc.balance; // Simplified. You could sum transactions if needed.
  }

  Future<VoidCallback> deleteTransactionWithUndo(String id) async {
    final metadata = await TransactionMetadataService.instance.getFor(id);
    final db = await DBHelper.database;
    final metas = metadata.source.startsWith('transfer:')
        ? (await db.query('transaction_metadata',
                where: 'source = ?', whereArgs: [metadata.source]))
            .map(TransactionMetadata.fromMap)
            .toList()
        : [metadata];
    final txs = transactions
        .where((t) => metas.any((m) => m.transactionId == t.id))
        .toList();
    final payments = await db.query('card_invoice_payments');
    await deleteTransaction(id);
    return () async {
      await db.transaction((txn) async {
        for (final tx in txs) {
          final m = metas.firstWhere((m) => m.transactionId == tx.id);
          await txn.insert('transactions', tx.toMap());
          await txn.insert('transaction_metadata', m.toMap());
          if (!m.isPending && m.affectsBalance)
            await txn.rawUpdate(
                'UPDATE accounts SET balance = balance + ? WHERE id = ?',
                [_txDelta(tx), tx.accountId]);
          for (final payment in payments.where((p) => p['id'] == tx.id)) {
            await txn.insert('card_invoice_payments', payment);
          }
        }
      });
      await _reloadLedger();
    };
  }

  Future<VoidCallback> deleteLendedPersonWithUndo(String id) async {
    final person = lendedPeople.firstWhere((p) => p.id == id);
    final personLended = lended.where((l) => l.personId == id).toList();

    await DBHelper.deleteLendedPerson(id);
    for (final l in personLended) {
      await DBHelper.deleteLended(l.id);
    }
    await load();
    return () async {
      await DBHelper.insertLendedPerson(person);
      for (final l in personLended) {
        await DBHelper.insertLended(l);
      }
      await load();
    };
  }

  Future<VoidCallback> deleteRecurringWithUndo(String id) async {
    final rec = recurring.firstWhere((r) => r.id == id);
    await DBHelper.deleteRecurring(id);
    await load();
    return () async {
      await DBHelper.insertRecurring(rec);
      await load();
    };
  }

  Future<VoidCallback> deleteWishlistWithUndo(String id) async {
    final item = wishlist.firstWhere((w) => w.id == id);
    await DBHelper.deleteWishlist(id);
    await load();
    return () async {
      await DBHelper.insertWishlist(item);
      await load();
    };
  }

  List<AppTransaction> get reportTransactions => transactions
      .where((t) =>
          !FinanceRules.isNeutral(t, transactionMetadata[t.id]) &&
          transactionMetadata[t.id]?.isPending != true)
      .toList();

  List<AppTransaction> getAccountTransactions(String id) {
    return transactions.where((t) => t.accountId == id).toList();
  }

  double getAccountIncome(String id) {
    return getAccountTransactions(id)
        .where((t) =>
            t.type == 'income' &&
            !FinanceRules.isNeutral(t, transactionMetadata[t.id]) &&
            transactionMetadata[t.id]?.isPending != true)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double getAccountExpense(String id) {
    return getAccountTransactions(id)
        .where((t) =>
            t.type == 'expense' &&
            !FinanceRules.isNeutral(t, transactionMetadata[t.id]) &&
            transactionMetadata[t.id]?.isPending != true)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  List<AppTransaction> findPossibleDuplicates(AppTransaction tx,
      {String? excludeId}) {
    return transactions
        .where((t) =>
            t.id != excludeId &&
            t.accountId == tx.accountId &&
            t.amount == tx.amount &&
            t.type == tx.type &&
            t.date.difference(tx.date).inDays.abs() <= 2)
        .toList();
  }
}
