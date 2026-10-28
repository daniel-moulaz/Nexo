import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../screens/accounts_screen.dart';
import '../screens/add_transaction_screen.dart';
import '../screens/assets_screen.dart';
import '../screens/backup_screen.dart';
import '../screens/balance_check_screen.dart';
import '../screens/card_invoice_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/finance_export_screen.dart';
import '../screens/help_screen.dart';
import '../screens/import_rules_screen.dart';
import '../screens/lended_screen.dart';
import '../screens/loans_screen.dart';
import '../screens/month_review_screen.dart';
import '../screens/notification_inbox_screen.dart';
import '../screens/reminder_settings_screen.dart';
import '../screens/security_settings_screen.dart';
import '../screens/sync_settings_screen.dart';
import '../screens/transfer_screen.dart';
import '../screens/wishlist_screen.dart';
import '../services/category_memory.dart';
import '../services/text_entry.dart';
import '../services/text_normalize.dart';
import '../theme/app_theme.dart';
import '../screens/home_customize_sheet.dart';

/// Where a palette entry runs: the context the palette was opened from
/// (still mounted after the palette closes) and the app state.
class PaletteHost {
  const PaletteHost(this.context, this.app);
  final BuildContext context;
  final AppProvider app;

  void push(Widget screen) =>
      Navigator.of(context).push(NexoRoute(builder: (_) => screen));
  void tab(int index) => app.tabIndexNotifier.value = index;
}

class CommandEntry {
  const CommandEntry(
      {required this.title,
      required this.icon,
      required this.run,
      this.subtitle,
      this.shortcut,
      this.keywords = ''});
  final String title;
  final String? subtitle;
  final IconData icon;

  /// Shown on wide screens, where the keyboard is real.
  final String? shortcut;
  final String keywords;
  final void Function(PaletteHost host) run;
}

