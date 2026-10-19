import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../investments/investment_quotes.dart';
import '../providers/app_provider.dart';
import 'analysis_widgets.dart';

/// Market changes are never presented as the user's portfolio return.
class InvestmentMarketInfo extends StatefulWidget {
  final String ticker;
  final bool expanded;
  final DateTime priceAt;
  const InvestmentMarketInfo(
      {super.key,
      required this.ticker,
      required this.priceAt,
      this.expanded = false});
  @override
  State<InvestmentMarketInfo> createState() => _InvestmentMarketInfoState();
}

class _InvestmentMarketInfoState extends State<InvestmentMarketInfo> {
  late Future<(MarketSnapshot?, bool)> _data;
  Future<(MarketSnapshot?, bool)> _load() async => (
        await MarketCache.read(widget.ticker),
        await InvestmentQuoteSettings.enabled()
      );
  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  @override
  void didUpdateWidget(covariant InvestmentMarketInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _data = _load();
  }

  @override
  Widget build(BuildContext context) {
    final private = context.watch<AppProvider>().settings.hideBalance;
    return FutureBuilder<(MarketSnapshot?, bool)>(
      future: _data,
      builder: (context, snapshot) {
        final market = snapshot.data?.$1;
        if (market == null) return const SizedBox.shrink();
        final change = market.value('regularMarketChangePercent');
        final dark = Theme.of(context).brightness == Brightness.dark;
        final color = private || change == null || change == 0
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : change > 0
                ? (dark ? const Color(0xff69dbad) : const Color(0xff146c43))
                : (dark ? const Color(0xffffa4a4) : const Color(0xffb3261e));
        final fallback = Center(
            child: Text(widget.ticker.substring(0, 1),
                style: const TextStyle(fontWeight: FontWeight.bold)));
        final logo = market.logo;
        String amount(String key) {
          final value = market.value(key);
          return private
              ? '••••'
              : value == null
                  ? 'Não informado'
                  : key == 'marketCap'
                      ? NumberFormat.compactCurrency(
                              locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2)
                          .format(value)
                      : NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                          .format(value);
        }

        final date = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
            .format(market.date.toLocal());
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.black),
                      child: logo != null && snapshot.data?.$2 == true
                          ? SvgPicture.network(logo,
                              fit: BoxFit.contain,
                              semanticsLabel: 'Logo de ${widget.ticker}',
                              placeholderBuilder: (_) => fallback,
                              errorBuilder: (_, __, ___) => fallback)
                          : fallback)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        private
                            ? 'Variação do pregão oculta'
                            : change == null
                                ? 'Variação do pregão não informada'
                                : '${change > 0 ? '+' : ''}${NumberFormat('0.00', 'pt_BR').format(change)}% no pregão',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w600)),
                    Text('brapi · $date',
                        style: Theme.of(context).textTheme.bodySmall),
                  ])),
            ]),
            if (widget.expanded)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Dados de mercado'),
                subtitle: const Text('Última consulta · pode haver atraso'),
                children: [
                  AnalysisMetrics(values: [
                    ('Variação por unidade', amount('regularMarketChange')),
                    ('Abertura', amount('regularMarketOpen')),
                    (
                      'Fechamento anterior',
                      amount('regularMarketPreviousClose')
                    ),
                    ('Mínima do pregão', amount('regularMarketDayLow')),
                    ('Máxima do pregão', amount('regularMarketDayHigh')),
                    ('Mínima em 52 semanas', amount('fiftyTwoWeekLow')),
                    ('Máxima em 52 semanas', amount('fiftyTwoWeekHigh')),
                    ('Valor de mercado (aprox.)', amount('marketCap')),
                    (
                      'Volume negociado (unidades)',
                      private
                          ? '••••'
                          : market.value('regularMarketVolume') == null
                              ? 'Não informado'
                              : NumberFormat.decimalPattern('pt_BR')
                                  .format(market.value('regularMarketVolume'))
                    ),
                  ]),
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          'Dados do ativo no mercado, independentes das suas compras. A variação do pregão não é o ganho da sua posição.')),
                ],
              ),
          ]),
        );
      },
    );
  }
}
