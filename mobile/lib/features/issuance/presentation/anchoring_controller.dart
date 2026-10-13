import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/anchoring_repository.dart';
import '../domain/issuance_repository.dart';

class AnchoringController extends ChangeNotifier {
  AnchoringController(this.scope, this.repository, this.store);
  final AnchorScope scope;
  final AnchoringRepository repository;
  final AnchorReceiptStore store;
  AnchorReceipt? receipt;
  AnchoringException? error;
  bool busy = false, ready = false, _disposed = false;
  int _generation = 0;
  DateTime? _retryAt;
  Timer? _retryTimer;
  bool get canAct =>
      ready &&
      !busy &&
      (_retryAt == null || !DateTime.now().isBefore(_retryAt!));
  Future<void> load() async {
    final generation = ++_generation;
    ready = false;
    error = null;
    notifyListeners();
    try {
      final r = await store.read(scope);
      if (_disposed || generation != _generation) return;
      receipt = r;
      ready = true;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = const AnchoringException('receipt_failure');
    }
    if (!_disposed) notifyListeners();
  }

  void invalidate() {
    _generation++;
    repository.cancel(scope);
    busy = false;
    ready = false;
    receipt = null;
    error = null;
    _retryAt = null;
    _retryTimer?.cancel();
    if (!_disposed) notifyListeners();
  }

  Future<void> request() => _run('request');
  Future<void> progress() => _run('progress');
  Future<void> reauthorize() => _run('reauthorize');
  Future<void> _run(String action) async {
    if (!canAct || _disposed) return;
    final op = receipt?.operation;
    if (action != 'request' && op == null) return;
    if (action == 'reauthorize' && !op!.canReauthorize) return;
    if (action == 'request' && op != null) return;
    busy = true;
    error = null;
    final generation = ++_generation;
    notifyListeners();
    bool current() => !_disposed && generation == _generation;
    try {
      final r =
          receipt ?? AnchorReceipt(newAttemptKey(), DateTime.now().toUtc());
      // Freeze and retain the key even if persisting or HTTP fails.
      receipt = r;
      await store.save(scope, r);
      if (!current()) return;
      final result = await switch (action) {
        'request' => repository.request(scope, r.key),
        'progress' => repository.progress(scope, op!.id),
        _ => repository.reauthorize(scope, op!.id),
      };
      if (!current()) return;
      final updated = AnchorReceipt(r.key, r.createdAt, operation: result);
      await store.save(scope, updated);
      if (!current()) return;
      receipt = updated;
    } catch (e) {
      if (!current()) return;
      error = e is AnchoringException
          ? e
          : const AnchoringException('temporary_failure');
      if (error?.retryAfter case final wait?) {
        _retryAt = DateTime.now().add(wait);
        _retryTimer?.cancel();
        _retryTimer = Timer(wait, () {
          if (!_disposed) notifyListeners();
        });
      }
    }
    if (!current()) return;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _retryTimer?.cancel();
    repository.cancel(scope);
    receipt = null;
    super.dispose();
  }
}
