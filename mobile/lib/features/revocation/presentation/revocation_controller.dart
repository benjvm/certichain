import 'package:flutter/foundation.dart';

import '../domain/revocation_repository.dart';
import '../domain/revocation_reason.dart';

class RevocationController extends ChangeNotifier {
  RevocationController(this.scope, this.repository, this.keys);
  final RevocationScope scope;
  final RevocationRepository repository;
  final RevocationKeyStore keys;
  RevocationDecision? decision;
  String? error, _reason, _key;
  bool busy = false, _disposed = false;
  bool accessDenied = false, uncertain = false;
  int _generation = 0;
  bool get frozen => _reason != null;
  Future<void> request(String reason) => _run(() async {
    if (_reason == null) {
      if (revocationReasonError(reason) != null) {
        throw const RevocationException('invalid_input');
      }
      _reason = normalizeRevocationReason(reason);
    }
    final generation = _generation;
    final key = _key ?? await keys.obtain(scope);
    if (_disposed || generation != _generation) {
      throw const RevocationException('stale_session');
    }
    _key = key;
    // Any lost/malformed response after POST can hide an accepted SQL decision.
    uncertain = true;
    return repository.request(scope, _key!, _reason!);
  });
  Future<void> refresh() => _run(() => repository.progress(scope));
  Future<void> reauthorize(String id) =>
      _run(() => repository.reauthorize(scope, id));
  Future<void> _run(Future<RevocationDecision> Function() action) async {
    if (busy || _disposed || accessDenied) return;
    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await action();
      if (_disposed || generation != _generation) return;
      decision = result;
      uncertain = false;
      if (result.revoked) _reason = null;
    } on RevocationException catch (e) {
      if (_disposed || generation != _generation) return;
      error = e.code;
      if ([
        'unauthenticated',
        'stale_session',
        'revocation_unavailable',
        'authorization_denied',
      ].contains(error)) {
        accessDenied = true;
        decision = null;
        _reason = null;
        _key = null;
        uncertain = false;
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = 'temporary_failure';
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void invalidate() {
    ++_generation;
    repository.cancel(scope);
    decision = null;
    error = null;
    accessDenied = false;
    uncertain = false;
    _reason = null;
    _key = null;
    busy = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    invalidate();
    super.dispose();
  }
}
