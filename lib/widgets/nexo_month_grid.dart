import 'package:flutter/material.dart';
import '../widgets/nexo_ui.dart';

/// What a day of the month carries: money in, money out, how many items.
class DayLoad {
  const DayLoad({this.income = 0, this.expense = 0, this.count = 0});
  final double income, expense;
  final int count;
  DayLoad add(double signed) => DayLoad(
      income: income + (signed > 0 ? signed : 0),
      expense: expense + (signed < 0 ? -signed : 0),
      count: count + 1);
}

/// A month as a 7-column grid: every day shows its outflow (and inflow when
/// any), today is ringed, the selected day is filled. Tapping a day tells
/// the parent; the parent decides what list to show. No scrolling inside.
class NexoMonthGrid extends StatelessWidget {
  const NexoMonthGrid(
      {super.key,
      required this.month,
      required this.loads,
      required this.money,
      required this.onDay,
      this.selected,
      this.today,
      this.hidden = false});
  final DateTime month;
  final Map<DateTime, DayLoad> loads;
  final String Function(double) money;
  final ValueChanged<DateTime> onDay;
  final DateTime? selected, today;
  final bool hidden;

  static DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday first
    final cells = <Widget>[];
    const names = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
    for (final n in names) {
      cells.add(Center(
          child: Text(n,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant))));
    }
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    final todayKey = today == null ? null : dayKey(today!);
    final selectedKey = selected == null ? null : dayKey(selected!);
    for (var d = 1; d <= days; d++) {
      final date = DateTime(month.year, month.month, d);
      final load = loads[date] ?? const DayLoad();
      final isToday = todayKey == date;
      final isSelected = selectedKey == date;
      final busy = load.count > 0;
      cells.add(Semantics(
        label:
            '${date.day}/${date.month}${busy ? ': sai ${money(load.expense)}${load.income > 0 ? ', entra ${money(load.income)}' : ''}' : ''}',
        button: true,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onDay(date),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primaryContainer
                  : busy
                      ? cs.surfaceContainerHigh
                      : null,
              borderRadius: BorderRadius.circular(10),
              border:
                  isToday ? Border.all(color: cs.primary, width: 1.5) : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$d',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday || isSelected
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color:
                          isSelected ? cs.onPrimaryContainer : cs.onSurface)),
              if (busy && !hidden) ...[
                if (load.expense > 0)
                  FittedBox(
                      child: Text('−${_short(load.expense)}',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: NexoTones.expense(context),
                              fontFeatures: NexoTones.figures))),
                if (load.income > 0)
                  FittedBox(
                      child: Text('+${_short(load.income)}',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: NexoTones.income(context),
                              fontFeatures: NexoTones.figures))),
              ] else if (busy)
                Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: cs.onSurfaceVariant, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ));
    }
    return GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: .78,
        children: cells);
  }

  /// 1.650,00 → "1,6k", 99,90 → "100", 7,50 → "7,50".
  static String _short(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1).replaceAll('.', ',')}k';
    }
    if (v >= 100) return v.round().toString();
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }
}
