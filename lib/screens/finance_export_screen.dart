import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/finance_export_service.dart';

class FinanceExportScreen extends StatefulWidget {
  const FinanceExportScreen({super.key});

  @override
  State<FinanceExportScreen> createState() => _FinanceExportScreenState();
}

class _FinanceExportScreenState extends State<FinanceExportScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  bool _busy = false;
  String? _message;

  Future<void> _pick(bool start) async {
    final initial = start ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final path = await FinanceExportService.exportWorkbook(
        context.read<AppProvider>(),
        from: _from,
        to: _to,
      );
      if (!mounted) return;
      setState(() => _message = path == null
          ? 'Exportação cancelada.'
          : 'Relatório salvo com sucesso.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Erro ao exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório financeiro',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Excel completo para análise',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'O arquivo inclui Resumo, Transações, Contas, Cartões e Orçamento. Também leva subcategoria, situação, vencimento e classificação do gasto.',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _DateBox(
                  label: 'De',
                  date: _from,
                  onTap: () => _pick(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateBox(
                  label: 'Até',
                  date: _to,
                  onTap: () => _pick(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_message != null) ...[
            Text(_message!, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_view_rounded),
            label: Text(_busy ? 'Gerando...' : 'Exportar .xlsx'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateBox({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              DateFormat('dd/MM/yyyy').format(date),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
