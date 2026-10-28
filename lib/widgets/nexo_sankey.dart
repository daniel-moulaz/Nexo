import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One band of the flow: from the left column to a right-hand target.
class SankeyFlow {
  const SankeyFlow(
      {required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
}

/// Income on the left, where it went on the right, as bands whose height is
/// the money. One picture answers "from where to where", the way Monarch's
/// cash-flow view does; no legend to read, the labels sit on the bands.
class NexoSankey extends StatelessWidget {
  const NexoSankey(
      {super.key,
      required this.sourceLabel,
      required this.source,
      required this.flows,
      required this.money,
      this.height = 220});
  final String sourceLabel;
  final double source;
  final List<SankeyFlow> flows;
  final String Function(double) money;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      label:
          '$sourceLabel ${money(source)}: ${flows.map((f) => '${f.label} ${money(f.value)}').join(', ')}',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _SankeyPainter(
              source: source,
              flows: flows,
              textColor: cs.onSurface,
              mutedColor: cs.onSurfaceVariant,
              sourceColor: cs.primary,
              labelStyle:
                  theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
              valueStyle:
                  (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
                      .copyWith(fontWeight: FontWeight.w800),
              sourceLabel: sourceLabel,
              money: money),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SankeyPainter extends CustomPainter {
  _SankeyPainter(
      {required this.source,
      required this.flows,
      required this.textColor,
      required this.mutedColor,
      required this.sourceColor,
      required this.labelStyle,
      required this.valueStyle,
      required this.sourceLabel,
      required this.money});
  final double source;
  final List<SankeyFlow> flows;
  final Color textColor, mutedColor, sourceColor;
  final TextStyle labelStyle, valueStyle;
  final String sourceLabel;
  final String Function(double) money;

  @override
  void paint(Canvas canvas, Size size) {
    final total = math.max(source, flows.fold(0.0, (s, f) => s + f.value));
    if (total <= 0 || size.width < 80) return;
    const barWidth = 10.0;
    const gap = 6.0;
    final labelWidth = math.min(140.0, size.width * .38);
    final left = 0.0;
    final right = size.width - barWidth - labelWidth;
    final usable = size.height - gap * math.max(0, flows.length - 1);
    final scale = usable / total;

    // Source bar.
    final sourceHeight = source * scale;
    final sourceTop = (size.height - sourceHeight) / 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left, sourceTop, barWidth, sourceHeight),
            const Radius.circular(4)),
        Paint()..color = sourceColor);
    _text(canvas, sourceLabel, labelStyle.copyWith(color: mutedColor),
        Offset(left + barWidth + 6, sourceTop), labelWidth);
    _text(canvas, money(source), valueStyle.copyWith(color: textColor),
        Offset(left + barWidth + 6, sourceTop + 14), labelWidth);

    // Bands and targets.
    var sy = sourceTop;
    var ty = 0.0;
    for (final f in flows) {
      final h = f.value * scale;
      final band = Path()
        ..moveTo(left + barWidth, sy)
        ..cubicTo(size.width * .45, sy, size.width * .55, ty, right, ty)
        ..lineTo(right, ty + h)
        ..cubicTo(size.width * .55, ty + h, size.width * .45, sy + h,
            left + barWidth, sy + h)
        ..close();
      canvas.drawPath(band, Paint()..color = f.color.withValues(alpha: .28));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(right, ty, barWidth, h), const Radius.circular(4)),
          Paint()..color = f.color);
      final labelTop = ty + math.max(0, (h - 26) / 2);
      _text(canvas, f.label, labelStyle.copyWith(color: mutedColor),
          Offset(right + barWidth + 6, labelTop), labelWidth - 6);
      _text(canvas, money(f.value), valueStyle.copyWith(color: textColor),
          Offset(right + barWidth + 6, labelTop + 13), labelWidth - 6);
      sy += h;
      ty += h + gap;
    }
  }

  void _text(
      Canvas canvas, String s, TextStyle style, Offset at, double maxWidth) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: math.max(10, maxWidth));
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SankeyPainter old) =>
      old.source != source ||
      old.flows != flows ||
      old.textColor != textColor ||
      old.sourceColor != sourceColor;
}
