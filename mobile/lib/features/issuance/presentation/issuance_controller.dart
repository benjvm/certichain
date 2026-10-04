import 'package:flutter/foundation.dart';

import '../domain/issuance_repository.dart';

class IssuanceController extends ChangeNotifier {
  IssuanceController({
    required this.userId,
    required this.institutionId,
    required this.repository,
    required this.store,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  DateTime get now => clock();
  final String userId;
  final String institutionId;
  final IssuanceRepository repository;
  final PendingAttemptStore store;
  PendingAttempt? pending;
  IssuanceRequest? request;
  IssuanceException? failure;
  String? certificateId;
  DateTime? retryAt;
  bool busy = false, ready = false, _disposed = false;
  bool get canRetry =>
      failure?.recoverable == true &&
      (retryAt == null || !now.isBefore(retryAt!));
  Future<void> restore() async {
    try {
      pending = await store.read(userId, institutionId);
      ready = true;
    } catch (_) {
      failure = const IssuanceException('receipt_failure');
    }
    _notify();
  }

  Future<void> submit(IssuanceData data, SelectedPdf pdf) async {
    if (busy ||
        !ready ||
        certificateId != null ||
        (failure != null && request != null && !canRetry)) {
      return;
    }
    busy = true;
    failure = null;
    _notify();
    try {
      final candidate =
          request ??
          IssuanceRequest(
            institutionId: institutionId,
            actorId: userId,
            key: pending?.key ?? newAttemptKey(),
            data: data,
            pdf: pdf,
          );
      if (pending != null && pending!.digest != candidate.digest) {
        throw const IssuanceException('reconstruction_mismatch');
      }
      final receipt =
          pending ??
          PendingAttempt(
            key: candidate.key,
            digest: candidate.digest,
            createdAt: now,
          );
      try {
        await store.save(userId, institutionId, receipt);
      } catch (_) {
        throw const IssuanceException('receipt_failure');
      }
      if (_disposed) return;
      pending = receipt;
      request = candidate;
      final id = await repository.issue(candidate);
      if (_disposed) return;
      certificateId = id;
      // A clear failure cannot turn confirmed success into a second emission.
      try {
        await store.clear(userId, institutionId);
        pending = null;
      } catch (_) {}
    } on IssuanceException catch (error) {
      if (!_disposed) {
        failure = error;
        if (error.recoverable) {
          retryAt = now.add(Duration(seconds: error.retryAfter));
        }
      }
    } catch (_) {
      if (!_disposed) {
        failure = const IssuanceException('response_lost');
        retryAt = now.add(const Duration(seconds: 120));
      }
    } finally {
      if (!_disposed) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> startNewDeliberately() async {
    if (busy) return;
    await store.clear(userId, institutionId);
    pending = null;
    request = null;
    certificateId = null;
    failure = null;
    retryAt = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
