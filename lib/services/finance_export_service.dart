import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import 'finance_rules.dart';
import 'transaction_metadata_service.dart';

class FinanceExportService {
  static Future<String?> exportWorkbook(
    AppProvider app, {
    required DateTime from,
    required DateTime to,
  }) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    final txs = app.transactions
        .where((t) => !t.date.isBefore(start) && !t.date.isAfter(end))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final metadata = await TransactionMetadataService.instance
        .getForMany(txs.map((e) => e.id));

    final excel = Excel.createExcel();
    try {
      excel.delete('Sheet1');
    } catch (_) {}

    _buildSummary(excel['Resumo'], app, txs, metadata, start, end);
    _buildTransactions(excel['Transações'], app, txs, metadata);
    _buildAccounts(excel['Contas'], app);
    _buildCards(excel['Cartões'], app, txs, metadata);
    _buildBudgets(excel['Orçamento'], app);

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Não foi possível gerar o Excel.');

    final fileName =
        'meu_fluxo_${DateFormat('yyyy-MM-dd').format(start)}_a_${DateFormat('yyyy-MM-dd').format(end)}.xlsx';

    return FilePicker.platform.saveFile(
      dialogTitle: 'Salvar relatório financeiro',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
  }

  static void _header(Sheet sheet, List<String> labels) {
    for (var i = 0; i < labels.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(labels[i]);
      cell.cellStyle = CellStyle(bold: true);
    }
  }

  static String _currencyFor(AppProvider app, AppTransaction tx) {
    if (tx.currency.isNotEmpty) return tx.currency;
    return app.accountById(tx.accountId)?.currency ?? app.settings.currency;
  }

  static double _mainAmount(AppProvider app, AppTransaction tx) {
    return app.convertToMain(tx.amount, _currencyFor(app, tx));
  }

  static void _buildSummary(
    Sheet sheet,
    AppProvider app,
    List<AppTransaction> txs,
    Map<String, TransactionMetadata> metadata,
    DateTime from,
    DateTime to,
  ) {
    _header(sheet, const ['Indicador', 'Valor']);

    double income = 0;
    double paid = 0;
    double pending = 0;
    double extraordinary = 0;
    double neutralMovements = 0;

    for (final tx in txs) {
      final amount = _mainAmount(app, tx);
      final meta = metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      if (FinanceRules.isNeutral(tx, meta)) {
        neutralMovements += amount;
        continue;
      }
      if (tx.type == 'income') {
        income += amount;
        continue;
      }
      if (meta.status == 'pending') {
        pending += amount;
      } else {
        paid += amount;
      }
      if (meta.expenseClass == 'extraordinary') extraordinary += amount;
    }

    final rows = <List<String>>[
      ['Período', '${DateFormat('dd/MM/yyyy').format(from)} a ${DateFormat('dd/MM/yyyy').format(to)}'],
      ['Moeda principal', app.settings.currency],
      ['Receitas reais', income.toStringAsFixed(2)],
      ['Despesas pagas', paid.toStringAsFixed(2)],
      ['Despesas pendentes', pending.toStringAsFixed(2)],
      ['Despesas extraordinárias', extraordinary.toStringAsFixed(2)],
      ['Movimentos neutros (transferência/reserva)', neutralMovements.toStringAsFixed(2)],
      ['Saldo do período (receitas - pagas)', (income - paid).toStringAsFixed(2)],
      ['Comprometido (pagas + pendentes)', (paid + pending).toStringAsFixed(2)],
    ];

    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = TextCellValue(rows[r][c]);
      }
    }
  }

  static void _buildTransactions(
    Sheet sheet,
    AppProvider app,
    List<AppTransaction> txs,
    Map<String, TransactionMetadata> metadata,
  ) {
    const headers = [
      'Data',
      'Descrição',
      'Tipo',
      'Valor',
      'Moeda',
      'Conta',
      'Categoria',
      'Subcategoria',
      'Situação',
      'Vencimento',
      'Classe',
      'Conta como gasto?',
      'Parcela',
      'Origem',
      'Observação',
    ];
    _header(sheet, headers);

    for (var i = 0; i < txs.length; i++) {
      final tx = txs[i];
      final meta = metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      final neutral = FinanceRules.isNeutral(tx, meta);
      final status = meta.isOverdue
          ? 'Atrasado'
          : (meta.status == 'pending' ? 'Pendente' : 'Pago');
      final values = [
        DateFormat('dd/MM/yyyy').format(tx.date),
        tx.description,
        tx.type == 'income' ? 'Receita' : 'Despesa',
        tx.amount.toStringAsFixed(2),
        _currencyFor(app, tx),
        app.accountById(tx.accountId)?.name ?? '',
        app.categoryById(tx.categoryId)?.name ?? '',
        meta.subcategory,
        tx.type == 'income' ? 'Recebido' : status,
        meta.dueDate == null ? '' : DateFormat('dd/MM/yyyy').format(meta.dueDate!),
        meta.expenseClass == 'extraordinary' ? 'Extraordinária' : 'Normal',
        neutral ? 'Não' : 'Sim',
        meta.installmentLabel,
        meta.source,
        tx.note,
      ];
      for (var c = 0; c < values.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1))
            .value = TextCellValue(values[c]);
      }
    }
  }

  static void _buildAccounts(Sheet sheet, AppProvider app) {
    _header(sheet, const ['Conta', 'Tipo', 'Saldo', 'Moeda', 'Incluir no total']);
    for (var i = 0; i < app.accounts.length; i++) {
      final a = app.accounts[i];
      final values = [
        a.name,
        a.type,
        a.balance.toStringAsFixed(2),
        a.currency,
        a.excludeFromTotal ? 'Não' : 'Sim',
      ];
      for (var c = 0; c < values.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1))
            .value = TextCellValue(values[c]);
      }
    }
  }

  static void _buildCards(
    Sheet sheet,
    AppProvider app,
    List<AppTransaction> txs,
    Map<String, TransactionMetadata> metadata,
  ) {
    _header(sheet, const [
      'Cartão',
      'Fechamento',
      'Vencimento',
      'Limite',
      'Compras no período',
      'Moeda',
    ]);
    final cards = app.accounts.where((a) => a.type == 'credit').toList();
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      final total = txs
          .where((t) =>
              t.type == 'expense' &&
              t.accountId == card.id &&
              !FinanceRules.isNeutral(t, metadata[t.id]))
          .fold<double>(0, (sum, t) => sum + t.amount);
      final values = [
        card.name,
        card.statementDay?.toString() ?? '',
        card.dueDay?.toString() ?? '',
        card.creditLimit?.toStringAsFixed(2) ?? '',
        total.toStringAsFixed(2),
        card.currency,
      ];
      for (var c = 0; c < values.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1))
            .value = TextCellValue(values[c]);
      }
    }
  }

  static void _buildBudgets(Sheet sheet, AppProvider app) {
    _header(sheet, const ['Categoria', 'Limite', 'Gasto', 'Restante', 'Período']);
    for (var i = 0; i < app.budgets.length; i++) {
      final budget = app.budgets[i];
      final spent = app.budgetSpent(budget);
      final values = [
        app.categoryById(budget.categoryId)?.name ?? '',
        budget.amount.toStringAsFixed(2),
        spent.toStringAsFixed(2),
        (budget.amount - spent).toStringAsFixed(2),
        budget.period == 'weekly' ? 'Semanal' : 'Mensal',
      ];
      for (var c = 0; c < values.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1))
            .value = TextCellValue(values[c]);
      }
    }
  }
}
