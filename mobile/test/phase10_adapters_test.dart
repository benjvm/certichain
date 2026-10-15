import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/features/revocation/data/supabase_revocation_repository.dart';
import 'package:mobile/features/revocation/domain/revocation_repository.dart';

const user = 'aa000000-0000-4000-8000-000000000001',
    cert = 'aa000000-0000-4000-8000-000000000002';
const scope = RevocationScope(
  user,
  'aa000000-0000-4000-8000-000000000011',
  cert,
);
Map<String, Object?> dto() => {
  'certificate_id': cert,
  'request_id': cert,
  'status': 'revoked',
  'revoked_at': '2026-10-15T00:00:00.123456Z',
  'reason': 'Private text',
  'synchronization': [
    {'operation_id': cert, 'status': 'requested'},
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late SupabaseRevocationRepository repo;
  late Future<http.Response> Function(http.Request) action;
  setUp(() async {
    action = (r) async => http.Response(jsonEncode(dto()), 202);
    final transport = MockClient((r) async {
      if (r.url.path.endsWith('/token')) {
        final token =
            'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.signature';
        return http.Response(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'synthetic',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': user,
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (r.url.path.endsWith('/logout')) return http.Response('{}', 200);
      return action(r);
    });
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'public',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'synthetic@example.invalid',
      password: 'synthetic',
    );
    repo = SupabaseRevocationRepository(
      client,
      apiUrl: 'http://127.0.0.1:54321',
      publicKey: 'public',
      transport: transport,
    );
  });
  tearDown(() async {
    await client.dispose();
    repo.close();
  });
  test('Auth request contains only closed inputs; response means SQL revoked, pending EVM', () async {
    action = (r) async {
      expect(r.url.path, '/functions/v1/revoke-certificate');
      expect(r.headers['Authorization'], startsWith('Bearer '));
      expect(jsonDecode(r.body), {
        'certificate_id': cert,
        'idempotency_key': cert,
        'reason': 'Private text',
      });
      return http.Response(jsonEncode(dto()), 202);
    };
    final d = await repo.request(scope, cert, 'Private text');
    expect(d.revoked, isTrue);
    expect(d.synchronization.single.status, RevocationSyncStatus.requested);
    expect(d.revokedAt!.microsecond, 456);
  });
  for (final changed in [
    {'certificate_id': user},
    {'raw': 'private'},
    {'status': 'active'},
    {'revoked_at': '2026-02-30T00:00:00Z'},
  ]) {
    test(
      'private DTO rejects wrong identity, widening or incoherent dates',
      () async {
        action = (r) async =>
            http.Response(jsonEncode({...dto(), ...changed}), 200);
        await expectLater(repo.progress(scope), throwsA(isA<Exception>()));
      },
    );
  }
  test('late response after logout cannot deliver reason or status', () async {
    final barrier = Completer<http.Response>();
    action = (r) => barrier.future;
    final pending = repo.progress(scope);
    await Future<void>.delayed(Duration.zero);
    await client.auth.signOut();
    barrier.complete(http.Response(jsonEncode(dto()), 200));
    await expectLater(
      pending,
      throwsA(
        isA<RevocationException>().having(
          (e) => e.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
  });
  test('progress never calls request or reauthorize and sanitized errors are bounded', () async {
    action = (r) async {
      expect(r.url.path, '/functions/v1/revocation-progress');
      expect(jsonDecode(r.body), {'certificate_id': cert});
      return http.Response('{"error":"revocation_unavailable"}', 404);
    };
    await expectLater(
      repo.progress(scope),
      throwsA(
        isA<RevocationException>().having(
          (e) => e.code,
          'code',
          'revocation_unavailable',
        ),
      ),
    );
  });
}
