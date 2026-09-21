import 'dart:async';

import 'package:mobile/features/auth/domain/auth_repository.dart';

AuthSession testSession() => AuthSession(
  userId: 'synthetic-user',
  email: 'ana@example.com',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.currentSession});
  final events = StreamController<AuthSession?>.broadcast();
  @override
  AuthSession? currentSession;
  @override
  Stream<AuthSession?> get sessionChanges => events.stream;
  Completer<void>? request;
  AuthFailure? failure;
  bool confirmationRequired = false;
  bool authenticate = true;
  int loginCalls = 0;
  int signupCalls = 0;
  int logoutCalls = 0;
  String? name;
  String? email;
  String? password;

  void emit(AuthSession? value) {
    currentSession = value;
    events.add(value);
  }

  Future<void> _finish() async {
    await request?.future;
    if (failure case final error?) throw error;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    loginCalls++;
    this.email = email;
    this.password = password;
    await _finish();
    if (authenticate) emit(testSession());
  }

  @override
  Future<SignupOutcome> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    signupCalls++;
    name = fullName;
    this.email = email;
    this.password = password;
    await _finish();
    if (confirmationRequired) return SignupOutcome.confirmationRequired;
    emit(testSession());
    return SignupOutcome.authenticated;
  }

  @override
  Future<void> signOut() async {
    logoutCalls++;
    await _finish();
    emit(null);
  }
}
