class AuthSession {
  const AuthSession({
    required this.userId,
    this.email,
    required this.expiresAt,
  });

  final String userId;
  final String? email;
  final DateTime expiresAt;
  bool get isValid => expiresAt.isAfter(DateTime.now());
}

enum SignupOutcome { authenticated, confirmationRequired }

enum AuthFailure implements Exception {
  invalidCredentials,
  weakPassword,
  invalidEmail,
  registrationRejected,
  profileProvisioning,
  network,
  timeout,
  rateLimited,
  unknown,
}

/// Only a real session grants entry. Account preferences are not authorization.
abstract interface class AuthRepository {
  AuthSession? get currentSession;
  Stream<AuthSession?> get sessionChanges;
  Future<SignupOutcome> signUp({
    required String fullName,
    required String email,
    required String password,
  });
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();
}
