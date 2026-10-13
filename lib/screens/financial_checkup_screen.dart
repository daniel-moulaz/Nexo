import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../providers/app_provider.dart';
import '../services/file_output.dart';
import '../services/financial_checkup.dart';
import '../utils/finance_input.dart';

class FinancialCheckupScreen extends StatefulWidget {
  const FinancialCheckupScreen({super.key});
  @override
  State<FinancialCheckupScreen> createState() => _FinancialCheckupScreenState();
}

class _FinancialCheckupScreenState extends State<FinancialCheckupScreen> {
  int _days = 7;
  bool _names = false, _busy = false;
  String? _message;
  FinancialCheckup? _report;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _message = null;
      _report = null;
    });
    try {
      final payments =
          await (await DBHelper.database).query('card_invoice_payments');
      if (!mounted) return;
      final report = FinancialCheckup.build(context.read<AppProvider>(),
          now: DateTime.now(),
          days: _days,
          invoicePayments: payments,
          includeNames: _names);
      setState(() => _report = report);
    } catch (_) {
      if (mounted)
        setState(
            () => _message = 'Não foi possível ler os dados. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final report = _report;
    if (report == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final path = await FileOutput.save(
          title: 'Salvar revisão financeira',
          name:
              'nexo_revisao_${report.to.toIso8601String().substring(0, 10)}_${_days}dias.txt',
          extension: 'txt',
          bytes: Uint8List.fromList(utf8.encode(report.text)));
      if (mounted)
        setState(() => _message = path == null
            ? 'Exportação cancelada.'
            : 'Relatório salvo no local escolhido.');
    } catch (_) {
      if (mounted)
        setState(() => _message =
            'Não foi possível salvar. Escolha outro local e tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<AppProvider>().settings.hideBalance;
    return Scaffold(
      appBar: AppBar(title: const Text('Revisão financeira')),
      body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Passado, presente e próximos compromissos',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Gere um resumo dos dados deste dispositivo. Você pode salvar o arquivo e enviá-lo em uma conversa para pedir uma análise. Nada é enviado automaticamente.'),
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: [
                for (final d in [3, 7])
                  ChoiceChip(
                      label: Text('Últimos $d dias'),
                      selected: _days == d,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                                _days = d;
                                _report = null;
                                _message = null;
                              }))
              ]),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Incluir nomes'),
                  subtitle: const Text(
                      'Contas, categorias, contratos e objetivos. Valores e datas estarão no arquivo mesmo sem nomes.'),
                  value: _names,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                            _names = v;
                            _report = null;
                          })),
              if (hidden)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                        'Valores ocultos. Desative o modo privado para visualizar ou exportar esta revisão.')),
              FilledButton.icon(
                  onPressed: _busy || hidden ? null : _generate,
                  icon: const Icon(Icons.refresh),
                  label: Text(_busy ? 'Aguarde...' : 'Gerar revisão')),
              if (_message != null)
                Padding(
                    padding: const EdgeInsets.all(12), child: Text(_message!)),
              if (_report != null && !hidden) ...[
                const SizedBox(height: 16),
                Text(
                    '${ptDate(_report!.from)} a ${ptDate(_report!.to)} • fotografia do momento da geração'),
                const SizedBox(height: 8),
                for (final section in _report!.sections.entries)
                  Card(
                      child: ExpansionTile(
                          key: ValueKey(
                              '${_report!.generatedAt}-${section.key}'),
                          initiallyExpanded: section.key == 'O que aconteceu',
                          title: Text(section.key),
                          childrenPadding: const EdgeInsets.all(16),
                          children: [
                        Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                                section.value.map((s) => '• $s').join('\n\n')))
                      ])),
                const SizedBox(height: 12),
                const Text(
                    'O arquivo contém dados financeiros. Confira o conteúdo e escolha com quem compartilhar.'),
                OutlinedButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Salvar relatório .txt')),
              ],
            ]),
          )),
    );
  }
}
