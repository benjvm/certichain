import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/auth_repository.dart';
import 'auth_messages.dart';

enum AuthStatus { initializing, unauthenticated, authenticated, error }

class AuthController extends ChangeNotifier {
  AuthController(this.repository) {
    _subscription = repository.sessionChanges.listen(
      (session) {
        if (!signingOut) _accept(session);
      },
      onError: (Object error, StackTrace stack) {
        if (_disposed || signingOut) return;
        status = AuthStatus.error;
        session = null;
        message = authMessage(error);
        notifyListeners();
      },
    );
    _accept(repository.currentSession);
  }

  final AuthRepository repository;
  late final StreamSubscription<AuthSession?> _subscription;
  Timer? _expiry;
  bool _disposed = false;
  bool signingOut = false;
  AuthStatus status = AuthStatus.initializing;
  AuthSession? session;
  String? message;

  void _accept(AuthSession? value) {
    if (_disposed) return;
    _expiry?.cancel();
    session = value;
    message = null;
    status = value == null
        ? AuthStatus.unauthenticated
        : value.isValid
        ? AuthStatus.authenticated
        : AuthStatus.initializing;
    if (value != null && value.isValid) {
      _expiry = Timer(
        value.expiresAt.difference(DateTime.now()),
        () => _accept(repository.currentSession),
      );
    }
    notifyListeners();
  }

  void inspectSession() => _accept(repository.currentSession);

  /// Backend 401 invalidates every visible route immediately.
  void requireSignIn() {
    _accept(null);
    unawaited(repository.signOut().catchError((Object _) {}));
  }

  Future<void> signOut() async {
    if (signingOut || _disposed) return;
    signingOut = true;
    message = null;
    notifyListeners();
    Object? failure;
    try {
      await repository.signOut();
    } catch (error) {
      failure = error;
    }
    if (_disposed) return;
    signingOut = false;
    _accept(repository.currentSession);
    if (failure != null) {
      message = authMessage(failure);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
