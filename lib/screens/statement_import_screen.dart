import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';
import '../services/ofx_parser.dart';
import '../utils/finance_input.dart';
import '../services/import_rules_service.dart';
import 'import_rules_screen.dart';

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
  bool _applyToBalance = false;
  String? _message;
  List<ImportRule> _customRules = [];

  Future<void> _pickFile() async {
    try {
      _customRules = await ImportRulesService.load();
    } catch (_) {
      if (mounted)
        setState(() =>
            _message = 'Não foi possível carregar as regras. Tente novamente.');
      return;
    }
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt', 'ofx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;

    final decoded = utf8.decode(bytes, allowMalformed: true);
    final content = decoded.contains('�') ? latin1.decode(bytes) : decoded;
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
    if (content.toUpperCase().contains('<OFX>')) {
      return parseOfx(content).map((entry) {
        final type = entry.amount > 0 ? 'income' : 'expense';
        final rule = _ruleFor(entry.description, type);
        return _ImportedRow(
            date: entry.date,
            description: entry.description,
            amount: entry.amount.abs(),
            type: type,
            categoryId: rule.categoryId,
            subcategory: rule.subcategory,
            excludeFromSpending: rule.excludeFromSpending);
      }).toList();
    }
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
      final parts = _splitCsv(line, sep).map(_normaliseHeader).toList();
      if (parts.any(_isDateHeader) &&
          parts.any(_isDescriptionHeader) &&
          parts.any(_isAmountHeader)) {
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

    final result = <_ImportedRow>[];
    for (var i = headerIndex + 1; i < rawLines.length; i++) {
      final cols = _splitCsv(rawLines[i], separator);
      final maxRequired =
          [dateCol, descCol, amountCol].reduce((a, b) => a > b ? a : b);
      if (cols.length <= maxRequired) continue;

      final date = _parseDate(cols[dateCol]);
      final amount = _parseAmount(cols[amountCol]);
      final description = cols[descCol].trim();
      if (date == null ||
          amount == null ||
          amount == 0 ||
          description.isEmpty) {
        continue;
      }

      final explicitType = typeCol >= 0 && typeCol < cols.length
          ? cols[typeCol].toLowerCase()
          : '';
      final looksIncome = explicitType.contains('receita') ||
          explicitType.contains('income') ||
          explicitType.contains('entrada') ||
          (amount > 0 &&
              (_looksLikeIncome(description) || !headers.contains('title')));
      final looksExpense = explicitType.contains('despesa') ||
          explicitType.contains('expense') ||
          explicitType.contains('saida') ||
          explicitType.contains('saída');
      final type = looksIncome && !looksExpense ? 'income' : 'expense';
      final absoluteAmount = amount.abs();
      final rule = _ruleFor(description, type);

      result.add(
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
    return result;
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

  bool _isDateHeader(String h) => [
        'data',
        'date',
        'datatransacao',
        'transactiondate',
        'releasedate',
        'datarelease'
      ].contains(h);
  bool _isDescriptionHeader(String h) => [
        'descricao',
        'description',
        'titulo',
        'title',
        'detalhes',
        'details',
        'estabelecimento',
        'transactiontype',
        'tipodetransacao',
      ].contains(h);
  bool _isAmountHeader(String h) => [
        'valor',
        'amount',
        'value',
        'quantia',
        'montante',
        'transactionnetamount',
        'netamount',
        'valorliquido'
      ].contains(h);

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

  double? _parseAmount(String raw) => parseMoney(raw);

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

  bool _looksNeutral(String d) {
    return d.contains('resgate de reserva') ||
        d.contains('aplicacao em reserva') ||
        d.contains('aplicação em reserva') ||
        d.contains('transferencia entre') ||
        d.contains('transferência entre') ||
        d.contains('entre contas') ||
        d.contains('pagamento da fatura') ||
        d.contains('pagamento de fatura') ||
        (d.contains('fatura') && d.contains('pagamento'));
  }

  _ImportRule _ruleFor(String description, String type) {
    final d = description.toLowerCase();
    final neutral = _looksNeutral(d);
    final custom = ImportRulesService.match(_customRules, description, type,
        context.read<AppProvider>().categories);
    if (custom != null)
      return _ImportRule(custom.categoryId, custom.subcategory,
          excludeFromSpending: neutral);
    if (neutral) {
      return _ImportRule(
        type == 'income' ? 'freelance' : 'other_exp',
        'Transferência/Reserva',
        excludeFromSpending: true,
      );
    }
    if (type == 'income') {
      if (d.contains('salario') || d.contains('salário')) {
        return const _ImportRule('salary', 'Salário');
      }
      return const _ImportRule('freelance', 'Outras entradas');
    }
    if (d.contains('ifood') ||
        d.contains('restaurante') ||
        d.contains('lanche')) {
      return const _ImportRule('food_exp', 'Delivery/Lanche');
    }
    if (d.contains('uber') ||
        d.contains('99 ') ||
        d.contains('posto') ||
        d.contains('combust')) {
      return const _ImportRule('transport', 'Transporte');
    }
    if (d.contains('spotify') ||
        d.contains('netflix') ||
        d.contains('prime') ||
        d.contains('youtube')) {
      return const _ImportRule('bills', 'Assinaturas');
    }
    if (d.contains('vivo') ||
        d.contains('claro') ||
        d.contains('tim ') ||
        d.contains('internet')) {
      return const _ImportRule('bills', 'Telefone/Internet');
    }
    if (d.contains('luz') ||
        d.contains('energia') ||
        d.contains('agua') ||
        d.contains('água')) {
      return const _ImportRule('bills', 'Contas da casa');
    }
    if (d.contains('farm') ||
        d.contains('drogaria') ||
        d.contains('consulta')) {
      return const _ImportRule('health', 'Saúde');
    }
    return const _ImportRule('other_exp', 'Outros');
  }

  Future<void> _importRows() async {
    if (_accountId == null || _rows.isEmpty) {
      setState(() => _message = 'Selecione a conta de destino e um arquivo.');
      return;
    }
    final app = context.read<AppProvider>();
    setState(() {
      _busy = true;
      _message = null;
    });

    var imported = 0;
    var skipped = 0;

    for (final row in _rows.where((e) => e.selected).toList()) {
      if (!mounted) return;

      final candidates = ImportRulesService.candidates(app.transactions,
          accountId: _accountId!,
          date: row.date,
          amount: row.amount,
          type: row.type);
      if (candidates.isNotEmpty) {
        final keep = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
                    title: const Text('Pode ser o mesmo lançamento'),
                    content: SingleChildScrollView(
                        child: Text(
                            'Arquivo: ${row.description}\n${DateFormat('dd/MM/yyyy').format(row.date)}\n\nJá registrados na mesma conta, com o mesmo valor e até 3 dias de diferença:\n${candidates.map((t) => '${DateFormat('dd/MM/yyyy').format(t.date)} • ${t.description}').join('\n')}\n\nIgnorar esta linha mantém os registros e saldos existentes. Se o registro está pendente, confirme o pagamento pela agenda.')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Ignorar esta linha')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('São diferentes: importar'))
                    ]));
        if (!mounted) return;
        if (keep == null) {
          setState(() {
            _busy = false;
            _message =
                'Importação interrompida. Os registros já salvos foram preservados.';
          });
          return;
        }
        if (!keep) {
          skipped++;
          row.selected = false;
          continue;
        }
      }

      final fallbackCategory =
          app.categories.where((c) => c.type == row.type).firstOrNull;
      var category = app.categoryById(row.categoryId);
      if (category == null || category.type != row.type) {
        category = fallbackCategory;
      }
      if (category == null) {
        setState(() { _busy = false; _message = 'Cadastre uma categoria de ${row.type == 'income' ? 'receita' : 'despesa'} antes de importar.'; });
        return;
      }

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

      try {
        await app.addTransaction(tx,
            metadata: TransactionMetadata(
                transactionId: tx.id,
                subcategory: row.subcategory,
                source: 'import',
                affectsBalance: _applyToBalance,
                excludeFromSpending: row.excludeFromSpending));
      } catch (_) {
        if (mounted)
          setState(() {
            _busy = false;
            _message =
                '$imported lançamentos salvos. Não foi possível concluir; tente novamente. Os registros já salvos foram desmarcados da prévia.';
          });
        return;
      }
      imported++;
      row.selected = false;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = skipped > 0
          ? '$imported importados • $skipped linhas ignoradas por sua escolha.'
          : '$imported lançamentos importados com sucesso.';
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
            'Mercado Pago, Nubank, CSV e OFX',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Reconhece data, descrição e valor, tenta categorizar automaticamente e separa transferências/reserva dos gastos reais.',
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ImportRulesScreen())),
              icon: const Icon(Icons.rule),
              label: const Text('Regras de categorização')),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _accountId,
            decoration: const InputDecoration(
              labelText: 'Conta/cartão de destino',
              border: OutlineInputBorder(),
            ),
            items: accounts
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: _busy ? null : (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _applyToBalance,
            onChanged: _busy
                ? null
                : (value) => setState(() => _applyToBalance = value),
            title: const Text('Ajustar saldo da conta com a importação'),
            subtitle: const Text(
              'Desligado por padrão. Para extratos históricos, os lançamentos entram sem alterar o saldo atual.',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(
                _fileName == null ? 'Selecionar CSV, TXT ou OFX' : _fileName!),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Prévia (${_rows.where((e) => e.selected).length} selecionados)',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ..._rows.map(
              (row) => CheckboxListTile(
                value: row.selected,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => row.selected = v ?? true),
                contentPadding: EdgeInsets.zero,
                title: Text(row.description,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${DateFormat('dd/MM/yyyy').format(row.date)} • ${row.subcategory}${row.excludeFromSpending ? ' • neutro' : ''}',
                ),
                secondary: PopupMenuButton<String>(
                  tooltip: 'Corrigir tipo do lançamento',
                  onSelected: (value) => setState(() {
                    row.excludeFromSpending = value == 'transfer';
                    if (value != 'transfer') row.type = value;
                  }),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'expense', child: Text('Despesa')),
                    PopupMenuItem(value: 'income', child: Text('Receita')),
                    PopupMenuItem(
                        value: 'transfer',
                        child: Text('Movimento entre minhas contas'))
                  ],
                  child: Text(
                      '${row.type == 'income' ? '+' : '-'} R\$ ${row.amount.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: row.type == 'expense'
                              ? Theme.of(context).colorScheme.error
                              : Colors.green)),
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
  String type;
  final String categoryId;
  final String subcategory;
  bool excludeFromSpending;
  bool selected = true;

  _ImportedRow({
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.subcategory,
    required this.excludeFromSpending,
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
