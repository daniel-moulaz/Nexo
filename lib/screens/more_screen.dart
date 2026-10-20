import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'assets_screen.dart';
import 'recurring_screen.dart';
import 'budget_screen.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
import 'currency_converter_screen.dart';
import 'finance_export_screen.dart';
import 'financial_planning_screen.dart';
import 'analysis_screen.dart';
import 'lended_screen.dart';
import 'loans_screen.dart';
import 'settings_screen.dart';
import 'statement_import_screen.dart';
import 'sync_settings_screen.dart';

import 'wishlist_screen.dart';

import 'agenda_screen.dart';
import 'notification_inbox_screen.dart';
import 'debt_overview_screen.dart';
import 'financial_checkup_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          color: Color(0xFF00897B),
          screen: RecurringScreen()),
      const _Item(
          icon: Icons.pie_chart_outline,
          label: 'Orçamentos e objetivos',
          sub: 'Limites de gastos e metas para guardar dinheiro',
          color: Color(0xFF00897B),
          screen: BudgetScreen()),
      const _Item(
          icon: Icons.fact_check_outlined,
          label: 'Revisão financeira',
          sub: 'Resumo de 3 ou 7 dias e próximos compromissos',
          color: Color(0xFF00695C),
          screen: FinancialCheckupScreen()),
      const _Item(
          icon: Icons.account_balance_outlined,
          label: 'Dívidas e compromissos',
          sub: 'Cartões, empréstimos, parcelas e despesas pendentes',
          color: Color(0xFF6750A4),
          screen: DebtOverviewScreen()),
      const _Item(
          icon: Icons.inbox_outlined,
          label: 'Sugestões de lançamentos',
          sub: 'Revisar notificações financeiras, sem registro automático',
          color: Color(0xFF00695C),
          screen: NotificationInboxScreen()),
      const _Item(
          icon: Icons.event_note,
          label: 'Agenda financeira',
          sub: 'Próximos vencimentos, receitas, parcelas e faturas',
          color: Color(0xFF00897B),
          screen: AgendaScreen()),
      const _Item(
        icon: Icons.auto_graph_rounded,
        label: 'Previsão detalhada',
        sub: 'Previsão de caixa, assinaturas, reserva e alertas',
        color: Color(0xFF6750A4),
        screen: FinancialPlanningScreen(),
      ),
      const _Item(
        icon: Icons.upload_file_rounded,
        label: 'Importar extrato',
        sub: 'Mercado Pago, Nubank e CSV genérico',
        color: Color(0xFF00897B),
        screen: StatementImportScreen(),
      ),
      const _Item(
        icon: Icons.table_view_rounded,
        label: 'Exportar relatório',
        sub: 'Excel e CSV para análise e portabilidade',
        color: Color(0xFF2E7D32),
        screen: FinanceExportScreen(),
      ),
      const _Item(
          icon: Icons.bar_chart_outlined,
          label: 'Análises',
          sub: 'Categorias, comparações e fechamento mensal',
          color: Color(0xFF1565C0),
          screen: AnalysisScreen()),
      const _Item(
        icon: Icons.currency_exchange_rounded,
        label: 'Conversor de moeda',
        sub: 'Converta valores entre moedas',
        color: Color(0xFF6750A4),
        screen: CurrencyConverterScreen(),
      ),
      _Item(
        icon: Icons.star_outline_rounded,
        label: 'Lista de desejos',
        sub:
            '$wishlistLen ${wishlistLen == 1 ? 'item pendente' : 'itens pendentes'}',
        color: const Color(0xFF7D5260),
        screen: const WishlistScreen(),
      ),
      _Item(
        icon: Icons.handshake_outlined,
        label: 'Dinheiro emprestado',
        sub:
            '$lendedLen ${lendedLen == 1 ? 'registro em aberto' : 'registros em aberto'}',
        color: const Color(0xFFE65140),
        screen: const LendedScreen(),
      ),
      _Item(
        icon: Icons.inventory_2_outlined,
        label: 'Bens e patrimônio',
        sub:
            '$assetsLen ${assetsLen == 1 ? 'item cadastrado' : 'itens cadastrados'}',
        color: const Color(0xFF1565C0),
        screen: const AssetsScreen(),
      ),
      _Item(
        icon: Icons.account_balance_outlined,
        label: 'Empréstimos',
        sub:
            '$loansLen ${loansLen == 1 ? 'empréstimo ativo' : 'empréstimos ativos'}',
        color: const Color(0xFF4A148C),
        screen: const LoansScreen(),
      ),
      _Item(
        icon: Icons.label_outline_rounded,
        label: 'Categorias',
        sub: '$categoriesLen categorias cadastradas',
        color: const Color(0xFF00897B),
        screen: const CategoriesScreen(),
      ),
      const _Item(
        icon: Icons.backup_outlined,
        label: 'Backup e restauração',
        sub: 'Salve ou recupere todos os dados do aplicativo',
        color: Color(0xFF37474F),
        screen: BackupScreen(),
      ),
      const _Item(
        icon: Icons.devices_outlined,
        label: 'Sincronizar dispositivos',
        sub: 'Conta e teste do servidor; sincronização ainda inativa',
        color: Color(0xFF00695C),
        screen: SyncSettingsScreen(),
      ),
      const _Item(
        icon: Icons.settings_outlined,
        label: 'Configurações',
        sub: 'Tema, privacidade, moeda, alertas e preferências',
        color: Color(0xFF4A148C),
        screen: SettingsScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title:
            const Text('Mais', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        actions: [
          IconButton(
              tooltip: 'Configurações',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context,
                  ExpensyRoute(builder: (_) => const SettingsScreen())))
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final group in <String, List<String>>{
              'Planejar e acompanhar': [
                'Agenda financeira',
                'Recorrentes e assinaturas',
                'Orçamentos e objetivos',
                'Dívidas e compromissos',
                'Análises',
                'Revisão financeira',
              ],
              'Organizar e proteger': [
                'Sugestões de lançamentos',
                'Importar extrato',
                'Exportar relatório',
                'Categorias',
                'Backup e restauração',
                'Sincronizar dispositivos',
                'Configurações'
              ],
              'Outros controles': [
                'Empréstimos',
                'Dinheiro emprestado',
                'Bens e patrimônio',
                'Lista de desejos',
                'Previsão detalhada',
                'Conversor de moeda',
              ],
            }.entries)
              Card(
                  child: ExpansionTile(
                      title: Text(group.key),
                      initiallyExpanded: group.key == 'Planejar e acompanhar',
                      children: [
                    for (final item in group.value.map((label) =>
                        items.singleWhere((item) => item.label == label)))
                      ListTile(
                          leading: Icon(item.icon, color: item.color),
                          title: Text(item.label),
                          subtitle: Text(item.sub),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(context,
                              ExpensyRoute(builder: (_) => item.screen))),
                  ])),
          ]),
    );
  }
}

class _Item {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final Widget screen;

  const _Item({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.screen,
  });
}