/// Everything the palette can reach, filtered by [query]. Screens and
/// actions always; accounts, entries and "lançar por texto" when the query
/// says enough. The order is the order of likely use.
List<CommandEntry> paletteEntries(AppProvider app, String query) {
  final q = normalizeText(query).trim();
  final words = wordsOf(query);
  final out = <CommandEntry>[];

  bool matches(CommandEntry e) {
    if (q.isEmpty) return true;
    final hay = wordsOf('${e.title} ${e.subtitle ?? ''} ${e.keywords}');
    final short = normalizeText(e.title);
    return words.every((w) => hay.any((h) => h.startsWith(w))) ||
        short.contains(q);
  }

  // ── Lançar por texto: only when the line carries an amount ──
  if (words.isNotEmpty) {
    final entry = TextEntryParser.parse(query,
        accounts: app.accounts,
        categories: app.categories,
        memory: CategoryMemory.fromTransactions(app.transactions));
    if (entry.complete) {
      final currency = app.accountById(entry.accountId ?? '')?.currency ??
          app.settings.currency;
      final parts = [
        formatAmount(entry.amount!, currency),
        if (entry.description.isNotEmpty) entry.description,
        DateFormat('dd/MM').format(entry.date),
        if (entry.accountId != null) app.accountById(entry.accountId!)?.name,
        if (entry.categoryId != null) app.categoryById(entry.categoryId!)?.name,
      ].whereType<String>();
      out.add(CommandEntry(
          title: entry.type == 'income' ? 'Lançar receita' : 'Lançar despesa',
          subtitle: parts.join(' · '),
          icon: Icons.bolt_outlined,
          run: (h) => h.push(AddTransactionScreen(
              initialType: entry.type,
              initialDate: entry.date,
              template: AppTransaction(
                  id: '',
                  type: entry.type,
                  amount: entry.amount!,
                  description: entry.description,
                  accountId: entry.accountId ?? '',
                  categoryId: entry.categoryId ?? '',
                  date: entry.date,
                  currency: currency)))));
    }
  }

  final actions = [
    CommandEntry(
        title: 'Nova despesa',
        icon: Icons.add,
        shortcut: 'Ctrl+N',
        keywords: 'gasto lançamento lancamento',
        run: (h) => h.push(const AddTransactionScreen())),
    CommandEntry(
        title: 'Nova receita',
        icon: Icons.south_west_rounded,
        keywords: 'entrada renda lançamento',
        run: (h) => h.push(const AddTransactionScreen(initialType: 'income'))),
    CommandEntry(
        title: 'Transferir entre contas',
        icon: Icons.swap_horiz,
        keywords: 'transferencia transferência',
        run: (h) => h.push(const TransferScreen())),
    CommandEntry(
        title: 'Para revisar',
        subtitle: 'Sugestões do Open Finance',
        icon: Icons.inbox_outlined,
        keywords: 'banco revisar sugestões',
        run: (h) => h.push(const NotificationInboxScreen())),
    CommandEntry(
        title: 'Personalizar o Hoje',
        subtitle: 'Ordem e visibilidade dos cartões',
        icon: Icons.tune,
        keywords: 'home início cartões ordem',
        run: (h) => showHomeCustomizeSheet(h.context)),
  ];
  final tabs = [
    (0, 'Hoje', 'Resumo do mês e ações', Icons.today_outlined, ''),
    (
      8,
      'Extrato',
      'Todos os lançamentos',
      Icons.receipt_long_outlined,
      'transações buscar'
    ),
    (
      4,
      'Orçamento',
      'Envelopes, limites e objetivos',
      Icons.pie_chart_outline,
      'metas objetivos orçamentos'
    ),
    (11, 'Investir', 'Carteira e aportes', Icons.show_chart, 'investimentos'),
    (
      3,
      'Contas e cartões',
      'Saldos e faturas',
      Icons.account_balance_wallet_outlined,
      'fatura cartão'
    ),
    (2, 'Recorrentes', 'Contas que se repetem', Icons.repeat, 'assinaturas'),
    (7, 'Agenda', 'Próximos vencimentos', Icons.event_note, 'calendário'),
    (6, 'Análises', 'Categorias e comparações', Icons.bar_chart, 'gráficos'),
    (
      10,
      'Importar extrato',
      'CSV, OFX, Nubank, Mercado Pago',
      Icons.upload_file_outlined,
      ''
    ),
    (
      9,
      'Configurações',
      'Tema, moeda, alertas',
      Icons.settings_outlined,
      'ajustes preferências'
    ),
    (5, 'Mais', 'Tudo o resto', Icons.more_horiz, ''),
  ];
  final screens = [
    CommandEntry(
        title: 'Mês em revisão',
        icon: Icons.auto_stories_outlined,
        run: (h) => h.push(const MonthReviewScreen())),
    CommandEntry(
        title: 'Conferir com o banco',
        subtitle: 'Saldo do Open Finance × Nexo',
        icon: Icons.fact_check_outlined,
        run: (h) => h.push(const BalanceCheckScreen())),
    CommandEntry(
        title: 'Exportar relatório',
        icon: Icons.table_view_rounded,
        keywords: 'excel csv',
        run: (h) => h.push(const FinanceExportScreen())),
    CommandEntry(
        title: 'Categorias',
        icon: Icons.label_outline_rounded,
        run: (h) => h.push(const CategoriesScreen())),
    CommandEntry(
        title: 'Regras de categoria',
        icon: Icons.rule,
        run: (h) => h.push(const ImportRulesScreen())),
    CommandEntry(
        title: 'Empréstimos',
        icon: Icons.account_balance_outlined,
        run: (h) => h.push(const LoansScreen())),
    CommandEntry(
        title: 'Dinheiro emprestado',
        icon: Icons.handshake_outlined,
        run: (h) => h.push(const LendedScreen())),
    CommandEntry(
        title: 'Bens e patrimônio',
        icon: Icons.inventory_2_outlined,
        run: (h) => h.push(const AssetsScreen())),
    CommandEntry(
        title: 'Lista de desejos',
        icon: Icons.star_outline_rounded,
        run: (h) => h.push(const WishlistScreen())),
    CommandEntry(
        title: 'Backup e restauração',
        icon: Icons.backup_outlined,
        run: (h) => h.push(const BackupScreen())),
    CommandEntry(
        title: 'Sincronizar dispositivos',
        icon: Icons.devices_outlined,
        keywords: 'open finance conector claude',
        run: (h) => h.push(const SyncSettingsScreen())),
    CommandEntry(
        title: 'Segurança',
        subtitle: 'PIN, biometria, privacidade',
        icon: Icons.lock_outline,
        run: (h) => h.push(const SecuritySettingsScreen())),
    CommandEntry(
        title: 'Notificações',
        subtitle: 'Lembretes e fechamento semanal',
        icon: Icons.notifications_outlined,
        run: (h) => h.push(const ReminderSettingsScreen())),
    CommandEntry(
        title: 'Ajuda',
        icon: Icons.help_outline_rounded,
        run: (h) => h.push(const HelpScreen())),
  ];

  out.addAll(actions.where(matches));
  for (final t in tabs) {
    final e = CommandEntry(
        title: t.$2,
        subtitle: t.$3,
        icon: t.$4,
        keywords: t.$5,
        shortcut: t.$1 == 8 ? 'Ctrl+F' : null,
        run: (h) => h.tab(t.$1));
    if (matches(e)) out.add(e);
  }
  out.addAll(screens.where(matches));

  // ── Accounts and cards, by name ──
  if (words.isNotEmpty) {
    for (final a in app.accounts) {
      final e = CommandEntry(
          title: a.name,
          subtitle: a.type == 'credit'
              ? 'Cartão · fatura'
              : 'Conta · ${app.settings.hideBalance ? '••••' : formatAmount(a.balance, a.currency)}',
          icon: a.type == 'credit'
              ? Icons.credit_card
              : Icons.account_balance_outlined,
          run: (h) => h.push(a.type == 'credit'
              ? CardInvoiceScreen(cardId: a.id)
              : const AccountsScreen()));
      if (matches(e)) out.add(e);
    }
  }

  // ── Entries, newest first, by description ──
  if (q.length >= 2) {
    final hits = app.transactions
        .where((t) => words
            .every((w) => wordsOf(t.description).any((d) => d.startsWith(w))))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final t in hits.take(6)) {
      final currency = t.currency.isEmpty ? app.settings.currency : t.currency;
      out.add(CommandEntry(
          title: t.description,
          subtitle:
              '${t.type == 'income' ? '+' : '−'}${app.settings.hideBalance ? '••••' : formatAmount(t.amount, currency)} · ${DateFormat('dd/MM/yyyy').format(t.date)} · ${app.accountById(t.accountId)?.name ?? ''}',
          icon: t.type == 'income'
              ? Icons.south_west_rounded
              : Icons.north_east_rounded,
          run: (h) => h.push(AddTransactionScreen(existing: t))));
    }
  }
  return out;
}

