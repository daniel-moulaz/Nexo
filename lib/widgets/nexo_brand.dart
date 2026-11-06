import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../theme/nexo_tokens.dart';

export '../theme/nexo_tokens.dart';

/// The Engate: two hooks that hold each other form the N. Drawn from the same
/// two paths as `docs/brand/nexo-mark.svg`, so it stays sharp at any size.
class NexoMark extends StatelessWidget {
  const NexoMark({super.key, this.size = 28, this.first, this.second});
  final double size;
  final Color? first, second;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
          size: Size.square(size),
          painter: _MarkPainter(first ?? cs.primary, second ?? cs.onSurface)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.first, this.second);
  final Color first, second;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(25, 81)
          ..lineTo(25, 38)
          ..cubicTo(25, 21, 39, 16, 50, 27)
          ..lineTo(60, 37),
        paint..color = first);
    canvas.drawPath(
        Path()
          ..moveTo(75, 19)
          ..lineTo(75, 62)
          ..cubicTo(75, 79, 61, 84, 50, 73)
          ..lineTo(40, 63),
        paint..color = second);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.first != first || old.second != second;
}

/// The signature surface: ink in both themes, with the mark as a watermark.
/// One per screen, for the number that matters there.
class NexoInkPanel extends StatelessWidget {
  const NexoInkPanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(NexoSpace.xl)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Whatever is inside reads as dark, whichever the app's theme is.
  static final _ink = buildTheme(seed: 'nexo', dark: true);

  @override
  Widget build(BuildContext context) {
    return Theme(data: _ink, child: _panel());
  }

  Widget _panel() {
    return Material(
      color: NexoBrand.ink,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexoRadius.panel),
          side: const BorderSide(color: NexoBrand.inkLine)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [NexoBrand.inkHigh, NexoBrand.ink])),
        child: Stack(children: [
          Positioned(
              right: -36,
              top: -30,
              child: NexoMark(
                  size: 190,
                  first: NexoBrand.teal.withValues(alpha: .10),
                  second: NexoBrand.paper.withValues(alpha: .05))),
          SizedBox(
            width: double.infinity,
            child: Padding(
                padding: padding,
                child: DefaultTextStyle.merge(
                    style: const TextStyle(color: NexoBrand.onInk),
                    child: IconTheme.merge(
                        data: const IconThemeData(color: NexoBrand.onInk),
                        child: child))),
          ),
        ]),
      ),
    );
  }
}

/// A figure inside the ink panel: small label, value below.
class NexoInkStat extends StatelessWidget {
  const NexoInkStat(
      {super.key,
      required this.label,
      required this.value,
      this.color,
      this.onTap});
  final String label, value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
        label: '$label: $value',
        button: onTap != null,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(NexoRadius.chip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NexoSpace.xs),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: NexoBrand.onInkMuted)),
              const SizedBox(height: 2),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: color ?? NexoBrand.onInk,
                          fontFeatures: NexoTones.figures))),
            ]),
          ),
        ));
  }
}
