import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/import_rules_service.dart';

class ImportRulesScreen extends StatefulWidget {
  const ImportRulesScreen({super.key});
  @override
  State<ImportRulesScreen> createState() => _ImportRulesScreenState();
}

class _ImportRulesScreenState extends State<ImportRulesScreen> {
  late Future<List<ImportRule>> _rules = ImportRulesService.load();
  Future<void> _edit([ImportRule? rule]) async {
    final app = context.read<AppProvider>();
    final pattern = TextEditingController(text: rule?.pattern);
    final sub = TextEditingController(text: rule?.subcategory);
    var type = rule?.type ?? 'expense';
    String? category = rule?.categoryId;
    String? error;
    bool busy = false;
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
              final cats = app.categories.where((c) => c.type == type).toList();
              if (!cats.any((c) => c.id == category)) category = null;
              return AlertDialog(
                  title: Text(rule == null ? 'Nova regra' : 'Editar regra'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: pattern,
                        decoration: const InputDecoration(
                            labelText: 'Descrição contém',
                            hintText: 'Ex.: UBER')),
                    DropdownButtonFormField<String>(
                        initialValue: type,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                              value: 'expense', child: Text('Despesa')),
                          DropdownMenuItem(
                              value: 'income', child: Text('Receita'))
                        ],
                        onChanged: busy
                            ? null
                            : (v) => update(() {
                                  type = v!;
                                  category = null;
                                })),
                    DropdownButtonFormField<String>(
                        key: ValueKey('$type:$category'),
                        initialValue: category,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Categoria'),
                        items: cats
                            .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged:
                            busy ? null : (v) => update(() => category = v)),
                    TextField(
                        controller: sub,
                        decoration: const InputDecoration(
                            labelText: 'Subcategoria (opcional)')),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: busy ? null : () => Navigator.pop(ctx),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (pattern.text.trim().isEmpty ||
                                    category == null) {
                                  update(() => error =
                                      'Preencha a descrição e a categoria.');
                                  return;
                                }
                                update(() => busy = true);
                                try {
                                  await ImportRulesService.save(ImportRule(
                                      id: rule?.id ?? app.newId(),
                                      pattern: pattern.text,
                                      type: type,
                                      categoryId: category!,
                                      subcategory: sub.text));
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (_) {
                                  if (ctx.mounted)
                                    update(() {
                                      busy = false;
                                      error =
                                          'Não foi possível salvar. Revise a categoria e tente novamente.';
                                    });
                                }
                              },
                        child: const Text('Salvar'))
                  ]);
            }));
    pattern.dispose();
    sub.dispose();
    if (mounted)
      setState(() {
        _rules = ImportRulesService.load();
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Regras de categoria')),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(),
          tooltip: 'Nova regra',
          child: const Icon(Icons.add)),
      body: FutureBuilder<List<ImportRule>>(
          future: _rules,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return const Center(
                  child: Text('Não foi possível carregar as regras.'));
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  const Text(
                      'Sugerem categorias na revisão de notificações e importações. O texto mais específico tem prioridade. Não alteram lançamentos antigos nem o saldo.'),
                  Wrap(spacing: 8, children: [
                    for (final example in const [
                      ('IFOOD', 'Delivery'),
                      ('UBER', 'Transporte por app'),
                      ('NETFLIX', 'Streaming'),
                      ('POSTO', 'Combustível')
                    ])
                      ActionChip(
                          label: Text('Exemplo: ${example.$1}'),
                          onPressed: () => _edit(ImportRule(
                              id: context.read<AppProvider>().newId(),
                              pattern: example.$1,
                              type: 'expense',
                              categoryId: '',
                              subcategory: example.$2))),
                  ]),
                  if (snapshot.data!.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Crie sua primeira regra, por exemplo: UBER → Transporte.')),
                  for (final r in snapshot.data!)
                    ListTile(
                        title: Text(r.pattern),
                        subtitle: Text(
                            '${context.read<AppProvider>().categoryById(r.categoryId)?.name ?? 'Categoria removida'} • ${r.subcategory}'),
                        onTap: () => _edit(r),
                        trailing: IconButton(
                            tooltip: 'Excluir regra',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                          title: const Text('Excluir regra?'),
                                          content: Text(r.pattern),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancelar')),
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('Excluir'))
                                          ]));
                              if (confirmed != true) return;
                              try {
                                await ImportRulesService.delete(r.id);
                                if (mounted)
                                  setState(() {
                                    _rules = ImportRulesService.load();
                                  });
                              } catch (_) {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Não foi possível excluir a regra.')));
                              }
                            }))
                ]);
          }));
}
