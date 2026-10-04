import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/verification_repository.dart';

class VerificationController extends ChangeNotifier {
  VerificationController(this.repository);
  final VerificationRepository repository;
  String input = '';
  bool loading = false, _disposed = false;
  int _generation = 0;
  VerificationResult? result;
  VerificationFailure? failure;
  Timer? _timer;
  DateTime? _retryAt;
  int get waitSeconds {
    final ms = _retryAt?.difference(DateTime.now()).inMilliseconds ?? 0;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  bool get canSubmit => !loading && waitSeconds == 0;
  void changeCode(String value) {
    if (input == value || _disposed) return;
    input = value;
    _generation++;
    loading = false;
    result = null;
    if (failure != VerificationFailure.rateLimited) failure = null;
    notifyListeners();
  }

  Future<void> submit() async {
    if (!canSubmit || _disposed) return;
    final code = normalizeCredentialCode(input);
    result = null;
    failure = null;
    if (code == null) {
      failure = VerificationFailure.invalidInput;
      notifyListeners();
      return;
    }
    input = code;
    loading = true;
    final generation = ++_generation;
    notifyListeners();
    try {
      final response = await repository.verify(code);
      if (_disposed || generation != _generation) return;
      result = response;
    } catch (error) {
      if (_disposed) return;
      // A rate limit belongs to the public budget, even if its form was replaced.
      if (error is VerificationException &&
          error.failure == VerificationFailure.rateLimited) {
        final deadline = DateTime.now().add(
          error.retryAfter ?? const Duration(seconds: 60),
        );
        if (_retryAt == null || deadline.isAfter(_retryAt!)) {
          _retryAt = deadline;
        }
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (waitSeconds == 0) _timer?.cancel();
          if (!_disposed) notifyListeners();
        });
      }
      if (generation != _generation) {
        notifyListeners();
        return;
      }
      failure = error is VerificationException
          ? error.failure
          : VerificationFailure.unexpected;
    }
    if (_disposed || generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
