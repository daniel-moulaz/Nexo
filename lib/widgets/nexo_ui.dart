import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Semantic money colors that read well on dark and light surfaces.
abstract final class NexoTones {
  static Color income(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF34D399)
          : const Color(0xFF047857);
  static Color expense(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFB7185)
          : const Color(0xFFBE123C);
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFBBF24)
          : const Color(0xFFB45309);

  /// Numbers line up in columns and read as figures, not prose.
  static const figures = [FontFeature.tabularFigures()];
}

/// Rounded surface used by every home section.
class NexoCard extends StatelessWidget {
  const NexoCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.gradient,
      this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Flat: a hairline border does the separating, not a tinted fill.
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: gradient == null
            ? BorderSide(color: cs.outlineVariant.withValues(alpha: .6))
            : BorderSide.none);
    final content = Padding(padding: padding, child: child);
    // A Material surface keeps ink splashes of lists and buttons visible.
    if (gradient == null) {
      return Material(
          color: color ?? cs.surfaceContainerLow,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: content);
    }
    return Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child:
            Ink(decoration: BoxDecoration(gradient: gradient), child: content));
  }
}

/// Section title with an optional action ("Ver tudo").
class NexoSectionTitle extends StatelessWidget {
  const NexoSectionTitle(this.title,
      {super.key, this.subtitle, this.action, this.onAction, this.icon});
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      if (icon != null) ...[
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (subtitle != null)
            Text(subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ]);
  }
}

/// Compact label + value capsule (like "Inicial · Saldo · Previsto").
class NexoStatPill extends StatelessWidget {
  const NexoStatPill(
      {super.key,
      required this.label,
      required this.value,
      this.icon,
      this.valueColor,
      this.onTap,
      this.onDark = false});
  final String label, value;
  final IconData? icon;
  final Color? valueColor;
  final VoidCallback? onTap;

  /// Placed over a colored gradient: use translucent white.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = onDark ? Colors.white : cs.onSurface;
    return Material(
      color: onDark
          ? Colors.white.withValues(alpha: .14)
          : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg.withValues(alpha: .8)),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        color: fg.withValues(alpha: .8))),
              ),
            ]),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: valueColor ?? fg,
                      fontFeatures: NexoTones.figures)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Round shortcut (Pix-style row of banking apps).
class NexoQuickAction extends StatelessWidget {
  const NexoQuickAction(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap,
      this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: primary ? cs.primary : cs.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: primary ? cs.onPrimary : cs.onSurface, size: 24),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Half-ring gauge: share of income kept this month.
class NexoSavingsGauge extends StatelessWidget {
  const NexoSavingsGauge(
      {super.key, required this.ratio, required this.label, this.size = 132});

