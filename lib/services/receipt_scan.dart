import 'dart:io';
import 'receipt_parser.dart';

/// Takes a photo of a receipt and reads it. The OCR engine is injected so the
/// screen does not depend on a native package: when none is wired (Windows,
/// or a build without ML Kit) [available] is false and the button hides.
abstract final class ReceiptScan {
  /// Set by the platform bootstrap when an OCR engine exists.
  static Future<String> Function(File image)? recognizer;

  /// Set by the platform bootstrap when a camera/picker exists.
  static Future<File?> Function()? picker;

  static bool get available => recognizer != null && picker != null;

  /// Null when the person cancelled; a reading (possibly without a total)
  /// otherwise. Never throws: an OCR failure reads as an empty receipt.
  static Future<ReceiptReading?> scan({DateTime? now}) async {
    final pick = picker;
    final read = recognizer;
    if (pick == null || read == null) return null;
    final file = await pick();
    if (file == null) return null;
    try {
      return ReceiptParser.parse(await read(file), now: now);
    } catch (_) {
      return const ReceiptReading();
    }
  }
}
