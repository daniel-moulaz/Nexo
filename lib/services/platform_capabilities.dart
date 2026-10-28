import 'package:flutter/foundation.dart';

/// Native integrations exposed by this release. Financial rules stay shared.
abstract final class PlatformCapabilities {
  static bool get windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get scheduledNotifications => android;
  static bool get homeWidgets => android;
  static bool get deviceAuthentication => android;
  static bool get captureProtection => android;
}
