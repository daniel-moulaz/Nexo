import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('pt')];

  /// No description provided for @appTitle.
  ///
  /// In pt, this message translates to:
  /// **'Nexo'**
  String get appTitle;

  /// No description provided for @settings_title.
  ///
  /// In pt, this message translates to:
  /// **'Configurações'**
  String get settings_title;

  /// No description provided for @settings_appearance.
  ///
  /// In pt, this message translates to:
  /// **'Aparência'**
  String get settings_appearance;

  /// No description provided for @settings_theme.
  ///
  /// In pt, this message translates to:
  /// **'Tema'**
  String get settings_theme;

  /// No description provided for @settings_system.
  ///
  /// In pt, this message translates to:
  /// **'Sistema'**
  String get settings_system;

  /// No description provided for @settings_light.
  ///
  /// In pt, this message translates to:
  /// **'Claro'**
  String get settings_light;

  /// No description provided for @settings_dark.
  ///
  /// In pt, this message translates to:
  /// **'Escuro'**
  String get settings_dark;

  /// No description provided for @settings_amoledTitle.
  ///
  /// In pt, this message translates to:
  /// **'Preto Puro (AMOLED)'**
  String get settings_amoledTitle;

  /// No description provided for @settings_amoledSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Força fundos pretos no modo escuro'**
  String get settings_amoledSubtitle;

  /// Accent Color title
  ///
  /// In pt, this message translates to:
  /// **'Cor de destaque'**
  String get settings_accentColor;

  /// No description provided for @settings_appFont.
  ///
  /// In pt, this message translates to:
  /// **'Fonte do aplicativo'**
  String get settings_appFont;

  /// System default option in settings
  ///
  /// In pt, this message translates to:
  /// **'Padrão do Sistema'**
  String get settings_systemDefault;

  /// No description provided for @settings_currency.
  ///
  /// In pt, this message translates to:
  /// **'Moeda'**
  String get settings_currency;

  /// No description provided for @settings_defaultCurrency.
  ///
  /// In pt, this message translates to:
  /// **'Moeda padrão'**
  String get settings_defaultCurrency;

  /// No description provided for @settings_preferences.
  ///
  /// In pt, this message translates to:
  /// **'Preferências'**
  String get settings_preferences;

  /// No description provided for @settings_weekStartsOn.
  ///
  /// In pt, this message translates to:
  /// **'A semana começa'**
  String get settings_weekStartsOn;

  /// No description provided for @settings_monday.
  ///
  /// In pt, this message translates to:
  /// **'Segunda-feira'**
  String get settings_monday;

  /// No description provided for @settings_sunday.
  ///
  /// In pt, this message translates to:
  /// **'Domingo'**
  String get settings_sunday;

  /// No description provided for @settings_hideBalance.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar saldo'**
  String get settings_hideBalance;

  /// No description provided for @settings_hideBalanceSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Mostrar ••••• em vez de valores'**
  String get settings_hideBalanceSubtitle;

  /// No description provided for @settings_language.
  ///
  /// In pt, this message translates to:
  /// **'Idioma'**
  String get settings_language;

  /// No description provided for @settings_profile.
  ///
  /// In pt, this message translates to:
  /// **'Perfil'**
  String get settings_profile;

  /// No description provided for @settings_displayName.
  ///
  /// In pt, this message translates to:
  /// **'Nome de exibição'**
  String get settings_displayName;

  /// No description provided for @settings_notSet.
  ///
  /// In pt, this message translates to:
  /// **'Não definido'**
  String get settings_notSet;

  /// No description provided for @settings_about.
  ///
  /// In pt, this message translates to:
  /// **'Sobre'**
  String get settings_about;

  /// No description provided for @settings_version.
  ///
  /// In pt, this message translates to:
  /// **'Versão'**
  String get settings_version;

  /// No description provided for @settings_privacy.
  ///
  /// In pt, this message translates to:
  /// **'Privacidade'**
  String get settings_privacy;

  /// No description provided for @settings_privacySubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Todos os dados armazenados localmente — 100% offline'**
  String get settings_privacySubtitle;

  /// No description provided for @settings_github.
  ///
  /// In pt, this message translates to:
  /// **'Github'**
  String get settings_github;

  /// No description provided for @settings_githubSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Ver código-fonte'**
  String get settings_githubSubtitle;

  /// No description provided for @settings_developer.
  ///
  /// In pt, this message translates to:
  /// **'Desenvolvedor'**
  String get settings_developer;

  /// No description provided for @settings_developerSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Conheça mais projetos da Mina Android'**
  String get settings_developerSubtitle;

  /// No description provided for @settings_githubProfile.
  ///
  /// In pt, this message translates to:
  /// **'Perfil GitHub'**
  String get settings_githubProfile;

  /// No description provided for @settings_developerWebsite.
  ///
  /// In pt, this message translates to:
  /// **'Site do desenvolvedor'**
  String get settings_developerWebsite;

  /// No description provided for @settings_close.
  ///
  /// In pt, this message translates to:
  /// **'Fechar'**
  String get settings_close;

  /// No description provided for @settings_yourName.
  ///
  /// In pt, this message translates to:
  /// **'Seu nome'**
  String get settings_yourName;

  /// No description provided for @settings_cancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get settings_cancel;

  /// No description provided for @settings_save.
  ///
  /// In pt, this message translates to:
  /// **'Salvar'**
  String get settings_save;

  /// No description provided for @recurring_expenses.
  ///
  /// In pt, this message translates to:
  /// **'Despesas ({count})'**
  String recurring_expenses(Object count);

  /// No description provided for @recurring_incomeList.
  ///
  /// In pt, this message translates to:
  /// **'Receitas ({count})'**
  String recurring_incomeList(Object count);

  /// No description provided for @recurring_monthly.
  ///
  /// In pt, this message translates to:
  /// **'Mensalmente'**
  String get recurring_monthly;

  /// No description provided for @recurring_weekly.
  ///
  /// In pt, this message translates to:
  /// **'Semanal'**
  String get recurring_weekly;

  /// No description provided for @recurring_noRecurringExpenses.
  ///
  /// In pt, this message translates to:
  /// **'Sem despesas recorrentes'**
  String get recurring_noRecurringExpenses;

  /// No description provided for @recurring_noRecurringIncome.
  ///
  /// In pt, this message translates to:
  /// **'Sem receitas recorrentes'**
  String get recurring_noRecurringIncome;

  /// No description provided for @recurring_addExpense.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar Despesa'**
  String get recurring_addExpense;

  /// No description provided for @recurring_addIncome.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar Renda'**
  String get recurring_addIncome;

  /// No description provided for @recurring_tapPlusToAddOne.
  ///
  /// In pt, this message translates to:
  /// **'Toque em + para adicionar um'**
  String get recurring_tapPlusToAddOne;

  /// No description provided for @recurring_fromOngoing.
  ///
  /// In pt, this message translates to:
  /// **'Desde {date} · Sem data final'**
  String recurring_fromOngoing(Object date);

  /// No description provided for @recurring_paidPayments.
  ///
  /// In pt, this message translates to:
  /// **'{paid}/{total} pagas'**
  String recurring_paidPayments(Object paid, Object total);

  /// No description provided for @recurring_totalAmount.
  ///
  /// In pt, this message translates to:
  /// **'Total: {amount}'**
  String recurring_totalAmount(Object amount);

  /// No description provided for @recurring_overdue.
  ///
  /// In pt, this message translates to:
  /// **'Atrasado!'**
  String get recurring_overdue;

  /// No description provided for @recurring_dueToday.
  ///
  /// In pt, this message translates to:
  /// **'Vencimento hoje'**
  String get recurring_dueToday;

  /// No description provided for @recurring_dueInDays.
  ///
  /// In pt, this message translates to:
  /// **'Vencimento em {days}d'**
  String recurring_dueInDays(Object days);

  /// No description provided for @recurring_edit.
  ///
  /// In pt, this message translates to:
  /// **'Editar'**
  String get recurring_edit;

  /// No description provided for @recurring_skipBtn.
  ///
  /// In pt, this message translates to:
  /// **'Pular'**
  String get recurring_skipBtn;

  /// No description provided for @recurring_nextDate.
  ///
  /// In pt, this message translates to:
  /// **'Próxima: {date}'**
  String recurring_nextDate(Object date);

  /// No description provided for @recurring_pay.
  ///
  /// In pt, this message translates to:
  /// **'Pagar'**
  String get recurring_pay;

  /// No description provided for @recurring_del.
  ///
  /// In pt, this message translates to:
  /// **'Excluir'**
  String get recurring_del;

  /// No description provided for @recurring_historyCount.
  ///
  /// In pt, this message translates to:
  /// **'Histórico ({count})'**
  String recurring_historyCount(Object count);

  /// No description provided for @recurring_paymentHistory.
  ///
  /// In pt, this message translates to:
  /// **'Histórico de pagamentos'**
  String get recurring_paymentHistory;

  /// No description provided for @recurring_notificationPermissionDenied.
  ///
  /// In pt, this message translates to:
  /// **'Permissão de notificação negada. Ative-o em Configurações → Aplicativos → Nexo → Notificações.'**
  String get recurring_notificationPermissionDenied;

  /// No description provided for @recurring_remindMeAt.
  ///
  /// In pt, this message translates to:
  /// **'Lembre-me em'**
  String get recurring_remindMeAt;

  /// No description provided for @recurring_editRecurring.
  ///
  /// In pt, this message translates to:
  /// **'Editar recorrente'**
  String get recurring_editRecurring;

  /// No description provided for @recurring_addRecurring.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar um pagamento recorrente'**
  String get recurring_addRecurring;

  /// No description provided for @recurring_name.
  ///
  /// In pt, this message translates to:
  /// **'Nome'**
  String get recurring_name;

  /// No description provided for @recurring_amountPerPayment.
  ///
  /// In pt, this message translates to:
  /// **'Montante por pagamento'**
  String get recurring_amountPerPayment;

  /// No description provided for @recurring_firstDate.
  ///
  /// In pt, this message translates to:
  /// **'Primeira: {date}'**
  String recurring_firstDate(Object date);

  /// No description provided for @recurring_lastDate.
  ///
  /// In pt, this message translates to:
  /// **'Última: {date}'**
  String recurring_lastDate(Object date);

  /// No description provided for @recurring_noLastPaymentOngoing.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum último pagamento (em andamento)'**
  String get recurring_noLastPaymentOngoing;

  /// No description provided for @accounts_refreshExchangeRates.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar taxas de câmbio'**
  String get accounts_refreshExchangeRates;

  /// No description provided for @accounts_noAccounts.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma conta'**
  String get accounts_noAccounts;

  /// No description provided for @accounts_tapPlusToAddYourFirst.
  ///
  /// In pt, this message translates to:
  /// **'Toque em + para adicionar sua primeira conta'**
  String get accounts_tapPlusToAddYourFirst;

  /// No description provided for @accounts_fetchingExchangeRates.
  ///
  /// In pt, this message translates to:
  /// **'Buscando taxas de câmbio…'**
  String get accounts_fetchingExchangeRates;

  /// No description provided for @accounts_exchangeRatesUnavailable.
  ///
  /// In pt, this message translates to:
  /// **'Taxas de câmbio indisponíveis (offline). Saldos apresentados em moeda nativa.'**
  String get accounts_exchangeRatesUnavailable;

  /// No description provided for @accounts_unknown.
  ///
  /// In pt, this message translates to:
  /// **'Desconhecido'**
  String get accounts_unknown;

  /// No description provided for @accounts_ratesUpdated.
  ///
  /// In pt, this message translates to:
  /// **'Tarifas atualizadas {timeStr} · Toque em ↺ para atualizar'**
  String accounts_ratesUpdated(Object timeStr);

  /// No description provided for @accounts_goldCaps.
  ///
  /// In pt, this message translates to:
  /// **'OURO'**
  String get accounts_goldCaps;

  /// No description provided for @accounts_balance.
  ///
  /// In pt, this message translates to:
  /// **'Saldo'**
  String get accounts_balance;

  /// No description provided for @accounts_income.
  ///
  /// In pt, this message translates to:
  /// **'Receita'**
  String get accounts_income;

  /// No description provided for @accounts_expense.
  ///
  /// In pt, this message translates to:
  /// **'Despesa'**
  String get accounts_expense;

  /// No description provided for @accounts_txs.
  ///
  /// In pt, this message translates to:
  /// **'Tx'**
  String get accounts_txs;

  /// No description provided for @accounts_value.
  ///
  /// In pt, this message translates to:
  /// **'Valor'**
  String get accounts_value;

  /// No description provided for @accounts_karat.
  ///
  /// In pt, this message translates to:
  /// **'Quilate'**
  String get accounts_karat;

  /// No description provided for @accounts_pure.
  ///
  /// In pt, this message translates to:
  /// **'{percentage}% puro'**
  String accounts_pure(Object percentage);

  /// No description provided for @accounts_weightLabel.
  ///
  /// In pt, this message translates to:
  /// **'Peso'**
  String get accounts_weightLabel;

  /// No description provided for @accounts_perGram.
  ///
  /// In pt, this message translates to:
  /// **'Por grama'**
  String get accounts_perGram;

  /// No description provided for @accounts_bank.
  ///
  /// In pt, this message translates to:
  /// **'Banco'**
  String get accounts_bank;

  /// No description provided for @accounts_cash.
  ///
  /// In pt, this message translates to:
  /// **'Dinheiro'**
  String get accounts_cash;

  /// No description provided for @accounts_savings.
  ///
  /// In pt, this message translates to:
  /// **'Poupança'**
  String get accounts_savings;

  /// No description provided for @accounts_creditCard.
  ///
  /// In pt, this message translates to:
  /// **'Cartão de Crédito'**
  String get accounts_creditCard;

  /// No description provided for @accounts_eWallet.
  ///
  /// In pt, this message translates to:
  /// **'Carteira Eletrônica'**
  String get accounts_eWallet;

  /// No description provided for @accounts_gold.
  ///
  /// In pt, this message translates to:
  /// **'Ouro'**
  String get accounts_gold;

  /// No description provided for @accounts_editAccount.
  ///
  /// In pt, this message translates to:
  /// **'Editar conta'**
  String get accounts_editAccount;

  /// No description provided for @accounts_addAccount.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar nova conta'**
  String get accounts_addAccount;

  /// No description provided for @accounts_accountName.
  ///
  /// In pt, this message translates to:
  /// **'Nome da conta'**
  String get accounts_accountName;

  /// No description provided for @accounts_weightInGrams.
  ///
  /// In pt, this message translates to:
  /// **'Peso em gramas'**
  String get accounts_weightInGrams;

  /// No description provided for @accounts_initialBalance.
  ///
  /// In pt, this message translates to:
  /// **'Saldo Inicial'**
  String get accounts_initialBalance;

  /// No description provided for @accounts_wontCountTowardYourHome.
  ///
  /// In pt, this message translates to:
  /// **'Não contará para o total da tela inicial'**
  String get accounts_wontCountTowardYourHome;

  /// No description provided for @accounts_saveChanges.
  ///
  /// In pt, this message translates to:
  /// **'Salvar alterações'**
  String get accounts_saveChanges;

  /// No description provided for @accounts_addAccountBtn.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar conta'**
  String get accounts_addAccountBtn;

  /// No description provided for @accounts_fetchingGoldPrice.
  ///
  /// In pt, this message translates to:
  /// **'Buscando o preço do ouro…'**
  String get accounts_fetchingGoldPrice;

  /// No description provided for @accounts_goldPriceUnavailable.
  ///
  /// In pt, this message translates to:
  /// **'Preço do ouro indisponível — verifique sua conexão'**
  String get accounts_goldPriceUnavailable;

  /// No description provided for @lended_person_owesYou.
  ///
  /// In pt, this message translates to:
  /// **'{name} deve a você'**
  String lended_person_owesYou(Object name);

  /// No description provided for @lended_person_youOwe.
  ///
  /// In pt, this message translates to:
  /// **'Você deve a {name}'**
  String lended_person_youOwe(Object name);

  /// No description provided for @lended_person_allSettledUp.
  ///
  /// In pt, this message translates to:
  /// **'Tudo resolvido'**
  String get lended_person_allSettledUp;

  /// No description provided for @lended_person_noRecordsYet.
  ///
  /// In pt, this message translates to:
  /// **'Ainda não há registros'**
  String get lended_person_noRecordsYet;

  /// No description provided for @lended_person_tapPlusToLog.
  ///
  /// In pt, this message translates to:
  /// **'Toque em + para registrar dinheiro emprestado ou emprestado'**
  String get lended_person_tapPlusToLog;

  /// No description provided for @lended_person_name.
  ///
  /// In pt, this message translates to:
  /// **'Nome'**
  String get lended_person_name;

  /// No description provided for @lended_person_notesOptional.
  ///
  /// In pt, this message translates to:
  /// **'Notas (opcional)'**
  String get lended_person_notesOptional;

  /// No description provided for @lended_person_lent.
  ///
  /// In pt, this message translates to:
  /// **'Quaresma'**
  String get lended_person_lent;

  /// No description provided for @lended_person_borrowed.
  ///
  /// In pt, this message translates to:
  /// **'Emprestado'**
  String get lended_person_borrowed;

  /// No description provided for @lended_person_overdue.
  ///
  /// In pt, this message translates to:
  /// **'Atrasado!'**
  String get lended_person_overdue;

  /// No description provided for @lended_person_due.
  ///
  /// In pt, this message translates to:
  /// **'Vence em {date}'**
  String lended_person_due(Object date);

  /// No description provided for @lended_person_reminderAt.
  ///
  /// In pt, this message translates to:
  /// **'Lembrete às {time}'**
  String lended_person_reminderAt(Object time);

  /// No description provided for @lended_person_notificationPermissionDenied.
  ///
  /// In pt, this message translates to:
  /// **'Permissão de notificação negada. Ative-o em Configurações → Aplicativos → Nexo → Notificações.'**
  String get lended_person_notificationPermissionDenied;

  /// No description provided for @lended_person_remindMeAtPrompt.
  ///
  /// In pt, this message translates to:
  /// **'Lembre-me em'**
  String get lended_person_remindMeAtPrompt;

  /// No description provided for @lended_person_editRecord.
  ///
  /// In pt, this message translates to:
  /// **'Editar registro'**
  String get lended_person_editRecord;

  /// No description provided for @lended_person_addRecord.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar registro'**
  String get lended_person_addRecord;

  /// No description provided for @lended_person_amount.
  ///
  /// In pt, this message translates to:
  /// **'Quantia'**
  String get lended_person_amount;

  /// No description provided for @lended_person_dueColon.
  ///
  /// In pt, this message translates to:
  /// **'Vencimento: {date}'**
  String lended_person_dueColon(Object date);

  /// No description provided for @lended_person_noDueDate.
  ///
  /// In pt, this message translates to:
  /// **'Sem data de vencimento'**
  String get lended_person_noDueDate;

  /// No description provided for @lended_person_setDueFirst.
  ///
  /// In pt, this message translates to:
  /// **'Defina uma data de vencimento primeiro'**
  String get lended_person_setDueFirst;

  /// No description provided for @lended_person_notifiedOnDue.
  ///
  /// In pt, this message translates to:
  /// **'Você será notificado na data de vencimento'**
  String get lended_person_notifiedOnDue;

  /// No description provided for @lended_person_getNotifiedWhenDue.
  ///
  /// In pt, this message translates to:
  /// **'Seja notificado quando isso acontecer'**
  String get lended_person_getNotifiedWhenDue;

  /// No description provided for @lended_person_thatTimePassed.
  ///
  /// In pt, this message translates to:
  /// **'Esse horário de hoje já passou. Em vez disso, você será notificado em breve.'**
  String get lended_person_thatTimePassed;

  /// No description provided for @lended_person_notificationFiresOn.
  ///
  /// In pt, this message translates to:
  /// **'A notificação é disparada em {date} às {time}.'**
  String lended_person_notificationFiresOn(Object date, Object time);

  /// No description provided for @lended_person_saveChangesBtn.
  ///
  /// In pt, this message translates to:
  /// **'Salvar alterações'**
  String get lended_person_saveChangesBtn;

  /// No description provided for @lended_person_addRecordBtn.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar registro'**
  String get lended_person_addRecordBtn;

  /// No description provided for @transactions_searchTransactions.
  ///
  /// In pt, this message translates to:
  /// **'Pesquisar transações...'**
  String get transactions_searchTransactions;

  /// No description provided for @transactions_all.
  ///
  /// In pt, this message translates to:
  /// **'Todos'**
  String get transactions_all;

  /// No description provided for @transactions_income.
  ///
  /// In pt, this message translates to:
  /// **'Renda'**
  String get transactions_income;

  /// No description provided for @transactions_expenses.
  ///
  /// In pt, this message translates to:
  /// **'Despesas'**
  String get transactions_expenses;

  /// No description provided for @transactions_lent.
  ///
  /// In pt, this message translates to:
  /// **'Quaresma'**
  String get transactions_lent;

  /// No description provided for @transactions_borrowed.
  ///
  /// In pt, this message translates to:
  /// **'Emprestado'**
  String get transactions_borrowed;

  /// No description provided for @transactions_noTransactions.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma transação'**
  String get transactions_noTransactions;

  /// No description provided for @transactions_tapPlusToAddOne.
  ///
  /// In pt, this message translates to:
  /// **'Toque em + para adicionar um'**
  String get transactions_tapPlusToAddOne;

  /// No description provided for @transactions_today.
  ///
  /// In pt, this message translates to:
  /// **'Hoje'**
  String get transactions_today;

  /// No description provided for @transactions_yesterday.
  ///
  /// In pt, this message translates to:
  /// **'Ontem'**
  String get transactions_yesterday;

  /// No description provided for @transactions_lentTo.
  ///
  /// In pt, this message translates to:
  /// **'Emprestado para {name}'**
  String transactions_lentTo(Object name);

  /// No description provided for @transactions_borrowedFrom.
  ///
  /// In pt, this message translates to:
  /// **'Emprestado de {name}'**
  String transactions_borrowedFrom(Object name);

  /// No description provided for @transactions_unknown.
  ///
  /// In pt, this message translates to:
  /// **'Desconhecido'**
  String get transactions_unknown;

  /// No description provided for @transactions_due.
  ///
  /// In pt, this message translates to:
  /// **'Vence em {date}'**
  String transactions_due(Object date);

  /// No description provided for @transactions_unsettled.
  ///
  /// In pt, this message translates to:
  /// **'Inquieto'**
  String get transactions_unsettled;

  /// No description provided for @onboarding_restoreFailed.
  ///
  /// In pt, this message translates to:
  /// **'Falha na restauração: o arquivo pode estar corrompido ou não ser um backup Nexo.'**
  String get onboarding_restoreFailed;

  /// No description provided for @onboarding_continue.
  ///
  /// In pt, this message translates to:
  /// **'Continuar'**
  String get onboarding_continue;

  /// No description provided for @onboarding_getStarted.
  ///
  /// In pt, this message translates to:
  /// **'Comece'**
  String get onboarding_getStarted;

  /// No description provided for @onboarding_yourPersonalTracker.
  ///
  /// In pt, this message translates to:
  /// **'Seu rastreador financeiro pessoal 100% offline.\nJá possui um backup de outro dispositivo ou uma instalação anterior?'**
  String get onboarding_yourPersonalTracker;

  /// No description provided for @onboarding_restoring.
  ///
  /// In pt, this message translates to:
  /// **'Restaurando...'**
  String get onboarding_restoring;

  /// No description provided for @onboarding_chooseBackupFile.
  ///
  /// In pt, this message translates to:
  /// **'Escolha o arquivo de backup'**
  String get onboarding_chooseBackupFile;

  /// No description provided for @onboarding_letsGetYouSetUp.
  ///
  /// In pt, this message translates to:
  /// **'Vamos preparar você'**
  String get onboarding_letsGetYouSetUp;

  /// No description provided for @onboarding_yourName.
  ///
  /// In pt, this message translates to:
  /// **'Seu nome'**
  String get onboarding_yourName;

  /// No description provided for @onboarding_accountName.
  ///
  /// In pt, this message translates to:
  /// **'Nome da conta'**
  String get onboarding_accountName;

  /// No description provided for @onboarding_bank.
  ///
  /// In pt, this message translates to:
  /// **'Banco'**
  String get onboarding_bank;

  /// No description provided for @onboarding_cash.
  ///
  /// In pt, this message translates to:
  /// **'Dinheiro'**
  String get onboarding_cash;

  /// No description provided for @onboarding_savings.
  ///
  /// In pt, this message translates to:
  /// **'Poupança'**
  String get onboarding_savings;

  /// No description provided for @onboarding_credit.
  ///
  /// In pt, this message translates to:
  /// **'Crédito'**
  String get onboarding_credit;

  /// No description provided for @onboarding_wallet.
  ///
  /// In pt, this message translates to:
  /// **'Carteira'**
  String get onboarding_wallet;

  /// No description provided for @onboarding_startingBalance.
  ///
  /// In pt, this message translates to:
  /// **'Saldo Inicial'**
  String get onboarding_startingBalance;

  /// No description provided for @backup_replaceDataWarning.
  ///
  /// In pt, this message translates to:
  /// **'Isso substituirá TODOS os seus dados atuais pelo backup.\nIsto não pode ser desfeito.'**
  String get backup_replaceDataWarning;

  /// No description provided for @backup_whatsIncluded.
  ///
  /// In pt, this message translates to:
  /// **'O que está incluído'**
  String get backup_whatsIncluded;

  /// No description provided for @backup_backupDescription.
  ///
  /// In pt, this message translates to:
  /// **'Cada backup inclui todos os seus dados – contas, transações, pagamentos recorrentes e seu histórico de pagamento/pular, orçamentos, itens da lista de desejos, pessoas e registros emprestados e emprestados, ativos, categorias e configurações de aplicativos.'**
  String get backup_backupDescription;

  /// No description provided for @backup_saving.
  ///
  /// In pt, this message translates to:
  /// **'Salvando...'**
  String get backup_saving;

  /// No description provided for @backup_saveBackup.
  ///
  /// In pt, this message translates to:
  /// **'Salvar backup'**
  String get backup_saveBackup;

  /// No description provided for @backup_restoring.
  ///
  /// In pt, this message translates to:
  /// **'Restaurando...'**
  String get backup_restoring;

  /// No description provided for @backup_restoreBackupBtn.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar Backup'**
  String get backup_restoreBackupBtn;

  /// No description provided for @backup_restoreWarningText.
  ///
  /// In pt, this message translates to:
  /// **'Compatível com backups de qualquer versão do aplicativo. Os campos ausentes são preenchidos com padrões seguros.'**
  String get backup_restoreWarningText;

  /// No description provided for @backup_included.
  ///
  /// In pt, this message translates to:
  /// **'incluído'**
  String get backup_included;

  /// No description provided for @backup_accounts.
  ///
  /// In pt, this message translates to:
  /// **'Contas'**
  String get backup_accounts;

  /// No description provided for @backup_transactions.
  ///
  /// In pt, this message translates to:
  /// **'Transações'**
  String get backup_transactions;

  /// No description provided for @backup_recurringPayments.
  ///
  /// In pt, this message translates to:
  /// **'Pagamentos recorrentes'**
  String get backup_recurringPayments;

  /// No description provided for @backup_recurringHistory.
  ///
  /// In pt, this message translates to:
  /// **'Histórico recorrente'**
  String get backup_recurringHistory;

  /// No description provided for @backup_budgets.
  ///
  /// In pt, this message translates to:
  /// **'Orçamentos'**
  String get backup_budgets;

  /// No description provided for @backup_wishlist.
  ///
  /// In pt, this message translates to:
  /// **'Lista de desejos'**
  String get backup_wishlist;

  /// No description provided for @backup_lentPeople.
  ///
  /// In pt, this message translates to:
  /// **'Quaresma/Empréstimo — Pessoas'**
  String get backup_lentPeople;

  /// No description provided for @backup_lentRecords.
  ///
  /// In pt, this message translates to:
  /// **'Emprestado/Empréstimo — Registros'**
  String get backup_lentRecords;

  /// No description provided for @backup_assets.
  ///
  /// In pt, this message translates to:
  /// **'Ativos'**
  String get backup_assets;

  /// No description provided for @backup_categories.
  ///
  /// In pt, this message translates to:
  /// **'Categorias'**
  String get backup_categories;

  /// No description provided for @backup_settings.
  ///
  /// In pt, this message translates to:
  /// **'Configurações'**
  String get backup_settings;

  /// No description provided for @backup_backupSavedSuccessfully.
  ///
  /// In pt, this message translates to:
  /// **'Backup salvo com sucesso:\n{savedPath}'**
  String backup_backupSavedSuccessfully(Object savedPath);

  /// No description provided for @backup_backupFailed.
  ///
  /// In pt, this message translates to:
  /// **'Falha no backup: {error}'**
  String backup_backupFailed(Object error);

  /// No description provided for @backup_upgradedFrom.
  ///
  /// In pt, this message translates to:
  /// **'(atualizado de v{originalVersion} → v{schemaVersion})'**
  String backup_upgradedFrom(Object originalVersion, Object schemaVersion);

  /// No description provided for @backup_dataRestoredSuccessfully.
  ///
  /// In pt, this message translates to:
  /// **'Dados restaurados com sucesso!{vLabel}'**
  String backup_dataRestoredSuccessfully(Object vLabel);

  /// No description provided for @backup_restoreFailed.
  ///
  /// In pt, this message translates to:
  /// **'Falha na restauração: {error}'**
  String backup_restoreFailed(Object error);

  /// No description provided for @backup_restoreFailedCorrupted.
  ///
  /// In pt, this message translates to:
  /// **'Falha na restauração: o arquivo pode estar corrompido ou não ser um backup Nexo.'**
  String get backup_restoreFailedCorrupted;

  /// No description provided for @budget_noBudgetsYet.
  ///
  /// In pt, this message translates to:
  /// **'Ainda sem orçamentos'**
  String get budget_noBudgetsYet;

  /// No description provided for @budget_tapToAddBudget.
  ///
  /// In pt, this message translates to:
  /// **'Toque em + para definir um limite de gastos por categoria'**
  String get budget_tapToAddBudget;

  /// No description provided for @budget_budgeted.
  ///
  /// In pt, this message translates to:
  /// **'Orçamentado'**
  String get budget_budgeted;

  /// No description provided for @budget_spent.
  ///
  /// In pt, this message translates to:
  /// **'Gasto'**
  String get budget_spent;

  /// No description provided for @budget_overLimit.
  ///
  /// In pt, this message translates to:
  /// **'Acima do limite'**
  String get budget_overLimit;

  /// No description provided for @budget_unknown.
  ///
  /// In pt, this message translates to:
  /// **'Desconhecido'**
  String get budget_unknown;

  /// No description provided for @budget_weeklyLabel.
  ///
  /// In pt, this message translates to:
  /// **'Semanal'**
  String get budget_weeklyLabel;

  /// No description provided for @budget_monthlyLabel.
  ///
  /// In pt, this message translates to:
  /// **'Mensal'**
  String get budget_monthlyLabel;

  /// No description provided for @budget_overAmount.
  ///
  /// In pt, this message translates to:
  /// **'{amount} acima'**
  String budget_overAmount(Object amount);

  /// No description provided for @budget_leftAmount.
  ///
  /// In pt, this message translates to:
  /// **'{amount} restantes'**
  String budget_leftAmount(Object amount);

  /// No description provided for @budget_percentUsed.
  ///
  /// In pt, this message translates to:
  /// **'{percent}% usado'**
  String budget_percentUsed(Object percent);

  /// No description provided for @budget_editBudget.
  ///
  /// In pt, this message translates to:
  /// **'Editar orçamento'**
  String get budget_editBudget;

  /// No description provided for @budget_setBudget.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar novo orçamento'**
  String get budget_setBudget;

  /// No description provided for @budget_budgetAmount.
  ///
  /// In pt, this message translates to:
  /// **'Montante do orçamento'**
  String get budget_budgetAmount;

  /// No description provided for @budget_previewFor.
  ///
  /// In pt, this message translates to:
  /// **'Visualização de \\\"{catName}\\\"'**
  String budget_previewFor(Object catName);

  /// No description provided for @budget_spentAmount.
  ///
  /// In pt, this message translates to:
  /// **'Gasto: {amount}'**
  String budget_spentAmount(Object amount);

  /// No description provided for @budget_ofAmount.
  ///
  /// In pt, this message translates to:
  /// **'de {amount}'**
  String budget_ofAmount(Object amount);

  /// No description provided for @budget_saveChanges.
  ///
  /// In pt, this message translates to:
  /// **'Salvar alterações'**
  String get budget_saveChanges;

  /// No description provided for @budget_budget.
  ///
  /// In pt, this message translates to:
  /// **'Orçamento'**
  String get budget_budget;

  /// No description provided for @insights_other.
  ///
  /// In pt, this message translates to:
  /// **'Outros'**
  String get insights_other;

  /// No description provided for @insights_noDataYet.
  ///
  /// In pt, this message translates to:
  /// **'Ainda não há dados'**
  String get insights_noDataYet;

  /// No description provided for @insights_addSomeTransactions.
  ///
  /// In pt, this message translates to:
  /// **'Adicione algumas transações para ver insights'**
  String get insights_addSomeTransactions;

  /// No description provided for @insights_thisMonthVsLastMonth.
  ///
  /// In pt, this message translates to:
  /// **'Este mês vs mês passado'**
  String get insights_thisMonthVsLastMonth;

  /// No description provided for @insights_dailyAverage.
  ///
  /// In pt, this message translates to:
  /// **'Média Diária'**
  String get insights_dailyAverage;

  /// No description provided for @insights_perDayBasedOn.
  ///
  /// In pt, this message translates to:
  /// **'por dia · com base em {days} dias deste mês'**
  String insights_perDayBasedOn(Object days);

  /// No description provided for @insights_incomeVsExpenses.
  ///
  /// In pt, this message translates to:
  /// **'Receitas vs Despesas'**
  String get insights_incomeVsExpenses;

  /// No description provided for @insights_incomeAmount.
  ///
  /// In pt, this message translates to:
  /// **'Receitas {amount}'**
  String insights_incomeAmount(Object amount);

  /// No description provided for @insights_expensesAmount.
  ///
  /// In pt, this message translates to:
  /// **'Despesas {amount}'**
  String insights_expensesAmount(Object amount);

  /// No description provided for @insights_percentSaved.
  ///
  /// In pt, this message translates to:
  /// **'{percent}% economizados este mês'**
  String insights_percentSaved(Object percent);

  /// No description provided for @insights_topSpendingCategories.
  ///
  /// In pt, this message translates to:
  /// **'Principais categorias de gastos'**
  String get insights_topSpendingCategories;

  /// No description provided for @insights_percentOfTotal.
  ///
  /// In pt, this message translates to:
  /// **'{percent}% do total'**
  String insights_percentOfTotal(Object percent);

  /// No description provided for @insights_biggestExpenseThisMonth.
  ///
  /// In pt, this message translates to:
  /// **'Maior despesa deste mês'**
  String get insights_biggestExpenseThisMonth;

  /// No description provided for @insights_categoryTrends.
  ///
  /// In pt, this message translates to:
  /// **'Tendências da categoria (vs mês passado)'**
  String get insights_categoryTrends;

  /// No description provided for @insights_12MonthTrend.
  ///
  /// In pt, this message translates to:
  /// **'Tendência de 12 meses'**
  String get insights_12MonthTrend;

  /// No description provided for @insights_incomeLabel.
  ///
  /// In pt, this message translates to:
  /// **'Renda'**
  String get insights_incomeLabel;

  /// No description provided for @insights_expensesLabel.
  ///
  /// In pt, this message translates to:
  /// **'Despesas'**
  String get insights_expensesLabel;

  /// No description provided for @categories_expenseLabel.
  ///
  /// In pt, this message translates to:
  /// **'Despesa'**
  String get categories_expenseLabel;

  /// No description provided for @categories_incomeLabel.
  ///
  /// In pt, this message translates to:
  /// **'Renda'**
  String get categories_incomeLabel;

  /// No description provided for @categories_editCategory.
  ///
  /// In pt, this message translates to:
  /// **'Editar categoria'**
  String get categories_editCategory;

  /// No description provided for @categories_addCategory.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar categoria'**
  String get categories_addCategory;

  /// No description provided for @categories_categoryName.
  ///
  /// In pt, this message translates to:
  /// **'Nome da categoria'**
  String get categories_categoryName;

  /// No description provided for @categories_saveChanges.
  ///
  /// In pt, this message translates to:
  /// **'Salvar alterações'**
  String get categories_saveChanges;

  /// No description provided for @statistics_other.
  ///
  /// In pt, this message translates to:
  /// **'Outros'**
  String get statistics_other;

  /// No description provided for @statistics_allAccounts.
  ///
  /// In pt, this message translates to:
  /// **'Todas as contas'**
  String get statistics_allAccounts;

  /// No description provided for @statistics_income.
  ///
  /// In pt, this message translates to:
  /// **'Renda'**
  String get statistics_income;

  /// No description provided for @statistics_expenses.
  ///
  /// In pt, this message translates to:
  /// **'Despesas'**
  String get statistics_expenses;

  /// No description provided for @statistics_expense.
  ///
  /// In pt, this message translates to:
  /// **'Despesa'**
  String get statistics_expense;

  /// No description provided for @statistics_net.
  ///
  /// In pt, this message translates to:
  /// **'Líquido'**
  String get statistics_net;

  /// No description provided for @statistics_6MonthOverviewAccount.
  ///
  /// In pt, this message translates to:
  /// **'Visão geral de 6 meses · {accountName}'**
  String statistics_6MonthOverviewAccount(Object accountName);

  /// No description provided for @statistics_6MonthOverview.
  ///
  /// In pt, this message translates to:
  /// **'Visão geral de 6 meses'**
  String get statistics_6MonthOverview;

  /// No description provided for @statistics_percentOfBudget.
  ///
  /// In pt, this message translates to:
  /// **'{percent}% do orçamento'**
  String statistics_percentOfBudget(Object percent);

  /// No description provided for @add_transaction_editTransaction.
  ///
  /// In pt, this message translates to:
  /// **'Editar transação'**
  String get add_transaction_editTransaction;

  /// No description provided for @add_transaction_addTransaction.
  ///
  /// In pt, this message translates to:
  /// **'Insira a transação'**
  String get add_transaction_addTransaction;

  /// No description provided for @add_transaction_amount.
  ///
  /// In pt, this message translates to:
  /// **'Montante'**
  String get add_transaction_amount;

  /// No description provided for @add_transaction_conversionPreview.
  ///
  /// In pt, this message translates to:
  /// **'≈ {amount} será deduzido de {accountName}'**
  String add_transaction_conversionPreview(Object accountName, Object amount);

  /// No description provided for @add_transaction_accountFallback.
  ///
  /// In pt, this message translates to:
  /// **'conta'**
  String get add_transaction_accountFallback;

  /// No description provided for @add_transaction_descriptionOptional.
  ///
  /// In pt, this message translates to:
  /// **'Descrição (opcional)'**
  String get add_transaction_descriptionOptional;

  /// No description provided for @add_transaction_noteOptional.
  ///
  /// In pt, this message translates to:
  /// **'Nota (opcional)'**
  String get add_transaction_noteOptional;

  /// No description provided for @add_transaction_saveChanges.
  ///
  /// In pt, this message translates to:
  /// **'Salvar alterações'**
  String get add_transaction_saveChanges;

  /// No description provided for @more_statistics.
  ///
  /// In pt, this message translates to:
  /// **'Estatísticas'**
  String get more_statistics;

  /// No description provided for @more_statisticsSub.
  ///
  /// In pt, this message translates to:
  /// **'Gráficos e resumo mensal'**
  String get more_statisticsSub;

  /// No description provided for @more_insights.
  ///
  /// In pt, this message translates to:
  /// **'Informações'**
  String get more_insights;

  /// No description provided for @more_insightsSub.
  ///
  /// In pt, this message translates to:
  /// **'Tendências, médias e análise de categorias'**
  String get more_insightsSub;

  /// No description provided for @more_currencyConverter.
  ///
  /// In pt, this message translates to:
  /// **'Conversor de moeda'**
  String get more_currencyConverter;

  /// No description provided for @more_currencyConverterSub.
  ///
  /// In pt, this message translates to:
  /// **'Converta entre moedas instantaneamente'**
  String get more_currencyConverterSub;

  /// No description provided for @more_wishlist.
  ///
  /// In pt, this message translates to:
  /// **'Lista de desejos'**
  String get more_wishlist;

  /// No description provided for @more_wishlistSub.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} itens}}'**
  String more_wishlistSub(num count);

  /// No description provided for @more_lentMoney.
  ///
  /// In pt, this message translates to:
  /// **'Dinheiro Emprestado'**
  String get more_lentMoney;

  /// No description provided for @more_lentMoneySub.
  ///
  /// In pt, this message translates to:
  /// **'{count} em aberto'**
  String more_lentMoneySub(Object count);

  /// No description provided for @more_assets.
  ///
  /// In pt, this message translates to:
  /// **'Ativos'**
  String get more_assets;

  /// No description provided for @more_assetsSub.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} itens}}'**
  String more_assetsSub(num count);

  /// No description provided for @more_categories.
  ///
  /// In pt, this message translates to:
  /// **'Categorias'**
  String get more_categories;

  /// No description provided for @more_categoriesSub.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 categoria} other{{count} categorias}}'**
  String more_categoriesSub(num count);

  /// No description provided for @more_exportTransactions.
  ///
  /// In pt, this message translates to:
  /// **'Transações de exportação'**
  String get more_exportTransactions;

  /// No description provided for @more_exportTransactionsSub.
  ///
  /// In pt, this message translates to:
  /// **'Salvar como Excel (.xlsx)'**
  String get more_exportTransactionsSub;

  /// No description provided for @more_backupRestore.
  ///
  /// In pt, this message translates to:
  /// **'Backup e restauração'**
  String get more_backupRestore;

  /// No description provided for @more_backupRestoreSub.
  ///
  /// In pt, this message translates to:
  /// **'Salve ou carregue seus dados'**
  String get more_backupRestoreSub;

  /// No description provided for @more_settings.
  ///
  /// In pt, this message translates to:
  /// **'Configurações'**
  String get more_settings;

  /// No description provided for @more_settingsSub.
  ///
  /// In pt, this message translates to:
  /// **'Tema, moeda e preferências'**
  String get more_settingsSub;

  /// No description provided for @home_greeting.
  ///
  /// In pt, this message translates to:
  /// **'Olá, {name} 👋'**
  String home_greeting(Object name);

  /// No description provided for @home_there.
  ///
  /// In pt, this message translates to:
  /// **'aí'**
  String get home_there;

  /// No description provided for @home_income.
  ///
  /// In pt, this message translates to:
  /// **'Renda'**
  String get home_income;

  /// No description provided for @home_expenses.
  ///
  /// In pt, this message translates to:
  /// **'Despesas'**
  String get home_expenses;

  /// No description provided for @home_net.
  ///
  /// In pt, this message translates to:
  /// **'Líquido'**
  String get home_net;

  /// No description provided for @wishlist_noItems.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum item da lista de desejos'**
  String get wishlist_noItems;

  /// No description provided for @wishlist_noItemsSub.
  ///
  /// In pt, this message translates to:
  /// **'Toque em + para adicionar itens para os quais você está salvando'**
  String get wishlist_noItemsSub;

  /// No description provided for @wishlist_editItem.
  ///
  /// In pt, this message translates to:
  /// **'Editar item'**
  String get wishlist_editItem;

  /// No description provided for @wishlist_addWishlistItem.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar item à lista de desejos'**
  String get wishlist_addWishlistItem;

  /// No description provided for @wishlist_itemName.
  ///
  /// In pt, this message translates to:
  /// **'Nome do item'**
  String get wishlist_itemName;

  /// No description provided for @wishlist_targetPrice.
  ///
  /// In pt, this message translates to:
  /// **'Preço Alvo'**
  String get wishlist_targetPrice;

  /// No description provided for @wishlist_priorityLow.
  ///
  /// In pt, this message translates to:
  /// **'Baixo'**
  String get wishlist_priorityLow;

  /// No description provided for @wishlist_priorityMedium.
  ///
  /// In pt, this message translates to:
  /// **'Médio'**
  String get wishlist_priorityMedium;

  /// No description provided for @wishlist_priorityHigh.
  ///
  /// In pt, this message translates to:
  /// **'Alto'**
  String get wishlist_priorityHigh;

  /// No description provided for @wishlist_notesOptional.
  ///
  /// In pt, this message translates to:
  /// **'Notas (opcional)'**
  String get wishlist_notesOptional;

  /// No description provided for @wishlist_saveChanges.
  ///
  /// In pt, this message translates to:
  /// **'Salvar alterações'**
  String get wishlist_saveChanges;

  /// No description provided for @wishlist_addItem.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar item'**
  String get wishlist_addItem;

  /// No description provided for @lended_theyOweMe.
  ///
  /// In pt, this message translates to:
  /// **'Eles me devem'**
  String get lended_theyOweMe;

  /// No description provided for @lended_iOweThem.
  ///
  /// In pt, this message translates to:
  /// **'Eu devo a eles'**
  String get lended_iOweThem;

  /// No description provided for @lended_net.
  ///
  /// In pt, this message translates to:
  /// **'Líquido'**
  String get lended_net;

  /// No description provided for @lended_noOneYet.
  ///
  /// In pt, this message translates to:
  /// **'Ninguém ainda'**
  String get lended_noOneYet;

  /// No description provided for @lended_noOneYetSub.
  ///
  /// In pt, this message translates to:
  /// **'Toque em + para adicionar uma pessoa a quem você empresta ou pede emprestado'**
  String get lended_noOneYetSub;

  /// No description provided for @lended_owesYou.
  ///
  /// In pt, this message translates to:
  /// **'Devo a você'**
  String get lended_owesYou;

  /// No description provided for @lended_youOwe.
  ///
  /// In pt, this message translates to:
  /// **'Você deve'**
  String get lended_youOwe;

  /// No description provided for @lended_settledUp.
  ///
  /// In pt, this message translates to:
  /// **'Resolvido'**
  String get lended_settledUp;

  /// No description provided for @lended_noActiveRecords.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum registro ativo'**
  String get lended_noActiveRecords;

  /// No description provided for @lended_activeRecords.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 registro ativo} other{{count} registros ativos}}'**
  String lended_activeRecords(num count);

  /// No description provided for @lended_editPerson.
  ///
  /// In pt, this message translates to:
  /// **'Editar Pessoa'**
  String get lended_editPerson;

  /// No description provided for @lended_addPerson.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar Pessoa'**
  String get lended_addPerson;

  /// No description provided for @lended_name.
  ///
  /// In pt, this message translates to:
  /// **'Nome'**
  String get lended_name;

  /// No description provided for @lended_notesOptional.
  ///
  /// In pt, this message translates to:
  /// **'Notas (opcional)'**
  String get lended_notesOptional;

  /// No description provided for @lended_saveChanges.
  ///
  /// In pt, this message translates to:
  /// **'Salvar alterações'**
  String get lended_saveChanges;

  /// No description provided for @assets_totalAssets.
  ///
  /// In pt, this message translates to:
  /// **'Ativo total'**
  String get assets_totalAssets;

  /// No description provided for @assets_items.
  ///
  /// In pt, this message translates to:
  /// **'Itens'**
  String get assets_items;

  /// No description provided for @assets_noAssetsYet.
  ///
  /// In pt, this message translates to:
  /// **'Ainda não há ativos'**
  String get assets_noAssetsYet;

  /// No description provided for @assets_noAssetsYetSub.
  ///
  /// In pt, this message translates to:
  /// **'Toque em + para adicionar um produto ou ativo'**
  String get assets_noAssetsYetSub;

  /// No description provided for @assets_editAsset.
  ///
  /// In pt, this message translates to:
  /// **'Editar recurso'**
  String get assets_editAsset;

  /// No description provided for @assets_addAsset.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar ativo'**
  String get assets_addAsset;

  /// No description provided for @assets_productAssetName.
  ///
  /// In pt, this message translates to:
  /// **'Nome do produto/ativo'**
  String get assets_productAssetName;

  /// No description provided for @assets_value.
  ///
  /// In pt, this message translates to:
  /// **'Valor'**
  String get assets_value;

  /// No description provided for @assets_notesOptional.
  ///
  /// In pt, this message translates to:
  /// **'Notas (opcional)'**
  String get assets_notesOptional;

  /// No description provided for @assets_saveChanges.
  ///
  /// In pt, this message translates to:
  /// **'Salvar alterações'**
  String get assets_saveChanges;

  /// No description provided for @currency_converter_loadingRates.
  ///
  /// In pt, this message translates to:
  /// **'Carregando taxas de câmbio…'**
  String get currency_converter_loadingRates;

  /// No description provided for @currency_converter_ratesUnavailable.
  ///
  /// In pt, this message translates to:
  /// **'Taxas de câmbio indisponíveis. Conecte-se à Internet e sincronize.'**
  String get currency_converter_ratesUnavailable;

  /// No description provided for @currency_converter_rateAgeJustNow.
  ///
  /// In pt, this message translates to:
  /// **'Agora mesmo'**
  String get currency_converter_rateAgeJustNow;

  /// No description provided for @currency_converter_rateAgeMins.
  ///
  /// In pt, this message translates to:
  /// **'há {minutes} min'**
  String currency_converter_rateAgeMins(Object minutes);

  /// No description provided for @currency_converter_rateAgeHours.
  ///
  /// In pt, this message translates to:
  /// **'{hours}h atrás'**
  String currency_converter_rateAgeHours(Object hours);

  /// No description provided for @currency_converter_rateAgeDays.
  ///
  /// In pt, this message translates to:
  /// **'há {days} dias'**
  String currency_converter_rateAgeDays(Object days);

  /// No description provided for @currency_converter_commonConversions.
  ///
  /// In pt, this message translates to:
  /// **'Conversões comuns de {fromCurrency}'**
  String currency_converter_commonConversions(Object fromCurrency);

  /// No description provided for @transfer_fromAcc.
  ///
  /// In pt, this message translates to:
  /// **'Origem ({currency})'**
  String transfer_fromAcc(Object currency);

  /// No description provided for @transfer_toAcc.
  ///
  /// In pt, this message translates to:
  /// **'Destino ({currency})'**
  String transfer_toAcc(Object currency);

  /// No description provided for @transfer_exchangeRatesNotLoaded.
  ///
  /// In pt, this message translates to:
  /// **'Taxas de câmbio não carregadas — o montante será transferido no estado em que se encontra'**
  String get transfer_exchangeRatesNotLoaded;

  /// No description provided for @transfer_amount.
  ///
  /// In pt, this message translates to:
  /// **'Montante'**
  String get transfer_amount;

  /// No description provided for @transfer_noteOptional.
  ///
  /// In pt, this message translates to:
  /// **'Nota (opcional)'**
  String get transfer_noteOptional;

  /// No description provided for @export_from.
  ///
  /// In pt, this message translates to:
  /// **'De'**
  String get export_from;

  /// No description provided for @export_to.
  ///
  /// In pt, this message translates to:
  /// **'Para'**
  String get export_to;

  /// No description provided for @export_txCount.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 lançamento no período} other{{count} lançamentos no período}}'**
  String export_txCount(num count);

  /// No description provided for @export_saved.
  ///
  /// In pt, this message translates to:
  /// **'Salvo em: {path}'**
  String export_saved(Object path);

  /// No description provided for @export_complete.
  ///
  /// In pt, this message translates to:
  /// **'Exportação concluída'**
  String get export_complete;

  /// No description provided for @export_exporting.
  ///
  /// In pt, this message translates to:
  /// **'Exportando...'**
  String get export_exporting;

  /// No description provided for @export_exportAsExcel.
  ///
  /// In pt, this message translates to:
  /// **'Exportar como Excel'**
  String get export_exportAsExcel;

  /// No description provided for @shared_widgets_deleteConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Excluir \"{name}\"? Essa ação não pode ser desfeita.'**
  String shared_widgets_deleteConfirm(Object name);

  /// No description provided for @shared_widgets_searchByCode.
  ///
  /// In pt, this message translates to:
  /// **'Pesquise por código ou nome...'**
  String get shared_widgets_searchByCode;

  /// No description provided for @accounts_accounts.
  ///
  /// In pt, this message translates to:
  /// **'Contas'**
  String get accounts_accounts;

  /// No description provided for @accounts_totalBalance.
  ///
  /// In pt, this message translates to:
  /// **'Saldo Total'**
  String get accounts_totalBalance;

  /// No description provided for @accounts_excluded.
  ///
  /// In pt, this message translates to:
  /// **'Excluído'**
  String get accounts_excluded;

  /// No description provided for @accounts_goldPriceNotYetLoade.
  ///
  /// In pt, this message translates to:
  /// **'Preço do ouro ainda não carregado. Aguarde e tente novamente.'**
  String get accounts_goldPriceNotYetLoade;

  /// No description provided for @accounts_accountType.
  ///
  /// In pt, this message translates to:
  /// **'Tipo de Conta'**
  String get accounts_accountType;

  /// No description provided for @accounts_currency.
  ///
  /// In pt, this message translates to:
  /// **'Moeda'**
  String get accounts_currency;

  /// No description provided for @accounts_goldPurityKarat.
  ///
  /// In pt, this message translates to:
  /// **'Pureza do Ouro (Quilates)'**
  String get accounts_goldPurityKarat;

  /// No description provided for @accounts_weight.
  ///
  /// In pt, this message translates to:
  /// **'Peso'**
  String get accounts_weight;

  /// No description provided for @accounts_excludeFromTotalBala.
  ///
  /// In pt, this message translates to:
  /// **'Excluir do Saldo Total'**
  String get accounts_excludeFromTotalBala;

  /// No description provided for @accounts_color.
  ///
  /// In pt, this message translates to:
  /// **'Cor'**
  String get accounts_color;

  /// No description provided for @accounts_liveGoldValue.
  ///
  /// In pt, this message translates to:
  /// **'Valor do Ouro em Tempo Real'**
  String get accounts_liveGoldValue;

  /// No description provided for @accounts_enterWeightAboveToSe.
  ///
  /// In pt, this message translates to:
  /// **'Insira o peso acima para ver o valor'**
  String get accounts_enterWeightAboveToSe;

  /// No description provided for @add_transaction_expense.
  ///
  /// In pt, this message translates to:
  /// **'Despesa'**
  String get add_transaction_expense;

  /// No description provided for @add_transaction_income.
  ///
  /// In pt, this message translates to:
  /// **'Receita'**
  String get add_transaction_income;

  /// No description provided for @add_transaction_account.
  ///
  /// In pt, this message translates to:
  /// **'Conta'**
  String get add_transaction_account;

  /// No description provided for @add_transaction_category.
  ///
  /// In pt, this message translates to:
  /// **'Categoria'**
  String get add_transaction_category;

  /// No description provided for @assets_assets.
  ///
  /// In pt, this message translates to:
  /// **'Ativos'**
  String get assets_assets;

  /// No description provided for @backup_restoreBackup.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar Backup?'**
  String get backup_restoreBackup;

  /// No description provided for @backup_cancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get backup_cancel;

  /// No description provided for @backup_replaceData.
  ///
  /// In pt, this message translates to:
  /// **'Substituir Dados'**
  String get backup_replaceData;

  /// No description provided for @backup_backupRestore.
  ///
  /// In pt, this message translates to:
  /// **'Backup e Restauração'**
  String get backup_backupRestore;

  /// No description provided for @backup_everythingAlways.
  ///
  /// In pt, this message translates to:
  /// **'Tudo, sempre'**
  String get backup_everythingAlways;

  /// No description provided for @backup_createBackup.
  ///
  /// In pt, this message translates to:
  /// **'Criar Backup'**
  String get backup_createBackup;

  /// No description provided for @backup_saveAsJson.
  ///
  /// In pt, this message translates to:
  /// **'Salvar como JSON'**
  String get backup_saveAsJson;

  /// No description provided for @backup_exportsAllAppDataToA.
  ///
  /// In pt, this message translates to:
  /// **'Exporta TODOS os dados do app para um arquivo'**
  String get backup_exportsAllAppDataToA;

  /// No description provided for @backup_restoreBackup_.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar Backup'**
  String get backup_restoreBackup_;

  /// No description provided for @backup_loadFromJson.
  ///
  /// In pt, this message translates to:
  /// **'Carregar do JSON'**
  String get backup_loadFromJson;

  /// No description provided for @backup_picksABackupFileAndR.
  ///
  /// In pt, this message translates to:
  /// **'Escolhe um arquivo de backup e o restaura'**
  String get backup_picksABackupFileAndR;

  /// No description provided for @backup_thisOverwritesAllCur.
  ///
  /// In pt, this message translates to:
  /// **'Isso sobrescreve TODOS os dados atuais.'**
  String get backup_thisOverwritesAllCur;

  /// No description provided for @budget_budgets.
  ///
  /// In pt, this message translates to:
  /// **'Orçamentos'**
  String get budget_budgets;

  /// No description provided for @budget_empty.
  ///
  /// In pt, this message translates to:
  /// **'·'**
  String get budget_empty;

  /// No description provided for @budget_overBudget.
  ///
  /// In pt, this message translates to:
  /// **'Acima do orçamento'**
  String get budget_overBudget;

  /// No description provided for @budget_thisCategoryAlreadyH.
  ///
  /// In pt, this message translates to:
  /// **'Esta categoria já tem um orçamento. Toque para editar.'**
  String get budget_thisCategoryAlreadyH;

  /// No description provided for @budget_period.
  ///
  /// In pt, this message translates to:
  /// **'Período'**
  String get budget_period;

  /// No description provided for @budget_monthly.
  ///
  /// In pt, this message translates to:
  /// **'Mensal'**
  String get budget_monthly;

  /// No description provided for @budget_weekly.
  ///
  /// In pt, this message translates to:
  /// **'Semanal'**
  String get budget_weekly;

  /// No description provided for @budget_category.
  ///
  /// In pt, this message translates to:
  /// **'Categoria'**
  String get budget_category;

  /// No description provided for @categories_categories.
  ///
  /// In pt, this message translates to:
  /// **'Categorias'**
  String get categories_categories;

  /// No description provided for @categories_expense.
  ///
  /// In pt, this message translates to:
  /// **'Despesa'**
  String get categories_expense;

  /// No description provided for @categories_income.
  ///
  /// In pt, this message translates to:
  /// **'Receita'**
  String get categories_income;

  /// No description provided for @categories_color.
  ///
  /// In pt, this message translates to:
  /// **'Cor'**
  String get categories_color;

  /// No description provided for @categories_icon.
  ///
  /// In pt, this message translates to:
  /// **'Ícone'**
  String get categories_icon;

  /// No description provided for @categories_autoBasedOnName.
  ///
  /// In pt, this message translates to:
  /// **'Auto (baseado no nome)'**
  String get categories_autoBasedOnName;

  /// No description provided for @categories_expenseCategories.
  ///
  /// In pt, this message translates to:
  /// **'Categorias de Despesas'**
  String get categories_expenseCategories;

  /// No description provided for @categories_incomeCategories.
  ///
  /// In pt, this message translates to:
  /// **'Categorias de Receitas'**
  String get categories_incomeCategories;

  /// No description provided for @currency_converter_currencyConverter.
  ///
  /// In pt, this message translates to:
  /// **'Conversor de Moedas'**
  String get currency_converter_currencyConverter;

  /// No description provided for @currency_converter_amount.
  ///
  /// In pt, this message translates to:
  /// **'Valor'**
  String get currency_converter_amount;

  /// No description provided for @currency_converter_convertedTo.
  ///
  /// In pt, this message translates to:
  /// **'Convertido para'**
  String get currency_converter_convertedTo;

  /// No description provided for @export_exportTransactions.
  ///
  /// In pt, this message translates to:
  /// **'Exportar Transações'**
  String get export_exportTransactions;

  /// No description provided for @export_dateRange.
  ///
  /// In pt, this message translates to:
  /// **'Período'**
  String get export_dateRange;

  /// No description provided for @export_formatExcelXlsx.
  ///
  /// In pt, this message translates to:
  /// **'Formato: Excel (.xlsx)'**
  String get export_formatExcelXlsx;

  /// No description provided for @home_totalBalance.
  ///
  /// In pt, this message translates to:
  /// **'Saldo Total'**
  String get home_totalBalance;

  /// No description provided for @home_accounts.
  ///
  /// In pt, this message translates to:
  /// **'Contas'**
  String get home_accounts;

  /// No description provided for @home_recentTransactions.
  ///
  /// In pt, this message translates to:
  /// **'Transações Recentes'**
  String get home_recentTransactions;

  /// No description provided for @home_noTransactionsYet.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma transação ainda'**
  String get home_noTransactionsYet;

  /// No description provided for @home_add.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar'**
  String get home_add;

  /// No description provided for @insights_insights.
  ///
  /// In pt, this message translates to:
  /// **'Informações'**
  String get insights_insights;

  /// No description provided for @lended_person_deletePerson.
  ///
  /// In pt, this message translates to:
  /// **'Excluir pessoa'**
  String get lended_person_deletePerson;

  /// No description provided for @lended_person_editPerson.
  ///
  /// In pt, this message translates to:
  /// **'Editar Pessoa'**
  String get lended_person_editPerson;

  /// No description provided for @lended_person_color.
  ///
  /// In pt, this message translates to:
  /// **'Cor'**
  String get lended_person_color;

  /// No description provided for @lended_person_saveChanges.
  ///
  /// In pt, this message translates to:
  /// **'Salvar Alterações'**
  String get lended_person_saveChanges;

  /// No description provided for @lended_person_settled.
  ///
  /// In pt, this message translates to:
  /// **'QUITADO'**
  String get lended_person_settled;

  /// No description provided for @lended_person_settle.
  ///
  /// In pt, this message translates to:
  /// **'Quitar'**
  String get lended_person_settle;

  /// No description provided for @lended_person_setADueDateFirstToEn.
  ///
  /// In pt, this message translates to:
  /// **'Defina uma data de vencimento primeiro para ativar lembretes.'**
  String get lended_person_setADueDateFirstToEn;

  /// No description provided for @lended_person_iLent.
  ///
  /// In pt, this message translates to:
  /// **'Eu Emprestei'**
  String get lended_person_iLent;

  /// No description provided for @lended_person_iBorrowed.
  ///
  /// In pt, this message translates to:
  /// **'Eu Peguei Emprestado'**
  String get lended_person_iBorrowed;

  /// No description provided for @lended_person_accountOptional.
  ///
  /// In pt, this message translates to:
  /// **'Conta (opcional)'**
  String get lended_person_accountOptional;

  /// No description provided for @lended_person_dueDateReminder.
  ///
  /// In pt, this message translates to:
  /// **'Lembrete de Vencimento'**
  String get lended_person_dueDateReminder;

  /// No description provided for @lended_person_remindMeAt.
  ///
  /// In pt, this message translates to:
  /// **'Lembrar-me às'**
  String get lended_person_remindMeAt;

  /// No description provided for @lended_person_active.
  ///
  /// In pt, this message translates to:
  /// **'Ativo'**
  String get lended_person_active;

  /// No description provided for @lended_person_settled_.
  ///
  /// In pt, this message translates to:
  /// **'Quitado'**
  String get lended_person_settled_;

  /// No description provided for @lended_lentMoney.
  ///
  /// In pt, this message translates to:
  /// **'Dinheiro Emprestado'**
  String get lended_lentMoney;

  /// No description provided for @lended_overdue.
  ///
  /// In pt, this message translates to:
  /// **'ATRASADO'**
  String get lended_overdue;

  /// No description provided for @lended_color.
  ///
  /// In pt, this message translates to:
  /// **'Cor'**
  String get lended_color;

  /// No description provided for @more_more.
  ///
  /// In pt, this message translates to:
  /// **'Mais'**
  String get more_more;

  /// No description provided for @onboarding_back.
  ///
  /// In pt, this message translates to:
  /// **'Voltar'**
  String get onboarding_back;

  /// No description provided for @onboarding_welcomeToNexo.
  ///
  /// In pt, this message translates to:
  /// **'Bem-vindo ao Nexo!'**
  String get onboarding_welcomeToNexo;

  /// No description provided for @onboarding_restoreABackup.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar um Backup'**
  String get onboarding_restoreABackup;

  /// No description provided for @onboarding_loadAPreviouslySaved.
  ///
  /// In pt, this message translates to:
  /// **'Carregar um arquivo JSON do Nexo salvo anteriormente'**
  String get onboarding_loadAPreviouslySaved;

  /// No description provided for @onboarding_or.
  ///
  /// In pt, this message translates to:
  /// **'ou'**
  String get onboarding_or;

  /// No description provided for @onboarding_startFresh.
  ///
  /// In pt, this message translates to:
  /// **'Começar do Zero'**
  String get onboarding_startFresh;

  /// No description provided for @onboarding_firstWhatShouldWeCal.
  ///
  /// In pt, this message translates to:
  /// **'Primeiro, como devemos chamá-lo?'**
  String get onboarding_firstWhatShouldWeCal;

  /// No description provided for @onboarding_defaultCurrency.
  ///
  /// In pt, this message translates to:
  /// **'Moeda Padrão'**
  String get onboarding_defaultCurrency;

  /// No description provided for @onboarding_thisWillBeUsedAcross.
  ///
  /// In pt, this message translates to:
  /// **'Isso será usado em todo o app.\nVocê pode mudar isso depois nas Configurações.'**
  String get onboarding_thisWillBeUsedAcross;

  /// No description provided for @onboarding_searchAllCurrencies.
  ///
  /// In pt, this message translates to:
  /// **'Pesquisar todas as moedas'**
  String get onboarding_searchAllCurrencies;

  /// No description provided for @onboarding_yourFirstAccount.
  ///
  /// In pt, this message translates to:
  /// **'Sua Primeira Conta'**
  String get onboarding_yourFirstAccount;

  /// No description provided for @onboarding_setUpYourMainAccount.
  ///
  /// In pt, this message translates to:
  /// **'Configure sua conta principal para começar a rastrear.'**
  String get onboarding_setUpYourMainAccount;

  /// No description provided for @onboarding_accountType.
  ///
  /// In pt, this message translates to:
  /// **'Tipo de Conta'**
  String get onboarding_accountType;

  /// No description provided for @onboarding_currency.
  ///
  /// In pt, this message translates to:
  /// **'Moeda'**
  String get onboarding_currency;

  /// No description provided for @onboarding_color.
  ///
  /// In pt, this message translates to:
  /// **'Cor'**
  String get onboarding_color;

  /// No description provided for @recurring_recurring.
  ///
  /// In pt, this message translates to:
  /// **'Recorrente'**
  String get recurring_recurring;

  /// No description provided for @recurring_income.
  ///
  /// In pt, this message translates to:
  /// **'RECEITA'**
  String get recurring_income;

  /// No description provided for @recurring_2D.
  ///
  /// In pt, this message translates to:
  /// **'−2d'**
  String get recurring_2D;

  /// No description provided for @recurring_skipNextPayment.
  ///
  /// In pt, this message translates to:
  /// **'Pular Próximo Pagamento?'**
  String get recurring_skipNextPayment;

  /// No description provided for @recurring_cancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get recurring_cancel;

  /// No description provided for @recurring_skip.
  ///
  /// In pt, this message translates to:
  /// **'Pular'**
  String get recurring_skip;

  /// No description provided for @recurring_noHistoryYet.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum histórico ainda'**
  String get recurring_noHistoryYet;

  /// No description provided for @recurring_expense.
  ///
  /// In pt, this message translates to:
  /// **'Despesa'**
  String get recurring_expense;

  /// No description provided for @recurring_income_.
  ///
  /// In pt, this message translates to:
  /// **'Receita'**
  String get recurring_income_;

  /// No description provided for @recurring_every.
  ///
  /// In pt, this message translates to:
  /// **'A cada '**
  String get recurring_every;

  /// No description provided for @recurring_days.
  ///
  /// In pt, this message translates to:
  /// **'Dias'**
  String get recurring_days;

  /// No description provided for @recurring_weeks.
  ///
  /// In pt, this message translates to:
  /// **'Semanas'**
  String get recurring_weeks;

  /// No description provided for @recurring_months.
  ///
  /// In pt, this message translates to:
  /// **'Meses'**
  String get recurring_months;

  /// No description provided for @recurring_years.
  ///
  /// In pt, this message translates to:
  /// **'Anos'**
  String get recurring_years;

  /// No description provided for @recurring_payments.
  ///
  /// In pt, this message translates to:
  /// **'Pagamentos'**
  String get recurring_payments;

  /// No description provided for @recurring_totalCost.
  ///
  /// In pt, this message translates to:
  /// **'Custo Total'**
  String get recurring_totalCost;

  /// No description provided for @recurring_account.
  ///
  /// In pt, this message translates to:
  /// **'Conta'**
  String get recurring_account;

  /// No description provided for @recurring_category.
  ///
  /// In pt, this message translates to:
  /// **'Categoria'**
  String get recurring_category;

  /// No description provided for @recurring_paymentReminder.
  ///
  /// In pt, this message translates to:
  /// **'Lembrete de Pagamento'**
  String get recurring_paymentReminder;

  /// No description provided for @recurring_notificationWillFire.
  ///
  /// In pt, this message translates to:
  /// **'A notificação disparará na próxima data de vencimento neste horário.'**
  String get recurring_notificationWillFire;

  /// No description provided for @recurring_remind2DaysBefore.
  ///
  /// In pt, this message translates to:
  /// **'Lembrar 2 dias antes'**
  String get recurring_remind2DaysBefore;

  /// No description provided for @statistics_statistics.
  ///
  /// In pt, this message translates to:
  /// **'Estatísticas'**
  String get statistics_statistics;

  /// No description provided for @statistics_expensesByCategory.
  ///
  /// In pt, this message translates to:
  /// **'Despesas por Categoria'**
  String get statistics_expensesByCategory;

  /// No description provided for @transactions_transactions.
  ///
  /// In pt, this message translates to:
  /// **'Transações'**
  String get transactions_transactions;

  /// No description provided for @transactions_settled.
  ///
  /// In pt, this message translates to:
  /// **'Quitado'**
  String get transactions_settled;

  /// No description provided for @transfer_transfer.
  ///
  /// In pt, this message translates to:
  /// **'Transferência'**
  String get transfer_transfer;

  /// No description provided for @transfer_from.
  ///
  /// In pt, this message translates to:
  /// **'DE'**
  String get transfer_from;

  /// No description provided for @transfer_to.
  ///
  /// In pt, this message translates to:
  /// **'PARA'**
  String get transfer_to;

  /// No description provided for @transfer_enterAnAmountToSeeTh.
  ///
  /// In pt, this message translates to:
  /// **'Insira um valor para ver a conversão'**
  String get transfer_enterAnAmountToSeeTh;

  /// No description provided for @wishlist_wishlist.
  ///
  /// In pt, this message translates to:
  /// **'Lista de Desejos'**
  String get wishlist_wishlist;

  /// No description provided for @wishlist_priority.
  ///
  /// In pt, this message translates to:
  /// **'Prioridade'**
  String get wishlist_priority;

  /// No description provided for @shared_widgets_delete.
  ///
  /// In pt, this message translates to:
  /// **'Excluir?'**
  String get shared_widgets_delete;

  /// No description provided for @shared_widgets_cancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get shared_widgets_cancel;

  /// No description provided for @shared_widgets_delete_.
  ///
  /// In pt, this message translates to:
  /// **'Excluir'**
  String get shared_widgets_delete_;

  /// No description provided for @shared_widgets_none.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum'**
  String get shared_widgets_none;

  /// No description provided for @shared_widgets_selectCurrency.
  ///
  /// In pt, this message translates to:
  /// **'Selecionar Moeda'**
  String get shared_widgets_selectCurrency;

  /// No description provided for @main_home.
  ///
  /// In pt, this message translates to:
  /// **'Início'**
  String get main_home;

  /// No description provided for @main_transactions.
  ///
  /// In pt, this message translates to:
  /// **'Transações'**
  String get main_transactions;

  /// No description provided for @main_recurring.
  ///
  /// In pt, this message translates to:
  /// **'Recorrente'**
  String get main_recurring;

  /// No description provided for @main_accounts.
  ///
  /// In pt, this message translates to:
  /// **'Contas'**
  String get main_accounts;

  /// No description provided for @main_budgets.
  ///
  /// In pt, this message translates to:
  /// **'Orçamentos'**
  String get main_budgets;

  /// No description provided for @main_more.
  ///
  /// In pt, this message translates to:
  /// **'Mais'**
  String get main_more;

  /// No description provided for @onboarding_chooseLanguage.
  ///
  /// In pt, this message translates to:
  /// **'Escolha o idioma'**
  String get onboarding_chooseLanguage;

  /// No description provided for @error_required.
  ///
  /// In pt, this message translates to:
  /// **'Este campo é obrigatório'**
  String get error_required;

  /// No description provided for @recurring_subscriptions.
  ///
  /// In pt, this message translates to:
  /// **'Assinaturas ({count})'**
  String recurring_subscriptions(Object count);

  /// No description provided for @recurring_installments.
  ///
  /// In pt, this message translates to:
  /// **'Parcelas ({count})'**
  String recurring_installments(Object count);

  /// No description provided for @recurring_recurringType.
  ///
  /// In pt, this message translates to:
  /// **'Tipo recorrente'**
  String get recurring_recurringType;

  /// No description provided for @recurring_subscription.
  ///
  /// In pt, this message translates to:
  /// **'Assinatura'**
  String get recurring_subscription;

  /// No description provided for @recurring_installment.
  ///
  /// In pt, this message translates to:
  /// **'Parcelamento'**
  String get recurring_installment;

  /// No description provided for @recurring_installmentsRequireEndDate.
  ///
  /// In pt, this message translates to:
  /// **'As parcelas devem ter uma data final de pagamento.'**
  String get recurring_installmentsRequireEndDate;

  /// No description provided for @backup_importFromOtherApps.
  ///
  /// In pt, this message translates to:
  /// **'Importar de outros aplicativos'**
  String get backup_importFromOtherApps;

  /// No description provided for @backup_importDescription.
  ///
  /// In pt, this message translates to:
  /// **'Importar dados de aplicativos suportados'**
  String get backup_importDescription;

  /// No description provided for @backup_importFromGreenStash.
  ///
  /// In pt, this message translates to:
  /// **'Importar do GreenStash (.json)'**
  String get backup_importFromGreenStash;

  /// Dynamic Color toggle title
  ///
  /// In pt, this message translates to:
  /// **'Cor Dinâmica'**
  String get settings_dynamicColor;

  /// Dynamic Color toggle subtitle
  ///
  /// In pt, this message translates to:
  /// **'Use cores de papel de parede do sistema'**
  String get settings_dynamicColorSubtitle;

  /// Accent Color subtitle
  ///
  /// In pt, this message translates to:
  /// **'Escolha uma cor de semente para o aplicativo'**
  String get settings_accentColorSubtitle;

  /// No description provided for @backup_automaticBackup.
  ///
  /// In pt, this message translates to:
  /// **'Backup Automático'**
  String get backup_automaticBackup;

  /// No description provided for @backup_dailyAutoBackup.
  ///
  /// In pt, this message translates to:
  /// **'Backup automático diário'**
  String get backup_dailyAutoBackup;

  /// No description provided for @backup_runsDailyAt.
  ///
  /// In pt, this message translates to:
  /// **'Funciona diariamente às {time}'**
  String backup_runsDailyAt(String time);

  /// No description provided for @backup_lastBackup.
  ///
  /// In pt, this message translates to:
  /// **'Último backup: {time}'**
  String backup_lastBackup(String time);

  /// No description provided for @backup_savingTo.
  ///
  /// In pt, this message translates to:
  /// **'Salvando em: {path}'**
  String backup_savingTo(String path);

  /// No description provided for @backup_changeTime.
  ///
  /// In pt, this message translates to:
  /// **'Alterar horário'**
  String get backup_changeTime;

  /// No description provided for @backup_changeFolder.
  ///
  /// In pt, this message translates to:
  /// **'Alterar pasta'**
  String get backup_changeFolder;

  /// No description provided for @budget_budgetsAndGoals.
  ///
  /// In pt, this message translates to:
  /// **'Orçamentos e Metas'**
  String get budget_budgetsAndGoals;

  /// No description provided for @onboarding_restoreGreenStash.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar do GreenStash (.json)'**
  String get onboarding_restoreGreenStash;

  /// No description provided for @savings_goalNotFound.
  ///
  /// In pt, this message translates to:
  /// **'Meta não encontrada'**
  String get savings_goalNotFound;

  /// No description provided for @savings_savedSoFar.
  ///
  /// In pt, this message translates to:
  /// **'Salvo até agora'**
  String get savings_savedSoFar;

  /// No description provided for @savings_target.
  ///
  /// In pt, this message translates to:
  /// **'Meta'**
  String get savings_target;

  /// No description provided for @savings_targetDate.
  ///
  /// In pt, this message translates to:
  /// **'Prazo: {date}'**
  String savings_targetDate(String date);

  /// No description provided for @savings_contribute.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar aporte'**
  String get savings_contribute;

  /// No description provided for @savings_withdraw.
  ///
  /// In pt, this message translates to:
  /// **'Retirar'**
  String get savings_withdraw;

  /// No description provided for @savings_noAccounts.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma conta disponível. Adicione uma conta primeiro.'**
  String get savings_noAccounts;

  /// No description provided for @settings_budgetAlerts.
  ///
  /// In pt, this message translates to:
  /// **'Alertas de orçamento'**
  String get settings_budgetAlerts;

  /// No description provided for @settings_budgetAlertsSub.
  ///
  /// In pt, this message translates to:
  /// **'Notificar quando um orçamento ou meta for atingido'**
  String get settings_budgetAlertsSub;

  /// No description provided for @settings_dailyReminder.
  ///
  /// In pt, this message translates to:
  /// **'Lembrete Diário'**
  String get settings_dailyReminder;

  /// No description provided for @settings_dailyReminderSub.
  ///
  /// In pt, this message translates to:
  /// **'Lembre de registrar transações diariamente'**
  String get settings_dailyReminderSub;

  /// No description provided for @settings_reminderTime.
  ///
  /// In pt, this message translates to:
  /// **'Hora do lembrete'**
  String get settings_reminderTime;

  /// No description provided for @settings_hapticFeedback.
  ///
  /// In pt, this message translates to:
  /// **'Feedback tátil'**
  String get settings_hapticFeedback;

  /// No description provided for @settings_hapticFeedbackSub.
  ///
  /// In pt, this message translates to:
  /// **'Vibrar nas interações'**
  String get settings_hapticFeedbackSub;

  /// No description provided for @savings_saveGoal.
  ///
  /// In pt, this message translates to:
  /// **'Salvar meta'**
  String get savings_saveGoal;

  /// No description provided for @more_loans.
  ///
  /// In pt, this message translates to:
  /// **'Empréstimos'**
  String get more_loans;

  /// No description provided for @more_loansSub.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 empréstimo ativo} other{{count} empréstimos ativos}}'**
  String more_loansSub(num count);

  /// No description provided for @loans_title.
  ///
  /// In pt, this message translates to:
  /// **'Empréstimos'**
  String get loans_title;

  /// No description provided for @loans_addLoan.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar empréstimo'**
  String get loans_addLoan;

  /// No description provided for @loans_editLoan.
  ///
  /// In pt, this message translates to:
  /// **'Editar empréstimo'**
  String get loans_editLoan;

  /// No description provided for @loans_loanName.
  ///
  /// In pt, this message translates to:
  /// **'Nome do empréstimo'**
  String get loans_loanName;

  /// No description provided for @loans_amount.
  ///
  /// In pt, this message translates to:
  /// **'Valor'**
  String get loans_amount;

  /// No description provided for @loans_startDate.
  ///
  /// In pt, this message translates to:
  /// **'Data de início'**
  String get loans_startDate;

  /// No description provided for @loans_endDate.
  ///
  /// In pt, this message translates to:
  /// **'Data de término'**
  String get loans_endDate;

  /// No description provided for @loans_interestRateOptional.
  ///
  /// In pt, this message translates to:
  /// **'Taxa de juros (Opcional)'**
  String get loans_interestRateOptional;

  /// No description provided for @loans_account.
  ///
  /// In pt, this message translates to:
  /// **'Conta vinculada'**
  String get loans_account;

  /// No description provided for @loans_monthlyPayment.
  ///
  /// In pt, this message translates to:
  /// **'Pagamento mensal'**
  String get loans_monthlyPayment;

  /// No description provided for @loans_totalPayable.
  ///
  /// In pt, this message translates to:
  /// **'Total a pagar'**
  String get loans_totalPayable;

  /// No description provided for @loans_remaining.
  ///
  /// In pt, this message translates to:
  /// **'Restante'**
  String get loans_remaining;

  /// No description provided for @loans_paid.
  ///
  /// In pt, this message translates to:
  /// **'Pago'**
  String get loans_paid;

  /// No description provided for @loans_logPayment.
  ///
  /// In pt, this message translates to:
  /// **'Registrar pagamento'**
  String get loans_logPayment;

  /// No description provided for @loans_paymentReminder.
  ///
  /// In pt, this message translates to:
  /// **'Lembrete de pagamento'**
  String get loans_paymentReminder;

  /// No description provided for @loans_reminderDay.
  ///
  /// In pt, this message translates to:
  /// **'Dia do lembrete'**
  String get loans_reminderDay;

  /// No description provided for @loans_notes.
  ///
  /// In pt, this message translates to:
  /// **'Notas'**
  String get loans_notes;

  /// No description provided for @loans_saveLoan.
  ///
  /// In pt, this message translates to:
  /// **'Salvar empréstimo'**
  String get loans_saveLoan;

  /// No description provided for @loans_deleteLoan.
  ///
  /// In pt, this message translates to:
  /// **'Excluir empréstimo'**
  String get loans_deleteLoan;

  /// No description provided for @loans_settled.
  ///
  /// In pt, this message translates to:
  /// **'Quitado'**
  String get loans_settled;

  /// No description provided for @loans_durationMonths.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 mês} other{{count} meses}}'**
  String loans_durationMonths(num count);

  /// No description provided for @loans_paymentHistory.
  ///
  /// In pt, this message translates to:
  /// **'Histórico de pagamentos'**
  String get loans_paymentHistory;

  /// No description provided for @loans_noPayments.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum pagamento registrado ainda'**
  String get loans_noPayments;

  /// No description provided for @loans_outstandingDebt.
  ///
  /// In pt, this message translates to:
  /// **'Dívida pendente'**
  String get loans_outstandingDebt;

  /// No description provided for @loans_monthlyObligation.
  ///
  /// In pt, this message translates to:
  /// **'Obrigação mensal'**
  String get loans_monthlyObligation;

  /// No description provided for @insights_loans.
  ///
  /// In pt, this message translates to:
  /// **'Empréstimos'**
  String get insights_loans;

  /// No description provided for @backup_loans.
  ///
  /// In pt, this message translates to:
  /// **'Empréstimos'**
  String get backup_loans;

  /// No description provided for @backup_loanPayments.
  ///
  /// In pt, this message translates to:
  /// **'Pagamentos de empréstimos'**
  String get backup_loanPayments;

  /// No description provided for @more_yearlyAnalysis.
  ///
  /// In pt, this message translates to:
  /// **'Análise anual'**
  String get more_yearlyAnalysis;

  /// No description provided for @more_yearlyAnalysisSub.
  ///
  /// In pt, this message translates to:
  /// **'Previsão de fluxo de caixa mês a mês'**
  String get more_yearlyAnalysisSub;

  /// No description provided for @yearly_title.
  ///
  /// In pt, this message translates to:
  /// **'Análise anual'**
  String get yearly_title;

  /// No description provided for @yearly_recurringExp.
  ///
  /// In pt, this message translates to:
  /// **'Despesas recorrentes'**
  String get yearly_recurringExp;

  /// No description provided for @yearly_recurringInc.
  ///
  /// In pt, this message translates to:
  /// **'Receitas recorrentes'**
  String get yearly_recurringInc;

  /// No description provided for @yearly_loans.
  ///
  /// In pt, this message translates to:
  /// **'Pagamentos de empréstimos'**
  String get yearly_loans;

  /// No description provided for @yearly_borrowed.
  ///
  /// In pt, this message translates to:
  /// **'Dívidas a pagar'**
  String get yearly_borrowed;

  /// No description provided for @yearly_lentDue.
  ///
  /// In pt, this message translates to:
  /// **'Valores a receber'**
  String get yearly_lentDue;

  /// No description provided for @yearly_inflow.
  ///
  /// In pt, this message translates to:
  /// **'Entradas'**
  String get yearly_inflow;

  /// No description provided for @yearly_outflow.
  ///
  /// In pt, this message translates to:
  /// **'Saídas'**
  String get yearly_outflow;

  /// No description provided for @yearly_netFlow.
  ///
  /// In pt, this message translates to:
  /// **'Fluxo líquido'**
  String get yearly_netFlow;

  /// No description provided for @yearly_totalInflow.
  ///
  /// In pt, this message translates to:
  /// **'Entrada total'**
  String get yearly_totalInflow;

  /// No description provided for @yearly_totalOutflow.
  ///
  /// In pt, this message translates to:
  /// **'Saída total'**
  String get yearly_totalOutflow;

  /// No description provided for @yearly_netCashFlow.
  ///
  /// In pt, this message translates to:
  /// **'Fluxo de caixa líquido'**
  String get yearly_netCashFlow;

  /// No description provided for @yearly_noData.
  ///
  /// In pt, this message translates to:
  /// **'Sem atividade projetada'**
  String get yearly_noData;

  /// No description provided for @yearly_noDataSub.
  ///
  /// In pt, this message translates to:
  /// **'Adicione pagamentos recorrentes ou empréstimos para ver a previsão'**
  String get yearly_noDataSub;

  /// No description provided for @budget_addBudget.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar orçamento'**
  String get budget_addBudget;

  /// No description provided for @budget_addGoal.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar meta de economia'**
  String get budget_addGoal;

  /// No description provided for @budget_leftToSpend.
  ///
  /// In pt, this message translates to:
  /// **'Disponível para gastar'**
  String get budget_leftToSpend;

  /// No description provided for @add_transaction_possibleDuplicate.
  ///
  /// In pt, this message translates to:
  /// **'Possível duplicidade'**
  String get add_transaction_possibleDuplicate;

  /// No description provided for @add_transaction_goBack.
  ///
  /// In pt, this message translates to:
  /// **'Revisar'**
  String get add_transaction_goBack;

  /// No description provided for @add_transaction_saveAnyway.
  ///
  /// In pt, this message translates to:
  /// **'Salvar mesmo assim'**
  String get add_transaction_saveAnyway;

  /// No description provided for @loans_confirmDeleteLoan.
  ///
  /// In pt, this message translates to:
  /// **'Excluir este empréstimo e todos os pagamentos?'**
  String get loans_confirmDeleteLoan;

  /// No description provided for @loans_deletePayment.
  ///
  /// In pt, this message translates to:
  /// **'Excluir pagamento'**
  String get loans_deletePayment;

  /// No description provided for @loans_confirmDeletePayment.
  ///
  /// In pt, this message translates to:
  /// **'Excluir este registro de pagamento?'**
  String get loans_confirmDeletePayment;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
