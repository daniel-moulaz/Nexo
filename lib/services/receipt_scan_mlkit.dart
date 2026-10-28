import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'platform_capabilities.dart';
import 'receipt_scan.dart';

/// Android only: the camera through image_picker and Google ML Kit's on-device
/// Latin text recognizer. Nothing leaves the phone. Called once at startup.
void wireReceiptScan() {
  if (!PlatformCapabilities.android) return;
  ReceiptScan.picker = () async {
    final shot = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 1600);
    return shot == null ? null : File(shot.path);
  };
  ReceiptScan.recognizer = (file) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFile(file));
      return result.text;
    } finally {
      await recognizer.close();
    }
  };
}
