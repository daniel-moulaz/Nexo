// lib/screens/net_worth_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../l10n/app_localizations.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/nexo_ui.dart';

class NetWorthScreen extends StatelessWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    final app = context.watch<AppProvider>();
    final snapshots = app.netWorthSnapshots;
    final worth = app.netWorthInputs();
    final totalAccounts = app.totalBalanceAll;
    final totalAssets = app.totalAssetsValue;
    final liveNetWorth = app.netWorthNow;
    final otherParts = liveNetWorth - totalAccounts - totalAssets;
    final currency =
        context.select<AppProvider, String>((app) => app.settings.currency);
    String fmt(double v) => formatAmount(v, currency);

    final spots = <FlSpot>[];
    for (int i = 0; i < snapshots.length; i++) {
      spots.add(FlSpot(i.toDouble(), worth.snapshotTotal(snapshots[i])));
    }
    // Append live current net worth point
    spots.add(FlSpot(snapshots.length.toDouble(), liveNetWorth));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.more_insights, // Fallback if netWorth_title unavailable
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
        children: [
          // Current Net Worth Hero Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Patrimônio atual',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fmt(liveNetWorth),
                    style: TextStyle(
                      fontFeatures: NexoTones.figures,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Investimentos pela última cotação: ${fmt(otherParts)} com objetivos, dinheiro emprestado e dívidas.',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Net Worth Trend Chart Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evolução do patrimônio',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: LineChart(
                      LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: cs.primary,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: cs.primary.withValues(alpha: 0.12),
                            ),
                          ),
                        ],
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: cs.outlineVariant.withValues(alpha: 0.3),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        lineTouchData: const LineTouchData(enabled: true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Breakdown Row (Accounts vs Assets)
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                size: 18, color: cs.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Contas e cartões',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fmt(totalAccounts),
                          style: TextStyle(
                            fontFeatures: NexoTones.figures,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 18, color: NexoTones.info(context)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Bens',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fmt(totalAssets),
                          style: TextStyle(
                            fontFeatures: NexoTones.figures,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
