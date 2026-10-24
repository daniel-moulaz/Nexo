import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../investments/investment_models.dart';
import '../investments/investment_repository.dart';
import '../providers/app_provider.dart';
import '../services/bank_snapshots.dart';
import '../services/balance_check.dart';
import '../services/liquidity.dart';
import '../widgets/analysis_widgets.dart';
import '../widgets/nexo_ui.dart';

/// What to do before a bill the cash will not cover: how much is missing and
/// the real options with their timing — reserves and investments that
/// arrive in time, the minimum payment and its cost, expected income.
/// Read-only: nothing is moved from here.
class DuePlanScreen extends StatefulWidget {
  const DuePlanScreen({super.key, required this.shortfall});
  final Shortfall shortfall;
  @override
  State<DuePlanScreen> createState() => _DuePlanScreenState();
}

class _DuePlanScreenState extends State<DuePlanScreen> {
  List<InvestmentPosition>? _positions;
  List<BankAccountSnapshot> _bank = const [];

  @override
  void initState() {
    super.initState();
    InvestmentRepository().load().then((p) {
      if (mounted) setState(() => _positions = p);
    }, onError: (_) {
      if (mounted) setState(() => _positions = const []);
    });
    BankSnapshots.load().then((b) {
      if (mounted) setState(() => _bank = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    String money(double v) => analysisMoney(app, v);
    final s = widget.shortfall;
    final due = s.event.date;
    final fmt = DateFormat("EEE dd/MM", 'pt_BR');
    final now = DateTime.now();
    final options = _positions == null
        ? null
        : raiseBy(
            due: due,
            now: now,
            positions: _positions!,
            goals: app.savingsGoals);
    final inTime =
        options?.where((o) => o.inTime).fold<double>(0, (t, o) => t + o.amount);
    final card = s.event.kind == 'invoice'
        ? BankSnapshots.linkedTo(_bank, s.event.accountId)
        : null;
    final small = Theme.of(context).textTheme.bodySmall;

    return Scaffold(
      appBar: AppBar(title: const Text('Plano para o vencimento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          NexoCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.event.title} · vence ${fmt.format(due)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Faltam ${money(s.missing)}',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: NexoTones.expense(context),
                      fontFeatures: NexoTones.figures)),
              Text(
                  'Pela previsão, depois de pagar ${money(-s.event.amount)} o saldo fica em ${money(s.balanceAfter)}. A previsão já inclui as receitas e contas cadastradas até lá.',
                  style: small),
            ]),
          ),
          const SizedBox(height: 16),
          const NexoSectionTitle('Reservas e investimentos',
              subtitle: 'O que chega a tempo se pedir hoje'),
          const SizedBox(height: 8),
          if (options == null)
            const LinearProgressIndicator()
          else if (options.isEmpty)
            const Text('Nenhuma reserva ou investimento cadastrado.')
          else ...[
            for (final o in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    o.inTime ? Icons.check_circle_outline : Icons.schedule,
                    color: o.inTime
                        ? NexoTones.income(context)
                        : NexoTones.warning(context)),
                title: Text('${o.label} · ${money(o.amount)}'),
                subtitle: Text(o.availableOn == null
                    ? 'Prazo de resgate desconhecido: confira no banco.'
                    : o.inTime
                        ? o.kind == 'reserva'
                            ? 'Na hora: retire do objetivo para a conta.'
                            : 'Peça até ${fmt.format(o.sellBy!)}${o.kind == 'Renda fixa' ? ' (antes das 13h)' : ''}: chega até ${fmt.format(due)}.'
                        : 'Pedindo hoje, chega ${fmt.format(o.availableOn!)}: depois do vencimento.'),
              ),
            if (inTime != null)
              Text(
                  inTime >= s.missing
                      ? 'O que chega a tempo (${money(inTime)}) cobre a diferença.'
                      : 'O que chega a tempo soma ${money(inTime)}; ainda faltariam ${money(s.missing - inTime)}.',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            if (options.any((o) =>
                o.kind == 'Ações' || o.kind == 'FIIs' || o.kind == 'ETFs'))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Ações, FIIs e ETFs caem na conta em 2 dias úteis (D+2), sem contar fins de semana e feriados. Vendas de ações no mercado à vista de até R\$ 20 mil no mês têm lucro isento de IR pela regra vigente. Informação, não recomendação.',
                    style: small),
              ),
          ],
          if (s.event.kind == 'invoice') ...[
            const SizedBox(height: 16),
            const NexoSectionTitle('Pagamento parcial'),
            const SizedBox(height: 8),
            Text(card?.minimumPaymentCents != null
                ? 'O banco informa mínimo de ${money(card!.minimumPaymentCents! / 100)}. O restante vai para o rotativo ou parcelamento da fatura, com juros altos. Pagar o máximo possível reduz o custo.'
                : 'Pagar só parte da fatura joga o restante para o rotativo ou parcelamento, com juros altos. Pagar o máximo possível reduz o custo; confira o mínimo no app do banco.'),
          ],
          const SizedBox(height: 16),
          const NexoSectionTitle('Renda esperada'),
          const SizedBox(height: 8),
          Text(
              'Se você espera uma entrada antes do vencimento (um trabalho extra, um reembolso), cadastre como receita pendente com a data prevista: ela passa a contar na previsão.',
              style: TextStyle(color: cs.onSurface)),
        ],
      ),
    );
  }
}
