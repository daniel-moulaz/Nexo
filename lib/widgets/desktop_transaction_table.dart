import 'package:flutter/material.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/finance_rules.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import '../screens/add_transaction_screen.dart';

class DesktopTransactionTable extends StatefulWidget {
  final AppProvider app;
  final List<AppTransaction> rows;
  const DesktopTransactionTable(
      {super.key, required this.app, required this.rows});
  @override
  State<DesktopTransactionTable> createState() =>
      _DesktopTransactionTableState();
}

class _DesktopTransactionTableState extends State<DesktopTransactionTable> {
  int column = 0, page = 0;
  bool ascending = false;
  final horizontal = ScrollController();
  static const pageSize = 20;
  @override
  void dispose() {
    horizontal.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DesktopTransactionTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rows.length != oldWidget.rows.length) page = 0;
  }

  String category(AppTransaction t) =>
      widget.app.categoryById(t.categoryId)?.name ?? 'Sem categoria';
  String account(AppTransaction t) =>
      widget.app.accountById(t.accountId)?.name ?? 'Conta indisponível';
  TransactionMetadata meta(AppTransaction t) =>
      widget.app.transactionMetadata[t.id] ??
      TransactionMetadata(transactionId: t.id);
  String type(AppTransaction t) => FinanceRules.isNeutral(t, meta(t))
      ? 'Movimentação'
      : t.type == 'income'
          ? 'Receita'
          : 'Despesa';
  String status(AppTransaction t) => meta(t).isPending
      ? 'Pendente'
      : t.type == 'income'
          ? 'Recebido'
          : 'Pago';
  int compare(AppTransaction a, AppTransaction b) => switch (column) {
        0 => a.date.compareTo(b.date),
        1 => a.description.toLowerCase().compareTo(b.description.toLowerCase()),
        2 => category(a).compareTo(category(b)),
        3 => account(a).compareTo(account(b)),
        4 => type(a).compareTo(type(b)),
        5 => status(a).compareTo(status(b)),
        _ => a.amount.compareTo(b.amount),
      };
  Future<void> edit(AppTransaction t, {bool repeat = false}) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => AddTransactionScreen(
              existing: repeat ? null : t,
              template: repeat ? t : null,
              initialType: t.type)));
  DataCell cell(String text, double width, VoidCallback action) => DataCell(
      SizedBox(
          width: width,
          child: Tooltip(
              message: text,
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis))),
      onTap: action);
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final rows = [...widget.rows]..sort((a, b) {
        final value = compare(a, b);
        return value == 0
            ? a.id.compareTo(b.id)
            : ascending
                ? value
                : -value;
      });
    final pages = (rows.length / pageSize).ceil().clamp(1, 1000000);
    page = page.clamp(0, pages - 1);
    return Column(children: [
      Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        Scrollbar(
            controller: horizontal,
            thumbVisibility: true,
            child: SingleChildScrollView(
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 14),
                child: DataTable(
                  sortColumnIndex: column,
                  sortAscending: ascending,
                  columnSpacing: 20,
                  horizontalMargin: 12,
                  showCheckboxColumn: false,
                  columns: [
                    for (final label in [
                      'Data',
                      'Descrição',
                      'Categoria',
                      'Conta / cartão',
                      'Tipo',
                      'Situação',
                      'Valor'
                    ])
                      DataColumn(
                          label: Text(label),
                          numeric: label == 'Valor',
                          onSort: (index, asc) => setState(() {
                                column = index;
                                ascending = asc;
                                page = 0;
                              })),
                    const DataColumn(label: Text('Ações')),
                  ],
                  rows: rows
                      .skip(page * pageSize)
                      .take(pageSize)
                      .map((t) => DataRow(cells: [
                            cell(ptDate(t.date), 82, () => edit(t)),
                            cell(t.description, 180, () => edit(t)),
                            cell(category(t), 110, () => edit(t)),
                            cell(account(t), 120, () => edit(t)),
                            cell(type(t), 100, () => edit(t)),
                            cell(status(t), 74, () => edit(t)),
                            cell(
                                app.settings.hideBalance
                                    ? '••••'
                                    : formatAmount(
                                        t.amount,
                                        t.currency.isNotEmpty
                                            ? t.currency
                                            : app
                                                    .accountById(t.accountId)
                                                    ?.currency ??
                                                app.settings.currency),
                                115,
                                () => edit(t)),
                            DataCell(PopupMenuButton<String>(
                                tooltip: 'Ações do lançamento',
                                onSelected: (action) =>
                                    edit(t, repeat: action == 'repeat'),
                                itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Abrir / editar')),
                                      if (!FinanceRules.isNeutral(t, meta(t)) &&
                                          meta(t).source == 'manual' &&
                                          meta(t).installmentTotal == null)
                                        const PopupMenuItem(
                                            value: 'repeat',
                                            child: Text('Repetir como novo…')),
                                    ])),
                          ]))
                      .toList(),
                ))),
      ])),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('Página ${page + 1} de $pages • até $pageSize por página'),
        IconButton(
            tooltip: 'Página anterior',
            onPressed: page > 0 ? () => setState(() => page--) : null,
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            tooltip: 'Próxima página',
            onPressed: page + 1 < pages ? () => setState(() => page++) : null,
            icon: const Icon(Icons.chevron_right)),
        const SizedBox(width: 12),
      ]),
    ]);
  }
}
