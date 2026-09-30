import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'platform_capabilities.dart';

/// Mobile pickers write bytes themselves; Windows returns a selected path.
abstract final class FileOutput {
  static Future<String?> save(
      {required String title,
      required String name,
      required String extension,
      required Uint8List bytes}) async {
    final path = await FilePicker.platform.saveFile(
        dialogTitle: title,
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes);
    if (path == null) return null;
    if (PlatformCapabilities.windows) await write(path, bytes);
    return path;
  }

  /// Write completely before replacing a destination approved in the dialog.
  static Future<void> write(String path, Uint8List bytes) async {
    final temporary = File('$path.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