  /// 0..1 saved; null when there is no income to compare.
  final double? ratio;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = ratio;
    final color = r == null
        ? cs.outline
        : r < 0
            ? NexoTones.expense(context)
            : r < .1
                ? NexoTones.warning(context)
                : NexoTones.income(context);
    final percent = r == null ? '—' : '${(r * 100).round().clamp(-999, 100)}%';
    return Semantics(
      label: r == null
          ? 'Economia do mês indisponível: sem receitas.'
          : 'Economia do mês: $percent das receitas.',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size * .78,
          child: CustomPaint(
            painter: _GaugePainter(
                value: (r ?? 0).clamp(0, 1).toDouble(),
                track: cs.surfaceContainerHighest,
                color: color),
            child: Padding(
              padding: EdgeInsets.only(top: size * .2),
              // Shrinks with large text instead of overflowing the ring.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(percent,
                      style: TextStyle(
                          fontSize: size * .22,
                          fontWeight: FontWeight.w900,
                          fontFeatures: NexoTones.figures)),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(
      {required this.value, required this.track, required this.color});
  final double value;
  final Color track, color;

  @override
  void paint(Canvas canvas, Size size) {
    const start = math.pi * .8, sweep = math.pi * 1.4;
    final stroke = size.width * .085;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.width / 2),
        radius: size.width / 2 - stroke / 2);
    Paint paint(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, paint(track));
    if (value > 0)
      canvas.drawArc(rect, start, sweep * value, false, paint(color));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Cumulative spending this month against the previous month, day by day:
/// "am I spending faster than usual?".
class NexoSpendingPace extends StatelessWidget {
  const NexoSpendingPace(
      {super.key,
      required this.current,
      required this.previous,
      required this.money,
      this.ideal,
      this.monthDays});

  /// Cumulative totals indexed by day-1 (current stops at today).
  final List<double> current, previous;
  final String Function(double) money;

  /// Month total that keeps the plan; drawn as a dotted straight line.
  final double? ideal;
  final int? monthDays;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days =
        math.max(math.max(previous.length, current.length), monthDays ?? 0);
    final top =
        [...current, ...previous, ideal ?? 0, 1.0].reduce(math.max) * 1.12;
    final now = current.isEmpty ? 0.0 : current.last;
    final then = previous.isEmpty
        ? null
        : previous[math.min(current.length, previous.length) - 1];
    final ahead = then != null && now > then;
    final color = ahead ? NexoTones.expense(context) : cs.primary;
    List<FlSpot> spots(List<double> v) =>
        [for (var i = 0; i < v.length; i++) FlSpot(i + 1.0, v[i])];
    return Semantics(
      label: 'Gasto acumulado no mês: ${money(now)}'
          '${then == null ? '' : '. No mesmo dia do mês anterior: ${money(then)}'}.',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 120,
          child: LineChart(LineChartData(
            minX: 1,
            maxX: math.max(days, 2).toDouble(),
            minY: 0,
            maxY: top,
            clipData: const FlClipData.all(),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              if (ideal != null && monthDays != null)
                LineChartBarData(
                  spots: [
                    const FlSpot(1, 0),
                    FlSpot(monthDays!.toDouble(), ideal!)
                  ],
                  color: cs.tertiary,
                  barWidth: 2,
                  dashArray: [2, 4],
                  dotData: const FlDotData(show: false),
                ),
              if (previous.any((v) => v > 0))
                LineChartBarData(
                  spots: spots(previous),
                  isCurved: false,
                  color: cs.outline,
                  barWidth: 2,
                  dashArray: [4, 4],
                  dotData: const FlDotData(show: false),
                ),
              if (current.isNotEmpty)
                LineChartBarData(
                  spots: spots(current),
                  isCurved: false,
                  color: color,
                  barWidth: 3,
                  dotData: FlDotData(
                      show: true,
                      checkToShowDot: (s, _) => s.x == current.length,
                      getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 4, color: color, strokeWidth: 0)),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: .28),
                        color.withValues(alpha: 0)
                      ],
                    ),
                  ),
                ),
            ],
          )),
        ),
      ),
    );
  }
}

class NexoDonutSlice {
  const NexoDonutSlice(this.id, this.label, this.value, this.color);
  final String id, label;
  final double value;
  final Color color;
}

/// Category ring with the total in the middle and a tappable legend.
class NexoCategoryDonut extends StatelessWidget {
  const NexoCategoryDonut(
      {super.key,
      required this.slices,
      required this.total,
      required this.money,
      required this.onSlice,
      this.maxLegend = 5});
  final List<NexoDonutSlice> slices;
  final double total;
  final String Function(double) money;
  final void Function(String id) onSlice;
  final int maxLegend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = slices.take(maxLegend).toList();
    final rest = slices.skip(maxLegend).fold<double>(0, (s, e) => s + e.value);
    final ring = <NexoDonutSlice>[
      ...shown,
      if (rest > 0)
        NexoDonutSlice('', 'Outras', rest, theme.colorScheme.outline),
    ];
    String pct(double v) => total <= 0 ? '' : '${(v / total * 100).round()}%';
    final donut = SizedBox(
      width: 150,
      height: 150,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(PieChartData(
          centerSpaceRadius: 50,
          sectionsSpace: 2,
          startDegreeOffset: -90,
          sections: [
            for (final s in ring)
              PieChartSectionData(
                  value: s.value, color: s.color, radius: 22, showTitle: false),
          ],
        )),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Total',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          FittedBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(money(total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontFeatures: NexoTones.figures)),
            ),
          ),
        ]),
      ]),
    );
    final legend = Column(children: [
      for (final s in ring)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: s.id.isEmpty ? null : () => onSlice(s.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: s.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(s.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(pct(s.value),
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: NexoTones.figures)),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(money(s.value),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFeatures: NexoTones.figures)),
                ),
              ),
            ]),
          ),
        ),
    ]);
    // Semantics sits inside the LayoutBuilder: wrapping a LayoutBuilder in
    // a labelled Semantics trips a framework assertion during relayout.
    return LayoutBuilder(builder: (context, c) {
      final chart = Semantics(
          label: 'Distribuição das despesas por categoria. Detalhes na lista.',
          child: ExcludeSemantics(child: donut));
      if (c.maxWidth < 420) {
        return Column(children: [chart, const SizedBox(height: 12), legend]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        chart,
        const SizedBox(width: 20),
        Expanded(child: legend),
      ]);
    });
  }
}

class NexoInsight {
  const NexoInsight(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      this.action,
      this.onTap});
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final String? action;
  final VoidCallback? onTap;
}

