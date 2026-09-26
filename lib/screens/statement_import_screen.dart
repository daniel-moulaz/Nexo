import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';

class StatementImportScreen extends StatefulWidget {
  const StatementImportScreen({super.key});

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  List<_ImportedRow> _rows = [];
  String? _accountId;
  String? _fileName;
  bool _busy = false;
  String? _message;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;

    final content = utf8.decode(bytes, allowMalformed: true);
    final parsed = _parse(content);
    setState(() {
      _rows = parsed;
      _fileName = file.name;
      _message = parsed.isEmpty
          ? 'Não encontrei lançamentos reconhecíveis neste arquivo.'
          : '${parsed.length} lançamentos prontos para revisão.';
    });
  }

  List<_ImportedRow> _parse(String content) {
    final rawLines = const LineSplitter()
        .convert(content)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (rawLines.length < 2) return [];

    int headerIndex = -1;
    String separator = ',';
    List<String> headers = [];

    for (var i = 0; i < rawLines.length && i < 20; i++) {
      final line = rawLines[i];
      final sep = _detectSeparator(line);
      final parts = _splitCsv(line, sep)
          .map((e) => _normaliseHeader(e))
          .toList();
      final hasDate = parts.any(_isDateHeader);
      final hasDescription = parts.any(_isDescriptionHeader);
      final hasAmount = parts.any(_isAmountHeader);
      if (hasDate && hasDescription && hasAmount) {
        headerIndex = i;
        separator = sep;
        headers = parts;
        break;
      }
    }

    if (headerIndex < 0) return [];

    final dateCol = headers.indexWhere(_isDateHeader);
    final descCol = headers.indexWhere(_isDescriptionHeader);
    final amountCol = headers.indexWhere(_isAmountHeader);
    final typeCol = headers.indexWhere(
      (h) => ['tipo', 'type', 'natureza', 'transactiontype'].contains(h),
    );

    final rows = <_ImportedRow>[];
    for (var i = headerIndex + 1; i < rawLines.length; i++) {
      final cols = _splitCsv(rawLines[i], separator);
      if (cols.length <= [dateCol, descCol, amountCol].reduce((a, b) => a > b ? a : b)) {
        continue;
      }
      final date = _parseDate(cols[dateCol]);
      final amount = _parseAmount(cols[amountCol]);
      final description = cols[descCol].trim();
      if (date == null || amount == null || description.isEmpty || amount == 0) {
        continue;
      }

      final explicitType = typeCol >= 0 && typeCol < cols.length
          ? cols[typeCol].toLowerCase()
          : '';
      final looksIncome = explicitType.contains('receita') ||
          explicitType.contains('income') ||
          explicitType.contains('entrada') ||
          amount > 0 && _looksLikeIncome(description);
      final looksExpense = explicitType.contains('despesa') ||
          explicitType.contains('expense') ||
          explicitType.contains('saida') ||
          explicitType.contains('saída');
      final type = looksIncome && !looksExpense ? 'income' : 'expense';
      final absoluteAmount = amount.abs();
      final rule = _ruleFor(description, type);

      rows.add(
        _ImportedRow(
          date: date,
          description: description,
          amount: absoluteAmount,
          type: type,
          categoryId: rule.categoryId,
          subcategory: rule.subcategory,
          excludeFromSpending: rule.excludeFromSpending,
        ),
      );
    }
    return rows;
  }

  String _detectSeparator(String line) {
    final semi = ';'.allMatches(line).length;
    final comma = ','.allMatches(line).length;
    final tab = '\t'.allMatches(line).length;
    if (semi >= comma && semi >= tab) return ';';
    if (tab > comma) return '\t';
    return ',';
  }

  List<String> _splitCsv(String line, String separator) {
    final result = <String>[];
    final current = StringBuffer();
    bool quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == separator && !quoted) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  String _normaliseHeader(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áàâãéêíóôõúç]'), '')
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  bool _isDateHeader(String h) =>
      ['data', 'date', 'datatransacao', 'transactiondate'].contains(h);
  bool _isDescriptionHeader(String h) => [
        'descricao',
        'description',
        'titulo',
        'title',
        'detalhes',
        'details',
        'estabelecimento',
      ].contains(h);
  bool _isAmountHeader(String h) =>
      ['valor', 'amount', 'value', 'quantia', 'montante'].contains(h);

  DateTime? _parseDate(String raw) {
    final value = raw.trim();
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;
    for (final pattern in ['dd/MM/yyyy', 'dd-MM-yyyy', 'MM/dd/yyyy']) {
      try {
        return DateFormat(pattern).parseStrict(value);
      } catch (_) {}
    }
    return null;
  }

  double? _parseAmount(String raw) {
    var value = raw
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(' ', '')
        .trim();
    if (value.contains(',') && value.contains('.')) {
      if (value.lastIndexOf(',') > value.lastIndexOf('.')) {
        value = value.replaceAll('.', '').replaceAll(',', '.');
      } else {
        value = value.replaceAll(',', '');
      }
    } else if (value.contains(',')) {
      value = value.replaceAll(',', '.');
    }
    value = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(value);
  }

  bool _looksLikeIncome(String description) {
    final d = description.toLowerCase();
    return d.contains('recebido') ||
        d.contains('salario') ||
        d.contains('salário') ||
        d.contains('deposito') ||
        d.contains('depósito') ||
        d.contains('cashback') ||
        d.contains('estorno');
  }

  _ImportRule _ruleFor(String description, String type) {
    final d = description.toLowerCase();
    if (type == 'income') {
      if (d.contains('salario') || d.contains('salário')) {
        return const _ImportRule('salary', 'Salário');
      }
      return const _ImportRule('freelance', 'Outras entradas');
    }
    if (d.contains('ifood') || d.contains('restaurante') || d.contains('lanche')) {
      return const _ImportRule('food_exp', 'Delivery/Lanche');
    }
    if (d.contains('uber') || d.contains('99 ') || d.contains('posto') || d.contains('combust')) {
      return const _ImportRule('transport', 'Transporte');
    }
    if (d.contains('spotify') || d.contains('netflix') || d.contains('prime') || d.contains('youtube')) {
      return const _ImportRule('bills', 'Assinaturas');
    }
    if (d.contains('vivo') || d.contains('claro') || d.contains('tim ') || d.contains('internet')) {
      return const _ImportRule('bills', 'Telefone/Internet');
    }
    if (d.contains('luz') || d.contains('energia') || d.contains('agua') || d.contains('água')) {
      return const _ImportRule('bills', 'Contas da casa');
    }
    if (d.contains('farm') || d.contains('drogaria') || d.contains('consulta')) {
      return const _ImportRule('health', 'Saúde');
    }
    final neutral = d.contains('reserva') ||
        d.contains('transfer') ||
        d.contains('entre contas') ||
        d.contains('fatura') && d.contains('pagamento');
    return _ImportRule('other_exp', neutral ? 'Transferência/Reserva' : 'Outros',
        excludeFromSpending: neutral);
  }

  Future<void> _importRows() async {
    if (_accountId == null || _rows.isEmpty) return;
    final app = context.read<AppProvider>();
    setState(() {
      _busy = true;
      _message = null;
    });

    var imported = 0;
    for (final row in _rows.where((e) => e.selected)) {
      final fallbackCategory = app.categories
          .where((c) => c.type == row.type)
          .firstOrNull;
      var category = app.categoryById(row.categoryId);
      if (category == null || category.type != row.type) category = fallbackCategory;
      if (category == null) continue;

      final tx = AppTransaction(
        id: app.newId(),
        type: row.type,
        amount: row.amount,
        description: row.description,
        accountId: _accountId!,
        categoryId: category.id,
        date: row.date,
        currency: '',
        note: 'Importado de $_fileName',
      );
      await app.addTransaction(tx);
      if (row.type == 'expense') {
        await TransactionMetadataService.instance.save(
          TransactionMetadata(
            transactionId: tx.id,
            subcategory: row.subcategory,
            source: 'import',
            excludeFromSpending: row.excludeFromSpending,
          ),
        );
      }
      imported++;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = '$imported lançamentos importados com sucesso.';
      _rows = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final accounts = app.accounts.where((a) => !a.isGold).toList();
    _accountId ??= accounts.firstOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar extrato',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Mercado Pago, Nubank e CSV genérico',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'O importador tenta reconhecer data, descrição e valor, aplica categorias automáticas e marca transferências/reserva para não inflar seus gastos.',
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(
              labelText: 'Conta/cartão de destino',
              border: OutlineInputBorder(),
            ),
            items: accounts
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(_fileName == null ? 'Selecionar CSV' : _fileName!),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Prévia (${_rows.where((e) => e.selected).length} selecionados)',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ..._rows.take(80).map(
                  (row) => CheckboxListTile(
                    value: row.selected,
                    onChanged: (v) => setState(() => row.selected = v ?? true),
                    contentPadding: EdgeInsets.zero,
                    title: Text(row.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${DateFormat('dd/MM/yyyy').format(row.date)} • ${row.subcategory}${row.excludeFromSpending ? ' • não conta como gasto' : ''}',
                    ),
                    secondary: Text(
                      'R\$ ${row.amount.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: row.type == 'expense'
                            ? Theme.of(context).colorScheme.error
                            : Colors.green,
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _importRows,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_done_rounded),
              label: const Text('Importar selecionados'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportedRow {
  final DateTime date;
  final String description;
  final double amount;
  final String type;
  final String categoryId;
  final String subcategory;
  final bool excludeFromSpending;
  bool selected;

  _ImportedRow({
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.subcategory,
    required this.excludeFromSpending,
    this.selected = true,
  });
}

class _ImportRule {
  final String categoryId;
  final String subcategory;
  final bool excludeFromSpending;

  const _ImportRule(
    this.categoryId,
    this.subcategory, {
    this.excludeFromSpending = false,
  });
}
