import 'dart:convert';

import 'package:expensy/sync/supabase_auth.dart';
import 'package:expensy/sync/supabase_sync_transport.dart';
import 'package:expensy/sync/sync_config.dart';
import 'package:expensy/sync/sync_protocol.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Fictitious project and identities; no request leaves the test.
final config = SyncConfig(
    Uri.parse('https://synthetic.supabase.co'), 'sb_publishable_synthetic');

Map<String, Object?> sessionJson(String access, {int expiresIn = 3600}) => {
      'access_token': access,
      'refresh_token': 'refresh-$access',
      'expires_in': expiresIn,
      'user': {'id': 'user-1', 'email': 'pessoa@exemplo.com'},
    };

void main() {
  late List<http.Request> requests;
  late DateTime now;
  late http.Response Function(http.Request) reply;

  SupabaseAuth auth() => SupabaseAuth(config,
      now: () => now,
      clientFactory: () => MockClient((request) async {
            requests.add(request);
            return reply(request);
          }));

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    requests = [];
    now = DateTime.utc(2026, 10, 20, 12);
    reply = (_) => http.Response('{}', 200);
  });

  test('requests a code with the publishable key only', () async {
    await auth().requestCode('  Pessoa@Exemplo.com ');
    final request = requests.single;
    expect(request.url.path, '/auth/v1/otp');
    expect(request.headers['apikey'], 'sb_publishable_synthetic');
    expect(request.headers.containsKey('Authorization'), false);
    expect(jsonDecode(request.body),
        {'email': 'pessoa@exemplo.com', 'create_user': true});
    expect(request.followRedirects, false);
  });

  test('invalid e-mail or code never reaches the server', () async {
    final a = auth();
    await expectLater(
        a.requestCode('sem-arroba'), throwsA(isA<SyncAuthException>()));
    await expectLater(a.verifyCode('pessoa@exemplo.com', '12ab'),
        throwsA(isA<SyncAuthException>()));
    expect(requests, isEmpty);
  });

  test('verified code stores a session that survives a restart', () async {
    reply = (_) => http.Response(jsonEncode(sessionJson('access-1')), 200);
    final first = auth();
    final session = await first.verifyCode('pessoa@exemplo.com', '123 456');
    expect(jsonDecode(requests.single.body),
        {'type': 'email', 'email': 'pessoa@exemplo.com', 'token': '123456'});
    expect(session.userId, 'user-1');
    final restarted = auth();
    expect(await restarted.accessToken(), 'access-1');
    expect(requests, hasLength(1), reason: 'no refresh while still valid');
  });

  test('wrong code and rate limit show actionable text, no server text',
      () async {
    reply =
        (_) => http.Response('{"msg":"Token has expired or is invalid"}', 403);
    final a = auth();
    try {
      await a.verifyCode('pessoa@exemplo.com', '123456');
      fail('expected failure');
    } on SyncAuthException catch (e) {
      expect(e.message, contains('inválido'));
      expect(e.message, isNot(contains('Token')));
    }
    reply = (_) => http.Response('{}', 429);
    await expectLater(
        a.requestCode('pessoa@exemplo.com'),
        throwsA(isA<SyncAuthException>()
            .having((e) => e.message, 'message', contains('Muitas'))));
    expect(await a.session(), isNull);
  });

  test('expiring token is refreshed once for concurrent callers', () async {
    reply = (_) =>
        http.Response(jsonEncode(sessionJson('access-1', expiresIn: 100)), 200);
    final a = auth();
    await a.verifyCode('pessoa@exemplo.com', '123456');
    now = now.add(const Duration(seconds: 50));
    reply = (_) => http.Response(jsonEncode(sessionJson('access-2')), 200);
    final tokens = await Future.wait([a.accessToken(), a.accessToken()]);
    expect(tokens, ['access-2', 'access-2']);
    final refreshes =
        requests.where((r) => r.url.path == '/auth/v1/token').toList();
    expect(refreshes, hasLength(1));
    expect(refreshes.single.url.queryParameters['grant_type'], 'refresh_token');
    expect(jsonDecode(refreshes.single.body),
        {'refresh_token': 'refresh-access-1'});
  });

  test('revoked refresh token signs out locally; offline keeps the session',
      () async {
    reply = (_) =>
        http.Response(jsonEncode(sessionJson('access-1', expiresIn: 10)), 200);
    final a = auth();
    await a.verifyCode('pessoa@exemplo.com', '123456');
    reply = (_) => throw http.ClientException('offline');
    await expectLater(a.accessToken(), throwsA(isA<SyncUnavailable>()));
    expect(await a.session(), isNotNull, reason: 'offline is not a logout');
    reply = (_) => http.Response('{"error":"invalid_grant"}', 400);
    expect(await a.accessToken(), isNull);
    expect(await a.session(), isNull);
    await expectLater(
        a.requireAccessToken(), throwsA(isA<SyncAuthenticationRequired>()));
  });

  test('sign out forgets the session even without network', () async {
    reply = (_) => http.Response(jsonEncode(sessionJson('access-1')), 200);
    final a = auth();
    await a.verifyCode('pessoa@exemplo.com', '123456');
    reply = (_) => throw http.ClientException('offline');
    await a.signOut();
    expect(await a.session(), isNull);
    expect(await auth().session(), isNull);
    final logout = requests.last;
    expect(logout.url.path, '/auth/v1/logout');
    expect(logout.headers['Authorization'], 'Bearer access-1');
  });

  test('a copied e-mail link signs in with its token hash', () async {
    reply = (_) => http.Response(jsonEncode(sessionJson('access-link')), 200);
    final a = auth();
    await a.verifyCode('pessoa@exemplo.com',
        ' https://synthetic.supabase.co/auth/v1/verify?token=abc123&type=magiclink&redirect_to=http://localhost:3000 ');
    expect(jsonDecode(requests.single.body),
        {'type': 'magiclink', 'token_hash': 'abc123'});
    expect(await a.accessToken(), 'access-link');
  });

  test('Gmail and Outlook redirect wrappers are unwrapped, then checked',
      () async {
    reply =
        (_) => http.Response(jsonEncode(sessionJson('access-wrapped')), 200);
    final inner = Uri.encodeComponent(
        'https://synthetic.supabase.co/auth/v1/verify?token=hash9&type=magiclink&redirect_to=http://localhost:3000');
    await auth().verifyCode('pessoa@exemplo.com',
        'https://www.google.com/url?q=$inner&source=gmail&ust=1&usg=x');
    expect(jsonDecode(requests.last.body)['token_hash'], 'hash9');
    await auth().verifyCode('pessoa@exemplo.com',
        'https://nam12.safelinks.protection.outlook.com/?url=$inner&data=x');
    expect(jsonDecode(requests.last.body)['token_hash'], 'hash9');
    final evil = Uri.encodeComponent(
        'https://attacker.example/auth/v1/verify?token=x&type=magiclink');
    await expectLater(
        auth().verifyCode(
            'pessoa@exemplo.com', 'https://www.google.com/url?q=$evil'),
        throwsA(isA<SyncAuthException>()));
    expect(requests, hasLength(2));
  });

  test('links from other hosts, paths or types are refused locally', () async {
    final a = auth();
    for (final link in [
      'https://attacker.example/auth/v1/verify?token=abc&type=magiclink',
      'http://synthetic.supabase.co/auth/v1/verify?token=abc&type=magiclink',
      'https://synthetic.supabase.co/other?token=abc&type=magiclink',
      'https://synthetic.supabase.co/auth/v1/verify?type=magiclink',
      'https://synthetic.supabase.co/auth/v1/verify?token=abc&type=recovery',
    ]) {
      await expectLater(a.verifyCode('pessoa@exemplo.com', link),
          throwsA(isA<SyncAuthException>()));
    }
    expect(requests, isEmpty);
  });

  test('build without coordinates has no sync configuration', () {
    expect(SyncConfig.current, isNull);
  });
}
