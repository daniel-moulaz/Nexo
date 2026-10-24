import 'dart:async';
import 'dart:convert';

import 'package:expensy/sync/supabase_sync_transport.dart';
import 'package:expensy/sync/sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Synthetic fixtures only. No socket is opened and no project is contacted.
final project = Uri.parse('https://synthetic-lab.supabase.co');
const publishable = 'sb_publishable_synthetic';
const device = '10000000-0000-4000-8000-000000000003';
const dataset = '10000000-0000-4000-8000-000000000001';
const epoch = '10000000-0000-4000-8000-000000000002';

String jwt(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.signature';
}

final userToken = jwt({'role': 'authenticated', 'sub': 'user-a'});

SyncOperation operation({String id = 'op-1', double balance = 900}) =>
    SyncOperation(
      id: id,
      datasetId: dataset,
      epoch: epoch,
      deviceId: device,
      createdAt: DateTime.utc(2026, 10, 20, 12),
      edits: [
        SyncEdit(const SyncKey('account', 'bank'), 1, {'balance': balance})
      ],
    );

Future<Map<String, Object?>> accepted(SyncOperation op, int revision) async => {
      'status': 'accepted',
      'revision': revision,
      'payload': op.encode(),
      'hash': await op.digest(),
    };

http.Response json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  late List<http.Request> requests;
  late int closed;

  SupabaseSyncTransport transport(
    Future<http.Response> Function(http.Request) handler, {
    Future<String?> Function()? token,
    Duration timeout = const Duration(seconds: 20),
  }) =>
      SupabaseSyncTransport(
        projectUrl: project,
        publishableKey: publishable,
        deviceId: device,
        accessToken: token ?? () async => userToken,
        timeout: timeout,
        clientFactory: () => _Tracked(MockClient((request) {
          requests.add(request);
          return handler(request);
        }), () => closed++),
      );

  setUp(() {
    requests = [];
    closed = 0;
  });

  group('configuration', () {
    test('rejects non-HTTPS, paths, credentials in URL and admin keys', () {
      SupabaseSyncTransport build(Uri url, String key) => SupabaseSyncTransport(
          projectUrl: url,
          publishableKey: key,
          deviceId: device,
          accessToken: () async => userToken);
      for (final url in [
        Uri.parse('http://synthetic-lab.supabase.co'),
        Uri.parse('https://synthetic-lab.supabase.co/rest/v1'),
        Uri.parse('https://user:pass@synthetic-lab.supabase.co'),
        Uri.parse('https://synthetic-lab.supabase.co?key=x'),
      ]) {
        expect(() => build(url, publishable),
            throwsA(isA<SyncProtocolException>()));
      }
      for (final key in ['sb_secret_x', 'service_role', 'sb_publishable_ x']) {
        expect(
            () => build(project, key), throwsA(isA<SyncProtocolException>()));
      }
    });

    test('missing, malformed, anonymous or service-role sessions never leave',
        () async {
      for (final token in [
        null,
        'not-a-jwt',
        jwt({'role': 'anon', 'sub': 'x'}),
        jwt({'role': 'service_role', 'sub': 'x'}),
        jwt({'role': 'authenticated'}),
        '$userToken extra',
      ]) {
        final t = transport((_) async => json({}), token: () async => token);
        await expectLater(
            t.push(operation()), throwsA(isA<SyncAuthenticationRequired>()));
      }
      expect(requests, isEmpty, reason: 'no request without a user session');
    });
  });

  group('requests', () {
    test('push sends exact payload, hash and user headers to the lab RPC',
        () async {
      final op = operation();
      final t = transport((_) async => json(await accepted(op, 7)));
      final result = await t.push(op);
      expect(result, isA<SyncAccepted>());
      expect((result as SyncAccepted).receipt.revision, 7);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(),
          'https://synthetic-lab.supabase.co/rest/v1/rpc/nexo_sync_lab_push');
      expect(request.headers['apikey'], publishable);
      expect(request.headers['Authorization'], 'Bearer $userToken');
      expect(request.followRedirects, false);
      final body = jsonDecode(request.body) as Map;
      expect(body['p_payload'], op.encode());
      expect(body['p_hash'], await op.digest());
      expect(closed, 1, reason: 'each request closes its own client');
    });

    test('pull is bounded to small pages and checks cursor continuity',
        () async {
      final ops = [operation(id: 'a'), operation(id: 'b')];
      final t = transport((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['p_limit'], 3);
        expect(body['p_after'], 4);
        return json([await accepted(ops[0], 5), await accepted(ops[1], 6)]);
      });
      final page =
          await t.pull(datasetId: dataset, epoch: epoch, after: 4, limit: 100);
      expect(page.map((r) => r.revision), [5, 6]);
      await expectLater(
          t.pull(datasetId: dataset, epoch: epoch, after: 0, limit: 101),
          throwsA(isA<SyncProtocolException>()));
    });
  });

  group('server responses', () {
    Future<void> rejects(Object? Function() body, String code) async {
      final t = transport((_) async => json(await body()));
      await expectLater(
          t.push(operation()),
          throwsA(isA<SyncProtocolException>()
              .having((e) => e.code, 'code', code)));
    }

    test('tampered or foreign receipts are rejected before acknowledgement',
        () async {
      final op = operation();
      final good = await accepted(op, 1);
      await rejects(() => {...good, 'hash': '0' * 64}, 'payload_hash_mismatch');
      final other = operation(id: 'other');
      await rejects(() async => await accepted(other, 1), 'receipt_mismatch');
      await rejects(
          () => {...good, 'status': 'maybe'}, 'invalid_receipt_status');
      await rejects(() => {...good, 'revision': 0}, 'invalid_cursor');
      await rejects(() => [], 'invalid_server_response');
    });

    test('conflicts must carry every entity of the rejected aggregate',
        () async {
      final complete = transport((_) async => json({
            'status': 'conflict',
            'remote': [
              {
                'kind': 'account',
                'id': 'bank',
                'revision': 2,
                'value': {'balance': 800}
              }
            ]
          }));
      final result = await complete.push(operation());
      expect((result as SyncRejected).remote.single.value, {'balance': 800});
      await rejects(() => {'status': 'conflict', 'remote': []},
          'incomplete_remote_alternative');
      await rejects(
          () => {
                'status': 'conflict',
                'remote': [
                  {'kind': 'account', 'id': 'bank', 'revision': 0, 'value': {}}
                ]
              },
          'invalid_remote_absence');
    });

    test('pull rejects gaps, foreign datasets and oversized pages', () async {
      Future<void> page(List<Object?> items, String code) async {
        final t = transport((_) async => json(items));
        await expectLater(
            t.pull(datasetId: dataset, epoch: epoch, after: 0, limit: 3),
            throwsA(isA<SyncProtocolException>()
                .having((e) => e.code, 'code', code)));
      }

      await page([await accepted(operation(id: 'a'), 2)], 'cursor_gap');
      final foreign = SyncOperation(
          id: 'f',
          datasetId: 'other',
          epoch: epoch,
          deviceId: device,
          createdAt: DateTime.utc(2026),
          edits: [SyncEdit(const SyncKey('x', 'y'), 0, {})]);
      await page([await accepted(foreign, 1)], 'wrong_dataset_or_epoch');
      await page([
        for (var i = 1; i <= 4; i++) await accepted(operation(id: 'p$i'), i)
      ], 'invalid_page');
      await page(['not-a-receipt'], 'invalid_server_response');
    });

    test('non-JSON and oversized bodies fail closed', () async {
      final text = transport((_) async => http.Response('<html>', 200));
      await expectLater(
          text.push(operation()), throwsA(isA<SyncProtocolException>()));
      final huge = SupabaseSyncTransport(
        projectUrl: project,
        publishableKey: publishable,
        deviceId: device,
        accessToken: () async => userToken,
        clientFactory: () => MockClient.streaming((request, _) async =>
            http.StreamedResponse(
                Stream.fromIterable(
                    List.generate(9, (_) => List.filled(1024 * 1024, 32))),
                200)),
      );
      await expectLater(
          huge.push(operation()),
          throwsA(isA<SyncProtocolException>()
              .having((e) => e.code, 'code', 'response_too_big')));
    });
  });

  group('failures', () {
    Future<Object> failure(http.Response response) async {
      final t = transport((_) async => response);
      try {
        await t.push(operation());
      } catch (error) {
        return error;
      }
      fail('expected a failure');
    }

    test('expired or invalid sessions ask for authentication, not retry',
        () async {
      expect(
          await failure(
              json({'code': 'PGRST303', 'message': 'JWT expired'}, 401)),
          isA<SyncAuthenticationRequired>());
      expect(
          await failure(json(
              {'code': '42501', 'message': 'authentication_required'}, 403)),
          isA<SyncAuthenticationRequired>());
      expect(await failure(http.Response('', 401)),
          isA<SyncAuthenticationRequired>());
    });

    test('revoked device is distinct from an expired session', () async {
      expect(
          await failure(
              json({'code': '42501', 'message': 'device_unavailable'}, 403)),
          isA<SyncDeviceRevoked>());
    });

    test('known server validation codes are surfaced, unknown text is not',
        () async {
      final reused = await failure(
          json({'code': '22023', 'message': 'operation_id_reused'}, 400));
      expect((reused as SyncProtocolException).code, 'operation_id_reused');
      final leaked = await failure(json(
          {'code': '22023', 'message': 'row with Salário 1500 failed'}, 400));
      expect((leaked as SyncProtocolException).code, 'backend_http_400');
      final notOwned = await failure(
          json({'code': '42501', 'message': 'dataset_unavailable'}, 403));
      expect((notOwned as SyncProtocolException).code, 'dataset_unavailable');
    });

    test('rate limit, server errors, network errors and timeout are retryable',
        () async {
      for (final status in [429, 500, 502, 503]) {
        expect(
            await failure(http.Response('', status)), isA<SyncUnavailable>());
      }
      final offline =
          transport((_) async => throw http.ClientException('offline'));
      await expectLater(
          offline.push(operation()), throwsA(isA<SyncUnavailable>()));
      final slow = transport((_) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 20));
      await expectLater(
          slow.push(operation()), throwsA(isA<SyncUnavailable>()));
      expect(closed, requests.length,
          reason: 'timed-out and failed clients are closed');
    });

    test('redirects are not followed and keep the token on the project host',
        () async {
      final moved = await failure(http.Response('', 302,
          headers: {'location': 'https://attacker.invalid/steal'}));
      expect((moved as SyncProtocolException).code, 'backend_http_302');
      expect(requests.single.url.host, project.host);
    });

    test('oversized error bodies are not buffered', () async {
      final t = SupabaseSyncTransport(
        projectUrl: project,
        publishableKey: publishable,
        deviceId: device,
        accessToken: () async => userToken,
        clientFactory: () => MockClient.streaming((request, _) async =>
            http.StreamedResponse(
                Stream.fromIterable(
                    List.generate(64, (_) => List.filled(1024, 32))),
                400)),
      );
      await expectLater(
          t.push(operation()),
          throwsA(isA<SyncProtocolException>()
              .having((e) => e.code, 'code', 'backend_http_400')));
    });
  });
}

class _Tracked extends http.BaseClient {
  _Tracked(this._inner, this._onClose);
  final http.Client _inner;
  final void Function() _onClose;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);
  @override
  void close() {
    _onClose();
    _inner.close();
  }
}
