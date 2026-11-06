// lib/theme/nexo_tokens.dart
import 'package:flutter/material.dart';

/// The Nexo look in one place. Changing the brand means changing this file
/// and the mark's two paths in `widgets/nexo_brand.dart`: screens only read
/// these tokens. Rules of use are in `docs/design-system.md`.
abstract final class NexoBrand {
  /// The ink: the mark's background, the app's dark surfaces and the panel
  /// that stays dark in both themes. It is what makes a screen read as Nexo.
  static const ink = Color(0xFF0E1420);
  static const inkRaised = Color(0xFF16202F);
  static const inkHigh = Color(0xFF1F2B3D);
  static const inkLine = Color(0xFF2C3A4F);

  /// The mark's two strands.
  static const teal = Color(0xFF5EEAD4);
  static const paper = Color(0xFFF8FAFC);

  /// Teal that passes 4.5:1 on light surfaces.
  static const tealDeep = Color(0xFF0F766E);

  /// On the ink panel, in both themes.
  static const onInk = Color(0xFFF1F5F9);
  static const onInkMuted = Color(0xFFA9B6C6);
}

/// Spacing scale. Rhythm comes from using few of these.
abstract final class NexoSpace {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
}

abstract final class NexoRadius {
  static const double chip = 12, field = 14, card = 20, panel = 24, sheet = 28;
}

/// Short and consistent; none at all when the system asks for less motion.
abstract final class NexoMotion {
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 240);
  static const curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, [Duration base = medium]) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true
          ? Duration.zero
          : base;
}

/// What money and state mean. These never stand for the brand, and the brand
/// color never stands for them: gain is a yellow green so that it cannot be
/// read as the mark's teal, and every one has a sign or a word beside it.
abstract final class NexoTones {
  static Color _pick(BuildContext context, Color dark, Color light) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const incomeOnInk = Color(0xFFB4E86B);
  static const expenseOnInk = Color(0xFFFB8FA0);
  static const warningOnInk = Color(0xFFFBBF24);

  static Color income(BuildContext context) =>
      _pick(context, incomeOnInk, const Color(0xFF3F6212));
  static Color expense(BuildContext context) =>
      _pick(context, expenseOnInk, const Color(0xFFBE123C));
  static Color warning(BuildContext context) =>
      _pick(context, warningOnInk, const Color(0xFF92400E));
  static Color info(BuildContext context) =>
      _pick(context, const Color(0xFF7DD3FC), const Color(0xFF0369A1));

  /// A category's own color, moved to a lightness that reads on this theme:
  /// many are stored dark, and vanished on the dark surfaces.
  static Color category(BuildContext context, Color color) {
    final hsl = HSLColor.fromColor(color);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lightness =
        dark ? hsl.lightness.clamp(.68, .82) : hsl.lightness.clamp(.22, .34);
    return hsl
        .withLightness(lightness.toDouble())
        .withSaturation(hsl.saturation.clamp(.45, .85).toDouble())
        .toColor();
  }

  /// Text or icon that stays readable on a fill of any color.
  static Color on(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
          ? Colors.white
          : NexoBrand.ink;

  /// Numbers line up in columns and read as figures, not prose.
  static const figures = [FontFeature.tabularFigures()];
}

/// Series for charts with no color of their own. Picked to stay apart for
/// people with red-green color blindness, and away from gain and loss.
abstract final class NexoChart {
  /// Same hue order in both themes, each checked against its own card surface
  /// for lightness, contrast and color blindness. The order matters: neighbors
  /// are the pairs that must stay apart. Far from gain and loss on purpose.
  static const seriesDark = [
    Color(0xFF12A594),
    Color(0xFFC2851A),
    Color(0xFF8F7BE8),
    Color(0xFFD9743A),
    Color(0xFF4C8DE8),
    Color(0xFFC75FB8),
  ];
  static const seriesLight = [
    Color(0xFF00897A),
    Color(0xFF9A6A00),
    Color(0xFF6D5BD0),
    Color(0xFFB45309),
    Color(0xFF2563EB),
    Color(0xFFC026A3),
  ];

  /// Every chart tooltip: the inverse surface reads over any series.
  static Color tooltip(BuildContext context) =>
      Theme.of(context).colorScheme.inverseSurface;
  static TextStyle tooltipText(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.onInverseSurface,
      fontWeight: FontWeight.w600);

  /// The color of the [index]th series. Past the palette a series reads as
  /// "others": new hues are never made up and colors never repeat.
  static Color slot(BuildContext context, int index) {
    final theme = Theme.of(context);
    final series =
        theme.brightness == Brightness.dark ? seriesDark : seriesLight;
    return index < series.length
        ? series[index]
        : theme.colorScheme.onSurfaceVariant;
  }
}
