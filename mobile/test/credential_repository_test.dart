import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/features/verification/data/supabase_credential_repository.dart';

import 'verification_repository_test.dart' show publicCode;

void main() {
  late SupabaseClient client;
  late Future<http.Response> Function(http.Request) read;
  var owner = 'holder-a', tokenVersion = 0, expires = 0, calls = 0;
  Map<String, Object?> row() => {
    'id': 'internal-id',
    'holder_id': 'holder-a',
    'credential_code': publicCode,
    'issuance_operation_id': 'e42f105a-a36b-40de-8326-47da5749eae4',
  };
  setUp(() async {
    owner = 'holder-a';
    tokenVersion = 0;
    calls = 0;
    expires =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    read = (_) async => http.Response(
      jsonEncode([row()]),
      200,
      headers: {'content-type': 'application/json'},
    );
    client = SupabaseClient(
      'http://127.0.0.1:55321',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          final token =
              'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': expires, 'v': tokenVersion}))).replaceAll('=', '')}.signature';
          return http.Response(
            jsonEncode({
              'access_token': token,
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': owner,
                'aud': 'authenticated',
                'created_at': '2026-01-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/logout')) {
          return http.Response('{}', 200);
        }
        calls++;
        final response = await read(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'synthetic@example.invalid',
      password: 'synthetic',
    );
  });
  tearDown(() async => client.dispose());
  test('minimal own authenticated SELECT: holder+id, public code is not internal id', () async {
    read = (request) async {
      expect(request.url.path, '/rest/v1/certificates');
      expect(
        request.url.queryParameters['select'],
        'id,holder_id,credential_code,issuance_operation_id',
      );
      expect(request.url.queryParameters['id'], 'eq.internal-id');
      expect(request.url.queryParameters['holder_id'], 'eq.holder-a');
      expect(request.headers['Authorization'], isNotNull);
      return http.Response(
        jsonEncode([row()]),
        200,
        headers: {'content-type': 'application/json'},
      );
    };
    expect(
      await SupabaseCredentialRepository(client)
          .readOwnCode('holder-a', 'internal-id'),
      publicCode,
    );
  });
  test('absent and legacy without evidence do not fabricate link', () async {
    final repository = SupabaseCredentialRepository(client);
    read = (_) async =>
        http.Response('[]', 200, headers: {'content-type': 'application/json'});
    expect(await repository.readOwnCode('holder-a', 'internal-id'), isNull);
    read = (_) async => http.Response(
      jsonEncode([row()..['issuance_operation_id'] = null]),
      200,
      headers: {'content-type': 'application/json'},
    );
    expect(await repository.readOwnCode('holder-a', 'internal-id'), isNull);
  });
  test('unknown owner/session fail before HTTP and unexpected identities fail closed', () async {
    final repository = SupabaseCredentialRepository(client);
    await expectLater(
      repository.readOwnCode('holder-b', 'internal-id'),
      throwsFormatException,
    );
    expect(calls, 0);
    read = (_) async => http.Response(
      jsonEncode([row()..['holder_id'] = 'holder-b']),
      200,
      headers: {'content-type': 'application/json'},
    );
    await expectLater(
      repository.readOwnCode('holder-a', 'internal-id'),
      throwsFormatException,
    );
    await client.auth.signOut();
    final before = calls;
    await expectLater(
      repository.readOwnCode('holder-a', 'internal-id'),
      throwsFormatException,
    );
    expect(calls, before);
  });
  for (final change in ['logout', 'account', 'token', 'expired']) {
    test('discard real SDK response after $change during own read', () async {
      final arrived = Completer<void>(), release = Completer<void>();
      read = (_) async {
        arrived.complete();
        await release.future;
        return http.Response(
          jsonEncode([row()]),
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      final pending = SupabaseCredentialRepository(client)
          .readOwnCode('holder-a', 'internal-id');
      final assertion = expectLater(pending, throwsFormatException);
      await arrived.future;
      if (change == 'logout') {
        await client.auth.signOut();
      } else {
        tokenVersion++;
        if (change == 'account') owner = 'holder-b';
        if (change == 'expired') {
          expires =
              DateTime.now()
                  .subtract(const Duration(seconds: 10))
                  .millisecondsSinceEpoch ~/
              1000;
        }
        await client.auth.signInWithPassword(
          email: 'synthetic@example.invalid',
          password: 'synthetic',
        );
      }
      release.complete();
      await assertion;
    });
  }
}
