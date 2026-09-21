import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/data/supabase_auth_repository.dart';
import 'package:mobile/features/auth/domain/auth_repository.dart';
import 'package:mobile/features/auth/presentation/auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// A loopback HTTP stub exercises the real SDK adapter, never a Supabase service.
void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseAuthRepository repository;
  late Map<String, dynamic> body;
  late int responseStatus;
  late Map<String, dynamic> response;
  final user = {
    'id': 'synthetic-id',
    'email': 'ana@example.com',
    'aud': 'authenticated',
    'created_at': '2026-01-01T00:00:00Z',
  };

  Map<String, dynamic> session() {
    final exp =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'exp': exp})))
        .replaceAll('=', '');
    return {
      'access_token': 'e30.$payload.signature',
      'refresh_token': 'synthetic-refresh',
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': user,
    };
  }

  setUp(() async {
    responseStatus = 200;
    response = session();
    body = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      if (text.isNotEmpty) body = jsonDecode(text) as Map<String, dynamic>;
      request.response.statusCode = responseStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    repository = SupabaseAuthRepository(client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'signup sends exactly full_name metadata and maps a real session',
    () async {
      final outcome = await repository.signUp(
        fullName: '  Ana García  ',
        email: ' ana@example.com ',
        password: 'test-password',
      );
      expect(body['data'], {'full_name': 'Ana García'});
      expect(body['email'], 'ana@example.com');
      expect(outcome, SignupOutcome.authenticated);
      expect(repository.currentSession?.userId, 'synthetic-id');
      expect(repository.currentSession?.isValid, isTrue);
    },
  );

  test(
    'user without session means confirmation, never authentication',
    () async {
      response = user;
      expect(
        await repository.signUp(
          fullName: 'Ana',
          email: 'ana@example.com',
          password: 'test-password',
        ),
        SignupOutcome.confirmationRequired,
      );
      expect(repository.currentSession, isNull);
    },
  );

  test('login and successful logout publish domain session events', () async {
    final events = <AuthSession?>[];
    final subscription = repository.sessionChanges.listen(events.add);
    await repository.signIn(
      email: ' ana@example.com ',
      password: 'test-password',
    );
    expect(body['email'], 'ana@example.com');
    await repository.signOut();
    await Future<void>.delayed(Duration.zero);
    expect(events.any((value) => value?.userId == 'synthetic-id'), isTrue);
    expect(events.last, isNull);
    expect(repository.currentSession, isNull);
    await subscription.cancel();
  });

  test(
    'SDK logout failure restores session and gate does not show Welcome',
    () async {
      await repository.signIn(
        email: 'ana@example.com',
        password: 'test-password',
      );
      final controller = AuthController(repository);
      final statuses = <AuthStatus>[];
      controller.addListener(() => statuses.add(controller.status));
      responseStatus = 429;
      response = {
        'code': 'over_request_rate_limit',
        'msg': 'sensitive internal payload',
      };
      await controller.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(repository.currentSession?.isValid, isTrue);
      expect(controller.status, AuthStatus.authenticated);
      expect(statuses, isNot(contains(AuthStatus.unauthenticated)));
      expect(controller.message, isNotNull);
      expect(controller.message, isNot(contains('sensitive')));
      controller.dispose();
    },
  );

  test('profile error becomes a safe category', () async {
    responseStatus = 500;
    response = {
      'code': 'unexpected_failure',
      'msg': 'SQL internal sensitive payload',
    };
    await expectLater(
      repository.signUp(
        fullName: 'Ana',
        email: 'ana@example.com',
        password: 'test-password',
      ),
      throwsA(AuthFailure.profileProvisioning),
    );
  });

  test('error mapping handles all required stable categories', () {
    final cases = <Object, AuthFailure>{
      const AuthException('private', code: 'invalid_credentials'):
          AuthFailure.invalidCredentials,
      const AuthException('private', code: 'weak_password'):
          AuthFailure.weakPassword,
      const AuthException('private', code: 'email_address_invalid'):
          AuthFailure.invalidEmail,
      const AuthException('private', statusCode: '429'):
          AuthFailure.rateLimited,
      AuthRetryableFetchException(): AuthFailure.network,
      TimeoutException('private'): AuthFailure.timeout,
      const AuthException('private', statusCode: '504'): AuthFailure.timeout,
      StateError('private'): AuthFailure.unknown,
    };
    for (final entry in cases.entries) {
      expect(SupabaseAuthRepository.mapFailure(entry.key), entry.value);
    }
    expect(
      SupabaseAuthRepository.mapFailure(
        const AuthException('private', code: 'signup_disabled'),
        registration: true,
      ),
      AuthFailure.registrationRejected,
    );
  });
}
