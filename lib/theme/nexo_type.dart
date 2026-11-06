// lib/theme/nexo_type.dart
import 'package:flutter/painting.dart';

import '../services/platform_capabilities.dart';

/// Two looks, one code path. The phone keeps its heavy titles and compact
/// labels, by the owner's choice; Windows follows `docs/TIPOGRAFIA.md`, where
/// the same values fell on Segoe UI Black and read badly. Each call names the
/// phone value first and the Windows value second.
abstract final class NexoType {
  static bool get phone => !PlatformCapabilities.windows;

  // Styles that only exist on the phone.
  static const phoneGreeting = TextStyle(fontWeight: FontWeight.w900);
  static const phoneDate = TextStyle(fontSize: 12);
  static TextStyle phoneSection(Color color) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: color);

  static FontWeight weight(FontWeight phone, FontWeight windows) =>
      NexoType.phone ? phone : windows;

  static double size(double phone, double windows) =>
      NexoType.phone ? phone : windows;

  /// Windows has no tracking outside the theme.
  static double tracking(double phone) => NexoType.phone ? phone : 0;
}
