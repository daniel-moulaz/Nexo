import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'assets_screen.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
import 'currency_converter_screen.dart';
import 'finance_export_screen.dart';
import 'financial_planning_screen.dart';
import 'insights_screen.dart';
import 'lended_screen.dart';
import 'loans_screen.dart';
import 'settings_screen.dart';
import 'statement_import_screen.dart';
import 'statistics_screen.dart';
import 'transaction_search_screen.dart';
import 'wishlist_screen.dart';
import 'yearly_analysis_screen.dart';
import 'agenda_screen.dart';
import 'notification_inbox_screen.dart';

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
      const _Item(icon: Icons.inbox_outlined, label: 'Sugestões de lançamentos', sub: 'Revisar notificações financeiras, sem registro automático', color: Color(0xFF00695C), screen: NotificationInboxScreen()),
      const _Item(
          icon: Icons.event_note,
          label: 'Agenda financeira',
          sub: 'Próximos vencimentos, receitas, parcelas e faturas',
          color: Color(0xFF00897B),
          screen: AgendaScreen()),
      const _Item(
        icon: Icons.auto_graph_rounded,
        label: 'Planejamento',
        sub: 'Previsão de caixa, assinaturas, reserva e alertas',
        color: Color(0xFF6750A4),
        screen: FinancialPlanningScreen(),
      ),
      const _Item(
        icon: Icons.search_rounded,
        label: 'Buscar lançamentos',
        sub: 'Encontre despesas e receitas por nome, conta ou categoria',
        color: Color(0xFF0061A4),
        screen: TransactionSearchScreen(),
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
        label: 'Relatório financeiro',
        sub: 'Excel e CSV para análise e portabilidade',
        color: Color(0xFF2E7D32),
        screen: FinanceExportScreen(),
      ),
      const _Item(
        icon: Icons.bar_chart_outlined,
        label: 'Estatísticas',
        sub: 'Gráficos e resumo mensal',
        color: Color(0xFF1565C0),
        screen: StatisticsScreen(),
      ),
      const _Item(
        icon: Icons.insights_outlined,
        label: 'Informações e tendências',
        sub: 'Médias, categorias e padrões de gastos',
        color: Color(0xFF00838F),
        screen: InsightsScreen(),
      ),
      const _Item(
        icon: Icons.calendar_month_outlined,
        label: 'Análise anual',
        sub: 'Fluxo de caixa e visão mês a mês',
        color: Color(0xFF2E7D32),
        screen: YearlyAnalysisScreen(),
      ),
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
        label: 'Ativos',
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
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final group in <String, List<String>>{
              'Planejamento': [
                'Agenda financeira',
                'Planejamento',
                'Buscar lançamentos'
              ],
              'Relatórios e arquivos': [
                'Relatório financeiro',
                'Importar extrato',
                'Estatísticas',
                'Informações e tendências',
                'Análise anual'
              ],
              'Categorias e preferências': [
                'Sugestões de lançamentos',
                'Categorias',
                'Backup',
                'Backup e restauração',
                'Configurações'
              ],
              'Ferramentas avançadas': [
                'Conversor de moeda',
                'Lista de desejos',
                'Dinheiro emprestado',
                'Empréstimos',
                'Patrimônio',
                'Ativos'
              ],
            }.entries)
              Card(
                  child: ExpansionTile(
                      title: Text(group.key),
                      initiallyExpanded: group.key == 'Planejamento',
                      children: [
                    for (final item in items
                        .where((item) => group.value.contains(item.label)))
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
