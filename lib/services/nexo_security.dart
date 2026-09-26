import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

class PinVerifier {
  static bool valid(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);
  static Future<String> derive(String pin, String salt) async {
    final key =
        await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256)
            .deriveKey(
                secretKey: SecretKey(utf8.encode(pin)),
                nonce: base64Decode(salt));
    return base64Encode(await key.extractBytes());
  }

  static bool equal(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  static bool timeoutReached(Duration elapsed, int seconds) =>
      elapsed >= Duration(seconds: seconds);
}

class NexoSecurity extends ChangeNotifier {
  static final instance = NexoSecurity();
  static const channel = MethodChannel('com.ma.expensy/automation');
  final FlutterSecureStorage storage;
  final LocalAuthentication auth;
  NexoSecurity({FlutterSecureStorage? storage, LocalAuthentication? auth})
      : storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(resetOnError: false)),
        auth = auth ?? LocalAuthentication();
  Map<String, dynamic> _data = {};
  bool ready = false,
      locked = true,
      authenticating = false,
      storageError = false;
  bool get enabled => _data['enabled'] == true;
  bool get hideRecents => _data['recents'] == true;
  bool get blockCapture => _data['capture'] == true;
  int get timeout => _data['timeout'] as int? ?? 0;
  int get retrySeconds => max(
      0,
      (((_data['retryAt'] as int? ?? 0) -
                  DateTime.now().millisecondsSinceEpoch) /
              1000)
          .ceil());
  Stopwatch? _background;
  Future<void> load() async {
    try {
      final text = await storage.read(key: 'nexo_security_v1');
      _data = text == null ? {} : Map<String, dynamic>.from(jsonDecode(text));
      storageError = false;
      locked = enabled;
      ready = true;
      await applyPrivacy();
    } catch (_) {
      storageError = true;
      locked = true;
      ready = true;
    }
    notifyListeners();
  }

  Future<void> _save() =>
      storage.write(key: 'nexo_security_v1', value: jsonEncode(_data));
  Future<bool> recoverStorage() async {
    if (!storageError || authenticating) return false;
    authenticating = true;
    try {
      if (!await auth.authenticate(
          localizedReason:
              'Confirme sua identidade para redefinir somente a proteção do Nexo.'))
        return false;
      // Explicit recovery after OS authentication. Never touches the financial DB.
      await const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true))
          .deleteAll();
      _data = {};
      await _save();
      storageError = false;
      ready = true;
      locked = false;
      await applyPrivacy();
      return true;
    } catch (_) {
      return false;
    } finally {
      authenticating = false;
      notifyListeners();
    }
  }

  Future<void> applyPrivacy() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await channel.invokeMethod(
        'privacy', {'recents': hideRecents, 'capture': blockCapture});
  }

  void background() {
    if (!authenticating) _background ??= Stopwatch()..start();
  }

  void resume() {
    if (enabled &&
        !authenticating &&
        _background != null &&
        PinVerifier.timeoutReached(_background!.elapsed, timeout))
      locked = true;
    _background = null;
    notifyListeners();
  }

  void lock() {
    if (enabled) {
      locked = true;
      notifyListeners();
    }
  }

  Future<bool> deviceAuth({bool biometricOnly = false}) async {
    if (authenticating || storageError) return false;
    authenticating = true;
    try {
      final ok = await auth.authenticate(
          localizedReason: 'Desbloqueie para acessar suas finanças.',
          biometricOnly: biometricOnly,
          authMessages: const [
            AndroidAuthMessages(
                signInTitle: 'Desbloquear Nexo',
                cancelButton: 'Usar PIN do Nexo')
          ]);
      if (ok) {
        locked = false;
        _data['failures'] = 0;
        _data['retryAt'] = 0;
        await _save();
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      authenticating = false;
      _background = null;
      notifyListeners();
    }
  }

  Future<bool> verify(String pin) async {
    if (storageError ||
        retrySeconds > 0 ||
        !PinVerifier.valid(pin) ||
        _data['salt'] == null) return false;
    final salt = _data['salt'] as String;
    final hash = await Isolate.run(() => PinVerifier.derive(pin, salt));
    final ok = PinVerifier.equal(hash, _data['hash'] as String);
    _data['failures'] = ok ? 0 : (_data['failures'] as int? ?? 0) + 1;
    if (!ok && (_data['failures'] as int) >= 5)
      _data['retryAt'] =
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch;
    if (ok) {
      _data['retryAt'] = 0;
      locked = false;
    }
    await _save();
    notifyListeners();
    return ok;
  }

  Future<void> setPin(String pin) async {
    if (!PinVerifier.valid(pin))
      throw ArgumentError('Use exatamente 6 dígitos.');
    final random = Random.secure();
    final salt = base64Encode(List.generate(32, (_) => random.nextInt(256)));
    final hash = await Isolate.run(() => PinVerifier.derive(pin, salt));
    _data.addAll({
      'salt': salt,
      'hash': hash,
      'enabled': true,
      'failures': 0,
      'retryAt': 0
    });
    await _save();
    locked = false;
    notifyListeners();
  }

  Future<void> configure(
      {bool? enabled, int? timeout, bool? recents, bool? capture}) async {
    if (enabled != null) _data['enabled'] = enabled;
    if (timeout != null && [0, 30, 60, 300].contains(timeout))
      _data['timeout'] = timeout;
    if (recents != null) _data['recents'] = recents;
    if (capture != null) _data['capture'] = capture;
    await _save();
    await applyPrivacy();
    notifyListeners();
  }
}
