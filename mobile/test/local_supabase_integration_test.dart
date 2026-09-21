import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mobile/features/auth/data/supabase_auth_repository.dart';
import 'package:mobile/features/auth/domain/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Opt-in: run only against the local stack using synthetic data. Ordinary
// flutter test never contacts a server.
void main() {
  const enabled = bool.fromEnvironment('RUN_LOCAL_SUPABASE');
  TestWidgetsFlutterBinding.ensureInitialized();
  const preferencesChannel = MethodChannel(
    'plugins.flutter.io/shared_preferences',
  );
  final preferences = <String, Object>{};

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferencesChannel, (call) async {
          final args = call.arguments as Map?;
          switch (call.method) {
            case 'getAll':
              return Map<String, Object>.of(preferences);
            case 'setString':
              preferences[args!['key'] as String] = args['value'] as String;
              return true;
            case 'remove':
              preferences.remove(args!['key'] as String);
              return true;
            default:
              throw MissingPluginException('Unsupported preferences method');
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferencesChannel, null);
    preferences.clear();
  });
  test(
    'real SDK registration, logout, login and persisted session recovery',
    skip: !enabled ? 'Requires local Supabase and Dart defines' : null,
    () async {
      // Flutter's VM test binding replaces HttpClient with a 400 stub.
      // This opt-in test deliberately contacts only the configured local API.
      HttpOverrides.global = null;
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final email = 'phase4b-sdk-$suffix@example.com';
      final password = 'T4b-$suffix';
      final first = await Supabase.initialize(
        url: const String.fromEnvironment('SUPABASE_URL'),
        publishableKey: const String.fromEnvironment(
          'SUPABASE_PUBLISHABLE_KEY',
        ),
        debug: false,
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      );
      var repository = SupabaseAuthRepository(first.client);
      try {
        expect(
          await repository.signUp(
            fullName: '  SDK Test  ',
            email: email,
            password: password,
          ),
          SignupOutcome.authenticated,
        );
        expect(repository.currentSession?.isValid, isTrue);
        await repository.signOut();
        expect(repository.currentSession, isNull);
        await repository.signIn(email: email, password: password);
        expect(repository.currentSession?.isValid, isTrue);
        // The SDK persists the signed-in session; recreating it simulates app
        // startup without introducing a second persistence mechanism.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await first.dispose();
        final restored = await Supabase.initialize(
          url: const String.fromEnvironment('SUPABASE_URL'),
          publishableKey: const String.fromEnvironment(
            'SUPABASE_PUBLISHABLE_KEY',
          ),
          debug: false,
          authOptions: const FlutterAuthClientOptions(
            detectSessionInUri: false,
          ),
        );
        repository = SupabaseAuthRepository(restored.client);
        // Supabase.initialize starts a background recoverSession operation.
        // Let it settle before testing a subsequent user-initiated logout.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(repository.currentSession?.isValid, isTrue);
        expect(repository.currentSession?.email, email);
        await repository.signOut();
        expect(repository.currentSession, isNull);
        await restored.dispose();
      } finally {
        if (first.isInitialized) await first.dispose();
      }
    },
  );
}
