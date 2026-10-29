import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../sync/assistant_commands.dart';
import '../utils/snackbar.dart';
import '../widgets/shared_widgets.dart';

/// Plain words for each request kind, for the list below.
const assistantKindLabels = <String, String>{
  'transaction.add': 'Lançamento',
  'transfer.add': 'Transferência',
  'transaction.update': 'Correção de lançamento',
  'transaction.edit': 'Edição de lançamento',
  'transaction.delete': 'Exclusão de lançamento',
  'transaction.settle': 'Marcado como pago',
  'transaction.bulk_update': 'Lançamentos alterados em lote',
  'transaction.bulk_delete': 'Lançamentos apagados em lote',
  'transaction.neutralize': 'Convertido em ajuste de saldo',
  'transaction.split': 'Dividido em parcelas',
  'suggestion.confirm': 'Sugestão do banco confirmada',
  'suggestion.accept': 'Sugestão do banco confirmada',
  'suggestion.transfer': 'Sugestão do banco como transferência',
  'recurring.pay': 'Recorrente efetivada',
  'recurring.skip': 'Recorrente pulada',
  'recurring.add': 'Nova recorrente',
  'recurring.update': 'Recorrente alterada',
  'recurring.edit': 'Recorrente alterada',
  'recurring.delete': 'Recorrente excluída',
  'budget.set': 'Orçamento',
  'budget.save': 'Orçamento',
  'budget.delete': 'Orçamento removido',
  'category.add': 'Nova categoria',
  'category.update': 'Categoria renomeada',
  'category.edit': 'Categoria alterada',
  'category.envelope': 'Tipo de gasto das categorias',
  'category.merge': 'Categorias juntadas',
  'category.delete': 'Categoria excluída',
  'settings.set': 'Configuração',
  'goal.move': 'Objetivo: guardar ou retirar',
  'goal.adjust': 'Objetivo ajustado sem mexer em conta',
  'goal.add': 'Novo objetivo',
  'goal.update': 'Objetivo alterado',
  'goal.edit': 'Objetivo alterado',
  'goal.delete': 'Objetivo excluído',
  'invoice.pay': 'Fatura paga',
  'account.add': 'Nova conta',
  'account.update': 'Conta alterada',
  'account.edit': 'Conta alterada',
  'account.adjust': 'Saldo ajustado',
  'account.delete': 'Conta excluída',
  'investment.add': 'Novo investimento',
  'investment.operation': 'Operação de investimento',
  'investment.price': 'Preço de investimento',
  'investment.archive': 'Investimento retirado da carteira',
  'investment.unrecord': 'Operação de investimento apagada',
  'investment.link': 'Operação vinculada a conta',
  'loan.add': 'Novo empréstimo',
  'loan.edit': 'Empréstimo alterado',
  'loan.delete': 'Empréstimo excluído',
  'loan.pay': 'Parcela paga',
  'loan.skip': 'Parcela pulada',
  'loan.unpay': 'Pagamento de parcela apagado',
  'lended.add': 'Emprestado / devido',
  'lended.edit': 'Empréstimo pessoal alterado',
  'lended.delete': 'Empréstimo pessoal excluído',
  'lended.settle': 'Empréstimo pessoal quitado',
  'person.edit': 'Pessoa alterada',
  'person.delete': 'Pessoa excluída',
  'asset.add': 'Novo bem',
  'asset.update': 'Bem alterado',
  'asset.delete': 'Bem excluído',
  'wishlist.add': 'Novo desejo',
  'wishlist.update': 'Desejo alterado',
  'wishlist.delete': 'Desejo removido',
  'rule.save': 'Regra de categoria',
  'rule.delete': 'Regra de categoria excluída',
  'bank.refresh': 'Leitura dos bancos',
  'request.undo': 'Pedido desfeito',
};

/// "Feito pelo Claude": every request of the assistant, when it was made,
/// what happened and, while nothing changed since, a way to undo it.
class AssistantHistoryScreen extends StatefulWidget {
  const AssistantHistoryScreen(
      {super.key, required this.assistant, required this.datasetId});
  final AssistantCommands assistant;
  final String datasetId;

  @override
  State<AssistantHistoryScreen> createState() => _AssistantHistoryScreenState();
}

class _AssistantHistoryScreenState extends State<AssistantHistoryScreen> {
  late Future<List<AssistantHistoryItem>> _items = _load();
  bool _busy = false;

  Future<List<AssistantHistoryItem>> _load() =>
      widget.assistant.remote.history(widget.datasetId);

  Future<void> _undo(AssistantHistoryItem item) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Desfazer este pedido?'),
              content: Text(
                  '${assistantKindLabels[item.kind] ?? item.kind}: ${item.message ?? ''}\n\nO Nexo volta ao que era antes, inclusive os saldos. Se algo mudou depois, nada é desfeito.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Desfazer')),
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await widget.assistant.undoFromApp(item.id);
      if (mounted) showAppSnackbar(context, message);
    } on StateError catch (e) {
      if (mounted) showAppSnackbar(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppSnackbar(context, 'Não foi possível desfazer agora.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _items = _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Feito pelo Claude')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _items = _load());
          await _items;
        },
        child: FutureBuilder<List<AssistantHistoryItem>>(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(children: const [
                SizedBox(height: 120),
                EmptyState(
                    icon: Icons.cloud_off_outlined,
                    message: 'Não foi possível carregar a lista.',
                    subMessage: 'Confira a conexão e puxe para atualizar.'),
              ]);
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                EmptyState(
                    icon: Icons.smart_toy_outlined,
                    message: 'O Claude ainda não fez nenhum pedido.'),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = items[i];
                final when =
                    DateFormat('dd/MM HH:mm', 'pt_BR').format(item.createdAt);
                final state = switch (item.status) {
                  _ when item.undoneAt != null => 'desfeito',
                  'done' => 'gravado',
                  'rejected' => 'recusado',
                  'applying' => 'gravando',
                  _ => 'esperando o app',
                };
                final detail =
                    item.status == 'rejected' ? item.reason : item.message;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  title: Text(assistantKindLabels[item.kind] ?? item.kind),
                  subtitle: Text(
                      [
                        '$when · $state',
                        if (detail != null && detail.isNotEmpty) detail,
                      ].join('\n'),
                      style: theme.textTheme.bodySmall),
                  trailing: item.undoable
                      ? TextButton(
                          onPressed: _busy ? null : () => _undo(item),
                          child: const Text('Desfazer'))
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
