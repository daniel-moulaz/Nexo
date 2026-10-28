import 'package:flutter/material.dart';
import '../widgets/nexo_ui.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'assets_screen.dart';
import 'recurring_screen.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
import 'finance_export_screen.dart';
import 'analysis_screen.dart';
import 'lended_screen.dart';
import 'loans_screen.dart';
import 'settings_screen.dart';
import 'statement_import_screen.dart';
import 'sync_settings_screen.dart';

import 'wishlist_screen.dart';

import 'agenda_screen.dart';
import 'notification_inbox_screen.dart';
import 'accounts_screen.dart';
import 'month_review_screen.dart';
import 'balance_check_screen.dart';
import 'help_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final wishlistLen = app.wishlist.where((w) => !w.isPurchased).length;
    final lendedLen = app.lended.where((l) => !l.isSettled).length;
    final assetsLen = app.assets.length;
    final categoriesLen = app.categories.length;
    final loansLen = app.loans.where((l) => !l.isSettled).length;

    final items = <_Item>[
      const _Item(
          icon: Icons.repeat,
          label: 'Recorrentes e assinaturas',
          sub: 'Contas que se repetem e próximas cobranças',
          screen: RecurringScreen()),
      const _Item(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Contas e cartões',
          sub: 'Saldos, cartões, faturas e vínculo com o banco',
          screen: AccountsScreen()),
      const _Item(
          icon: Icons.help_outline_rounded,
          label: 'Ajuda',
          sub: 'Como o Nexo conta o dinheiro e o que cada parte faz',
          screen: HelpScreen()),
      const _Item(
          icon: Icons.fact_check_outlined,
          label: 'Conferir com o banco',
          sub: 'Saldo do Open Finance × saldo do Nexo, com ajuste neutro',
          screen: BalanceCheckScreen()),
      const _Item(
          icon: Icons.auto_stories_outlined,
          label: 'Mês em revisão',
          sub: 'Destaques do mês e comparação com o anterior',
          screen: MonthReviewScreen()),
      const _Item(
          icon: Icons.inbox_outlined,
          label: 'Sugestões de lançamentos',
          sub: 'Revisar notificações financeiras, sem registro automático',
          screen: NotificationInboxScreen()),
      const _Item(
          icon: Icons.event_note,
          label: 'Agenda financeira',
          sub: 'Próximos vencimentos, receitas, parcelas e faturas',
          screen: AgendaScreen()),
      const _Item(
        icon: Icons.upload_file_rounded,
        label: 'Importar extrato',
        sub: 'Mercado Pago, Nubank e CSV genérico',
        screen: StatementImportScreen(),
      ),
      const _Item(
        icon: Icons.table_view_rounded,
        label: 'Exportar relatório',
        sub: 'Excel e CSV para análise e portabilidade',
        screen: FinanceExportScreen(),
      ),
      const _Item(
          icon: Icons.bar_chart_outlined,
          label: 'Análises',
          sub: 'Categorias, comparações e fechamento mensal',
          screen: AnalysisScreen()),
      _Item(
        icon: Icons.star_outline_rounded,
        label: 'Lista de desejos',
        sub:
            '$wishlistLen ${wishlistLen == 1 ? 'item pendente' : 'itens pendentes'}',
        screen: const WishlistScreen(),
      ),
      _Item(
        icon: Icons.handshake_outlined,
        label: 'Dinheiro emprestado',
        sub:
            '$lendedLen ${lendedLen == 1 ? 'registro em aberto' : 'registros em aberto'}',
        screen: const LendedScreen(),
      ),
      _Item(
        icon: Icons.inventory_2_outlined,
        label: 'Bens e patrimônio',
        sub:
            '$assetsLen ${assetsLen == 1 ? 'item cadastrado' : 'itens cadastrados'}',
        screen: const AssetsScreen(),
      ),
      _Item(
        icon: Icons.account_balance_outlined,
        label: 'Empréstimos',
        sub:
            '$loansLen ${loansLen == 1 ? 'empréstimo ativo' : 'empréstimos ativos'}',
        screen: const LoansScreen(),
      ),
      _Item(
        icon: Icons.label_outline_rounded,
        label: 'Categorias',
        sub: '$categoriesLen categorias cadastradas',
        screen: const CategoriesScreen(),
      ),
      const _Item(
        icon: Icons.backup_outlined,
        label: 'Backup e restauração',
        sub: 'Salve ou recupere todos os dados do aplicativo',
        screen: BackupScreen(),
      ),
      const _Item(
        icon: Icons.devices_outlined,
        label: 'Sincronizar dispositivos',
        sub: 'Acervo compartilhado entre celular e PC, Open Finance e conector',
        screen: SyncSettingsScreen(),
      ),
      const _Item(
        icon: Icons.settings_outlined,
        label: 'Configurações',
        sub: 'Tema, privacidade, moeda, alertas e preferências',
        screen: SettingsScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title:
            const Text('Mais', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
              tooltip: 'Configurações',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                  context, NexoRoute(builder: (_) => const SettingsScreen())))
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final group in <String, List<String>>{
              'Planejar e acompanhar': [
                'Agenda financeira',
                'Contas e cartões',
                'Recorrentes e assinaturas',
                'Análises',
                'Mês em revisão',
              ],
              'Organizar e proteger': [
                'Sugestões de lançamentos',
                'Conferir com o banco',
                'Importar extrato',
                'Exportar relatório',
                'Categorias',
                'Backup e restauração',
                'Sincronizar dispositivos',
                'Configurações',
                'Ajuda',
              ],
              'Outros controles': [
                'Empréstimos',
                'Dinheiro emprestado',
                'Bens e patrimônio',
                'Lista de desejos',
              ],
            }.entries) ...[
              _Group(
                  title: group.key,
                  initiallyOpen: group.key == 'Planejar e acompanhar',
                  items: [
                    for (final label in group.value)
                      items.singleWhere((item) => item.label == label)
                  ]),
              const SizedBox(height: 12),
            ],
          ]),
    );
  }
}

class _Item {
  final IconData icon;
  final String label;
  final String sub;
  final Widget screen;

  const _Item({
    required this.icon,
    required this.label,
    required this.sub,
    required this.screen,
  });
}

/// One group of the Mais screen: a flat card whose header opens and closes
/// the list, with a hairline between the items.
class _Group extends StatefulWidget {
  const _Group(
      {required this.title, required this.items, this.initiallyOpen = false});
  final String title;
  final List<_Item> items;
  final bool initiallyOpen;
  @override
  State<_Group> createState() => _GroupState();
}

class _GroupState extends State<_Group> {
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NexoCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800))),
              AnimatedRotation(
                  turns: open ? .5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(Icons.expand_more, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Column(children: [
                  for (final (i, item) in widget.items.indexed) ...[
                    Divider(
                        height: 1,
                        indent: i == 0 ? 0 : 56,
                        color: cs.outlineVariant.withValues(alpha: .6)),
                    ListTile(
                        leading: Icon(item.icon, color: cs.primary),
                        title: Text(item.label),
                        subtitle: Text(item.sub),
                        trailing: Icon(Icons.chevron_right,
                            color: cs.onSurfaceVariant),
                        onTap: () => Navigator.push(
                            context, NexoRoute(builder: (_) => item.screen))),
                  ],
                  const SizedBox(height: 4),
                ]),
        ),
      ]),
    );
  }
}
