import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  static AuthSession? _session(Session? session) => session == null
      ? null
      : AuthSession(
          userId: session.user.id,
          email: session.user.email,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            (session.expiresAt ?? 0) * 1000,
          ),
        );

  @override
  AuthSession? get currentSession => _session(_client.auth.currentSession);

  @override
  Stream<AuthSession?> get sessionChanges => _client.auth.onAuthStateChange
      .map((state) => _session(state.session))
      .transform(
        StreamTransformer.fromHandlers(
          handleError:
              (Object error, StackTrace stack, EventSink<AuthSession?> sink) {
                sink.addError(mapFailure(error));
              },
        ),
      );

  @override
  Future<SignupOutcome> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
      );
      if (_session(response.session)?.isValid ?? false) {
        return SignupOutcome.authenticated;
      }
      if (response.user != null) return SignupOutcome.confirmationRequired;
      throw AuthFailure.registrationRejected;
    } catch (error) {
      throw mapFailure(error, registration: true);
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (!(_session(response.session)?.isValid ?? false)) {
        throw AuthFailure.invalidCredentials;
      }
    } catch (error) {
      throw mapFailure(error);
    }
  }

  @override
  Future<void> signOut() async {
    final previous = _client.auth.currentSession;
    try {
      await _client.auth.signOut();
    } catch (error) {
      // SDK 2.17 clears local state BEFORE the remote logout request. Restore
      // through the SDK on failure; the gate buffers events during logout.
      // Never persist tokens separately or log this snapshot.
      if (previous != null && !previous.isExpired) {
        await _client.auth.setInitialSession(jsonEncode(previous.toJson()));
      }
      throw mapFailure(error);
    }
  }

  /// Stable categories only: raw messages, SQL and metadata never leave data.
  static AuthFailure mapFailure(Object error, {bool registration = false}) {
    if (error is AuthFailure) return error;
    if (error is TimeoutException) return AuthFailure.timeout;
    if (error is AuthUnknownException &&
        error.originalError is TimeoutException) {
      return AuthFailure.timeout;
    }
    if (error is AuthException) {
      if (error.statusCode == '429') return AuthFailure.rateLimited;
      if (error.statusCode == '408' ||
          error.statusCode == '504' ||
          error.code == 'request_timeout') {
        return AuthFailure.timeout;
      }
      switch (error.code) {
        case 'invalid_credentials':
        case 'email_not_confirmed':
          return AuthFailure.invalidCredentials;
        case 'weak_password':
          return AuthFailure.weakPassword;
        case 'email_address_invalid':
        case 'email_address_not_authorized':
          return AuthFailure.invalidEmail;
        case 'over_request_rate_limit':
        case 'over_email_send_rate_limit':
          return AuthFailure.rateLimited;
        case 'unexpected_failure':
          if (registration) return AuthFailure.profileProvisioning;
      }
      if (registration && error.statusCode == '500') {
        return AuthFailure.profileProvisioning;
      }
      if (error is AuthRetryableFetchException) return AuthFailure.network;
      if (registration) return AuthFailure.registrationRejected;
    }
    return AuthFailure.unknown;
  }
}
