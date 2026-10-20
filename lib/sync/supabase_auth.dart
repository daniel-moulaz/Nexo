import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../services/desktop_profile.dart';
import 'supabase_sync_transport.dart' show SyncAuthenticationRequired;
import 'sync_config.dart';
import 'sync_protocol.dart' show SyncUnavailable;

/// A failure the person can act on; messages never contain the e-mail,
/// the code or any token.
class SyncAuthException implements Exception {
  const SyncAuthException(this.message);
  final String message;
  @override
  String toString() => 'SyncAuthException';
}

class SyncSession {
  const SyncSession(
      {required this.accessToken,
      required this.refreshToken,
      required this.expiresAt,
      required this.userId,
      required this.email});
  final String accessToken, refreshToken, userId, email;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'user_id': userId,
        'email': email,
      };

  static SyncSession? fromJson(Map<String, dynamic> json) {
    final access = json['access_token'], refresh = json['refresh_token'];
    final user = json['user_id'], email = json['email'];
    final expires = DateTime.tryParse('${json['expires_at']}');
    if (access is! String ||
        refresh is! String ||
        user is! String ||
        email is! String ||
        expires == null) {
      return null;
    }
    return SyncSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: expires,
        userId: user,
        email: email);
  }
}

/// E-mail one-time-code login against Supabase Auth, without deep links, so
/// Android and Windows behave the same. The PIN stays local and unrelated.
class SupabaseAuth {
  SupabaseAuth(this.config,
      {FlutterSecureStorage? storage,
      http.Client Function()? clientFactory,
      DateTime Function()? now,
      this.timeout = const Duration(seconds: 20)})
      : _storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(resetOnError: false)),
        _clientFactory = clientFactory ?? http.Client.new,
        _now = now ?? DateTime.now;

  /// The app-wide instance, shared by the sign-in screen and automatic
  /// sync so both see the same session.
  static SupabaseAuth? app;

  final SyncConfig config;
  final FlutterSecureStorage _storage;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;
  final Duration timeout;
  SyncSession? _session;
  bool _loaded = false;
  Future<SyncSession?>? _refreshing;

  static String get storageKey => DesktopProfile.isTest
      ? 'nexo_windows_qa${DesktopProfile.qaSuffix}_sync_session_v1'
      : 'nexo_sync_session_v1';

  static final _email = RegExp(r'^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s]{2,}$');
  static final _code = RegExp(r'^\d{6,10}$');

  Future<SyncSession?> session() async {
    if (!_loaded) {
      _loaded = true;
      try {
        final raw = await _storage.read(key: storageKey);
        _session = raw == null
            ? null
            : SyncSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _session = null;
      }
    }
    return _session;
  }

  Future<void> _save(SyncSession? session) async {
    _session = session;
    _loaded = true;
    if (session == null) {
      await _storage.delete(key: storageKey);
    } else {
      await _storage.write(key: storageKey, value: jsonEncode(session));
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body,
      {Map<String, String> query = const {}, String? bearer}) async {
    final client = _clientFactory();
    try {
      final request = http.Request(
          'POST',
          config.projectUrl
              .resolve(path)
              .replace(queryParameters: query.isEmpty ? null : query))
        ..followRedirects = false
        ..headers.addAll({
          'apikey': config.publishableKey,
          'Content-Type': 'application/json',
          if (bearer != null) 'Authorization': 'Bearer $bearer',
        })
        ..body = jsonEncode(body);
      final response =
          await http.Response.fromStream(await client.send(request))
              .timeout(timeout);
      if (response.statusCode == 429) {
        throw const SyncAuthException(
            'Muitas tentativas. Aguarde alguns minutos antes de pedir outro código.');
      }
      if (response.statusCode >= 500) throw const SyncUnavailable();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _HttpStatus(response.statusCode);
      }
      if (response.body.isEmpty) return const {};
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const SyncAuthException('Resposta inesperada do servidor.');
      }
      return decoded;
    } on TimeoutException {
      throw const SyncUnavailable();
    } on http.ClientException {
      throw const SyncUnavailable();
    } on FormatException {
      throw const SyncAuthException('Resposta inesperada do servidor.');
    } finally {
      client.close();
    }
  }

  SyncSession _parse(Map<String, dynamic> json, String fallbackEmail) {
    final access = json['access_token'], refresh = json['refresh_token'];
    final user = json['user'];
    final seconds = json['expires_in'];
    if (access is! String ||
        refresh is! String ||
        user is! Map ||
        user['id'] is! String ||
        seconds is! num) {
      throw const SyncAuthException('Resposta inesperada do servidor.');
    }
    return SyncSession(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: _now().toUtc().add(Duration(seconds: seconds.toInt())),
        userId: user['id'] as String,
        email: (user['email'] as String?) ?? fallbackEmail);
  }

  String _normalize(String email) {
    final value = email.trim().toLowerCase();
    if (!_email.hasMatch(value)) {
      throw const SyncAuthException('Informe um e-mail válido.');
    }
    return value;
  }

  /// Sends a one-time code by e-mail. The account is created on first use.
  Future<void> requestCode(String email) async {
    final address = _normalize(email);
    try {
      await _post('/auth/v1/otp', {'email': address, 'create_user': true});
    } on _HttpStatus catch (e) {
      throw SyncAuthException(
          'Não foi possível enviar o e-mail de acesso (HTTP ${e.code}). Confira o endereço.');
    }
  }

  /// Accepts the numeric code or, when the project still sends the default
  /// e-mail with a link, that link copied without opening it. The link is
  /// only accepted for this project's own host.
  Future<SyncSession> verifyCode(String email, String code) async {
    final address = _normalize(email);
    final input = code.trim();
    final Map<String, Object?> body;
    if (input.contains('://')) {
      body = _linkBody(input);
    } else {
      final token = input.replaceAll(RegExp(r'\s'), '');
      if (!_code.hasMatch(token)) {
        throw const SyncAuthException(
            'Digite o código numérico ou cole o link do e-mail.');
      }
      body = {'type': 'email', 'email': address, 'token': token};
    }
    final Map<String, dynamic> json;
    try {
      json = await _post('/auth/v1/verify', body);
    } on _HttpStatus catch (e) {
      throw SyncAuthException(
          'Código ou link inválido, expirado ou já usado (HTTP ${e.code}). Peça um novo e-mail.');
    }
    final session = _parse(json, address);
    await _save(session);
    return session;
  }

  /// Mail apps often copy a redirect wrapper instead of the real link
  /// (Gmail `google.com/url?q=`, Outlook Safe Links `?url=`). Only the
  /// wrapped address is used, and it still has to be this project's link.
  static Uri? _unwrap(String link) {
    var uri = Uri.tryParse(link.trim());
    for (var depth = 0; uri != null && depth < 3; depth++) {
      final host = uri.host.toLowerCase();
      final inner = (host == 'www.google.com' || host == 'google.com') &&
              uri.path == '/url'
          ? uri.queryParameters['q'] ?? uri.queryParameters['url']
          : host.endsWith('safelinks.protection.outlook.com')
              ? uri.queryParameters['url']
              : null;
      if (inner == null) return uri;
      uri = Uri.tryParse(inner);
    }
    return uri;
  }

  Map<String, Object?> _linkBody(String link) {
    final uri = _unwrap(link);
    final token =
        uri?.queryParameters['token'] ?? uri?.queryParameters['token_hash'];
    final type = uri?.queryParameters['type'] ?? 'magiclink';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != config.projectUrl.host ||
        uri.path != '/auth/v1/verify' ||
        token == null ||
        token.isEmpty ||
        token.length > 512 ||
        !const {'magiclink', 'signup', 'email'}.contains(type)) {
      throw const SyncAuthException(
          'Este link não é do seu projeto Nexo. Copie o link do e-mail de acesso.');
    }
    return {'type': type, 'token_hash': token};
  }

  /// Password sign-in for accounts created with a password in the Supabase
  /// dashboard. Sends no e-mail, so it does not depend on mail limits. The
  /// password is used for this request only and never stored.
  Future<SyncSession> signInWithPassword(String email, String password) async {
    final address = _normalize(email);
    if (password.length < 8 || password.length > 256) {
      throw const SyncAuthException('A senha tem pelo menos 8 caracteres.');
    }
    final Map<String, dynamic> json;
    try {
      json = await _post('/auth/v1/token', {
        'email': address,
        'password': password,
      }, query: const {
        'grant_type': 'password'
      });
    } on _HttpStatus catch (e) {
      throw SyncAuthException(e.code == 400
          ? 'E-mail ou senha incorretos, ou a conta ainda não foi confirmada.'
          : 'Não foi possível entrar (HTTP ${e.code}).');
    }
    final session = _parse(json, address);
    await _save(session);
    return session;
  }

  /// A valid access token, renewed shortly before expiry. Null means the
  /// person must sign in again; local work is never blocked by this.
  Future<String?> accessToken() async {
    final current = await session();
    if (current == null) return null;
    if (current.expiresAt
        .isAfter(_now().toUtc().add(const Duration(seconds: 60)))) {
      return current.accessToken;
    }
    final refreshed = await (_refreshing ??=
        _refresh(current).whenComplete(() => _refreshing = null));
    return refreshed?.accessToken;
  }

  Future<SyncSession?> _refresh(SyncSession current) async {
    try {
      final json = await _post(
          '/auth/v1/token', {'refresh_token': current.refreshToken},
          query: const {'grant_type': 'refresh_token'});
      final next = _parse(json, current.email);
      await _save(next);
      return next;
    } on _HttpStatus {
      // Revoked or reused refresh token: sign in again, keep local data.
      await _save(null);
      return null;
    }
  }

  /// Ends the session on this device. Local data stays; the server session
  /// is revoked when reachable, and the local copy is removed regardless.
  Future<void> signOut() async {
    final current = await session();
    try {
      if (current != null) {
        await _post('/auth/v1/logout', const {},
            query: const {'scope': 'local'}, bearer: current.accessToken);
      }
    } catch (_) {
      // Offline or already expired: forgetting the session locally suffices.
    } finally {
      await _save(null);
    }
  }

  /// For transports: a token or the explicit need to sign in.
  Future<String> requireAccessToken() async =>
      await accessToken() ?? (throw const SyncAuthenticationRequired());
}

class _HttpStatus implements Exception {
  const _HttpStatus(this.code);
  final int code;
}