/// Opens the palette: a dialog on wide screens, a full page on phones.
Future<void> showCommandPalette(BuildContext context) {
  final host = PaletteHost(context, context.read<AppProvider>());
  if (MediaQuery.sizeOf(context).width >= 900) {
    return showDialog<void>(
        context: context,
        builder: (_) => Dialog(
            alignment: Alignment.topCenter,
            insetPadding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
                width: 600, height: 520, child: CommandPaletteView(host))));
  }
  return Navigator.of(context).push(NexoSlideUpRoute(
      builder: (_) =>
          Scaffold(body: SafeArea(child: CommandPaletteView(host)))));
}

class CommandPaletteView extends StatefulWidget {
  const CommandPaletteView(this.host, {super.key});
  final PaletteHost host;
  @override
  State<CommandPaletteView> createState() => _CommandPaletteViewState();
}

class _CommandPaletteViewState extends State<CommandPaletteView> {
  final _controller = TextEditingController();
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(CommandEntry entry) {
    Navigator.of(context).pop();
    entry.run(widget.host);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final app = context.watch<AppProvider>();
    final entries = paletteEntries(app, _controller.text);
    if (_selected >= entries.length) _selected = 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(
            () => _selected = entries.isEmpty
                ? 0
                : (_selected + 1).clamp(0, entries.length - 1)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            setState(() => _selected = (_selected - 1).clamp(0, 0x7fffffff)),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.go,
                decoration: const InputDecoration(
                    hintText: 'Tela, ação ou "mercado 45,90 ontem"',
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none),
                onChanged: (_) => setState(() => _selected = 0),
                onSubmitted: (text) {
                  // Read the list for the text as submitted, not the one
                  // this field was built with.
                  final current = paletteEntries(app, text);
                  if (current.isEmpty) return;
                  _run(current[_selected.clamp(0, current.length - 1)]);
                },
              ),
            ),
            IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text('Nada com esse nome.',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return ListTile(
                      selected: wide && i == _selected,
                      leading: Icon(e.icon),
                      title: Text(e.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: e.subtitle == null
                          ? null
                          : Text(e.subtitle!,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: wide && e.shortcut != null
                          ? Text(e.shortcut!,
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12))
                          : null,
                      onTap: () => _run(e),
                    );
                  }),
        ),
      ]),
    );
  }
}
