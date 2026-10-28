import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

/// The cards of Hoje a person can reorder or hide. The month bar, the four
/// numbers, "quanto posso gastar" and the quick actions always stay.
const kHomeSections = <String, String>{
  'daily': 'Saídas por dia',
  'month': 'Resumo do mês',
  'week': 'Sua semana',
  'categories': 'Para onde foi',
  'netWorth': 'Patrimônio',
  'future': 'O que vem pela frente',
  'budget': 'Orçamento',
  'cards': 'Cartões e compromissos',
};

/// Saved order and visibility; an empty setting means the default order.
List<String> homeSectionOrder(List<String> saved) {
  final known = saved.where(kHomeSections.containsKey).toList();
  return saved.isEmpty ? kHomeSections.keys.toList() : known;
}

Future<void> showHomeCustomizeSheet(BuildContext context) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const _HomeCustomizeSheet());

class _HomeCustomizeSheet extends StatefulWidget {
  const _HomeCustomizeSheet();
  @override
  State<_HomeCustomizeSheet> createState() => _HomeCustomizeSheetState();
}

class _HomeCustomizeSheetState extends State<_HomeCustomizeSheet> {
  late List<String> _order;
  late Set<String> _visible;

  @override
  void initState() {
    super.initState();
    final saved = context.read<AppProvider>().settings.homeCards;
    final visible = homeSectionOrder(saved);
    _visible = visible.toSet();
    _order = [
      ...visible,
      ...kHomeSections.keys.where((k) => !visible.contains(k)),
    ];
  }

  void _save() {
    final list = [
      for (final k in _order)
        if (_visible.contains(k)) k
    ];
    // Hiding everything is a mistake, not a wish: keep the default then.
    context.read<AppProvider>().updateSetting(
        'homeCards', list.isEmpty ? kHomeSections.keys.toList() : list);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            Expanded(
                child: Text('Personalizar o Hoje',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900))),
            TextButton(
                onPressed: () => setState(() {
                      _order = kHomeSections.keys.toList();
                      _visible = kHomeSections.keys.toSet();
                      _save();
                    }),
                child: const Text('Padrão')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
              'Arraste para ordenar; desligue o que não quer ver. Os quatro números e "quanto posso gastar" ficam sempre.',
              style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            onReorderItem: (from, to) => setState(() {
              final key = _order.removeAt(from);
              _order.insert(to, key);
              _save();
            }),
            children: [
              for (final key in _order)
                SwitchListTile(
                    key: ValueKey(key),
                    title: Text(kHomeSections[key]!),
                    secondary: const Icon(Icons.drag_handle),
                    value: _visible.contains(key),
                    onChanged: (on) => setState(() {
                          on ? _visible.add(key) : _visible.remove(key);
                          _save();
                        })),
            ],
          ),
        ),
      ]),
    );
  }
}
