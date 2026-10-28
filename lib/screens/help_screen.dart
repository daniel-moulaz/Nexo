import 'package:flutter/material.dart';

import '../services/help_topics.dart';
import '../utils/finance_input.dart';
import '../services/diagnostics.dart';

/// Searchable answers about how the Nexo counts money and what each part
/// does. The search looks in the whole answer, not only in the question.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  @override
  void initState() {
    super.initState();
    Diagnostics.load();
  }

  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = searchHelp(_query);
    final groups = <String, List<HelpTopic>>{};
    for (final t in results) {
      (groups[t.group] ??= []).add(t);
    }
    return Scaffold(
      appBar: AppBar(
          title: const Text('Ajuda',
              style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Descreva o que aconteceu',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _query = '')),
            ),
          ),
          const SizedBox(height: 4),
          Text(
              '${helpTopics.length} respostas · a busca procura no texto inteiro',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: Text(
                      'Nada com essas palavras. Tente um termo só, como "fatura" ou "banco".')),
            ),
          for (final g in groups.entries) ...[
            Text(g.key,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final t in g.value)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                    initiallyExpanded: _query.isNotEmpty,
                    title: Text(t.question,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [Text(t.answer)]),
              ),
            const SizedBox(height: 12),
          ],
          if (_query.isEmpty) ...[
            Text('Diagnóstico',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            ValueListenableBuilder<int>(
                valueListenable: Diagnostics.revision,
                builder: (context, _, __) {
                  final entries = Diagnostics.entries;
                  if (entries.isEmpty) {
                    return Text(
                        'Nenhuma falha registrada. Erros de rede, de sincronização e do Open Finance aparecem aqui, sem valores.',
                        style: theme.textTheme.bodySmall);
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in entries)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.error_outline),
                              title: Text(
                                  '${e.area} · ${e.count}× · última ${ptShortDate(e.last)}'),
                              subtitle: Text(e.message)),
                        TextButton(
                            onPressed: Diagnostics.clear,
                            child: const Text('Limpar diagnóstico')),
                      ]);
                }),
          ],
        ],
      ),
    );
  }
}