/// Swipeable cards with what deserves attention now.
class NexoInsightCarousel extends StatefulWidget {
  const NexoInsightCarousel({super.key, required this.items});
  final List<NexoInsight> items;
  @override
  State<NexoInsightCarousel> createState() => _NexoInsightCarouselState();
}

class _NexoInsightCarouselState extends State<NexoInsightCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _card(NexoInsight i) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: i.color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: i.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
                radius: 22,
                backgroundColor: i.color.withValues(alpha: .2),
                child: Icon(i.icon, color: i.color)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(i.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurfaceVariant)),
                  ]),
            ),
            if (i.action != null) ...[
              const SizedBox(width: 8),
              Text(i.action!,
                  style:
                      TextStyle(color: i.color, fontWeight: FontWeight.w800)),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.length == 1) return _card(items.single);
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      SizedBox(
        height: 112 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.6),
        child: PageView(
          controller: _controller,
          onPageChanged: (p) => setState(() => _page = p),
          children: [
            for (final i in items)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _card(i)),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var p = 0; p < items.length; p++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: p == _page ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
                color: p == _page ? cs.primary : cs.outlineVariant,
                borderRadius: BorderRadius.circular(3)),
          ),
      ]),
    ]);
  }
}

/// Thin rounded progress bar that turns warm as it fills.
class NexoProgress extends StatelessWidget {
  const NexoProgress(
      {super.key, required this.value, this.height = 8, this.color});
  final double value;
  final double height;

  /// Fixed color (e.g. an envelope's); otherwise warm as it fills.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = value.clamp(0.0, 1.0);
    final color = this.color ??
        (value >= 1
            ? NexoTones.expense(context)
            : value >= .8
                ? NexoTones.warning(context)
                : cs.primary);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Container(color: cs.surfaceContainerHighest),
          FractionallySizedBox(widthFactor: v, child: Container(color: color)),
        ]),
      ),
    );
  }
}

/// Small trend line without axes (net worth, balances).
class NexoSparkline extends StatelessWidget {
  const NexoSparkline(
      {super.key, required this.values, this.height = 56, this.color});
  final List<double> values;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    final c = color ?? Theme.of(context).colorScheme.primary;
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final pad = math.max((high - low) * .15, 1.0);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: values.length - 1.0,
          minY: low - pad,
          maxY: high + pad,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i])
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              color: c,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.withValues(alpha: .25), c.withValues(alpha: 0)]),
              ),
            ),
          ],
        )),
      ),
    );
  }
}

/// Month grid colored by how much was spent each day (Sunday first, as in
/// Brazilian calendars). Tapping a day opens its entries.
class NexoSpendingCalendar extends StatelessWidget {
  const NexoSpendingCalendar(
      {super.key,
      required this.month,
      required this.daily,
      required this.onDay,
      required this.compact});
  final DateTime month;
  final Map<DateTime, double> daily;
  final void Function(DateTime day) onDay;

  /// Short amount for a cell ("120", "1,2 mil").
  final String Function(double) compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hot = NexoTones.expense(context);
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday % 7; // Sunday = 0
    final top = daily.values.fold<double>(0, math.max);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const names = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
    return Column(children: [
      Row(children: [
        for (final n in names)
          Expanded(
              child: Center(
                  child: Text(n,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant)))),
      ]),
      const SizedBox(height: 6),
      for (var week = 0; week * 7 < offset + days; week++)
        Row(children: [
          for (var col = 0; col < 7; col++)
            Expanded(
              child: Builder(builder: (context) {
                final n = week * 7 + col - offset + 1;
                if (n < 1 || n > days) return const SizedBox(height: 46);
                final day = DateTime(month.year, month.month, n);
                final value = daily[day] ?? 0;
                final t = top <= 0 ? 0.0 : math.pow(value / top, .6).toDouble();
                final future = day.isAfter(today);
                final bg = value <= 0
                    ? cs.surfaceContainerHigh.withValues(alpha: future ? .4 : 1)
                    : Color.lerp(cs.surfaceContainerHigh, hot, .25 + .65 * t)!;
                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: Material(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: value > 0 ? () => onDay(day) : null,
                      child: SizedBox(
                        height: 42,
                        // Large accessibility text shrinks inside the cell.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('$n',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: day == today
                                            ? FontWeight.w900
                                            : FontWeight.w600)),
                                if (value > 0)
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: Text(compact(value),
                                          style: const TextStyle(
                                              fontSize: 9.5,
                                              fontFeatures: NexoTones.figures)),
                                    ),
                                  ),
                              ]),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
        ]),
    ]);
  }
}
