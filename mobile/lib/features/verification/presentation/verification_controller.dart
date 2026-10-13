import 'package:flutter/foundation.dart';

import '../domain/verification_repository.dart';
import '../domain/hash_comparison.dart';
import '../domain/blockchain_verification.dart';
import 'public_query_cooldown.dart';

class VerificationController extends ChangeNotifier {
  VerificationController(
    this.repository, {
    this.comparisonRepository,
    this.picker,
    this.hasher,
    PublicQueryCooldown? cooldown,
  }) : _cooldown = cooldown ?? PublicQueryCooldown(),
       _ownsCooldown = cooldown == null {
    _cooldown.addListener(_cooldownChanged);
  }
  final PublicQueryCooldown _cooldown;
  final bool _ownsCooldown;
  void _cooldownChanged() {
    if (!_disposed) notifyListeners();
  }

  final HashComparisonRepository? comparisonRepository;
  final ComparisonPdfPicker? picker;
  final PdfHasher? hasher;
  ComparisonPhase comparisonPhase = ComparisonPhase.idle;
  FileIntegrity? integrity;
  LocalPdfFailure? localPdfFailure;
  VerificationFailure? comparisonFailure;
  String? _candidateHash;
  int _fileGeneration = 0;
  bool get canCompare =>
      !loading &&
      waitSeconds == 0 &&
      result?.record != null &&
      comparisonRepository != null &&
      picker != null &&
      hasher != null &&
      comparisonPhase != ComparisonPhase.selecting;
  final VerificationRepository repository;
  String input = '';
  bool loading = false, _disposed = false;
  int _generation = 0;
  VerificationResult? result;
  bool resultIsPrevious = false;
  BlockchainEvidence? previousBlockchain;
  VerificationFailure? failure;
  int get waitSeconds => _cooldown.waitSeconds;

  bool get canSubmit => !loading && waitSeconds == 0;
  void changeCode(String value) {
    if (input == value || _disposed) return;
    input = value;
    _clearComparison();
    _generation++;
    loading = false;
    result = null;
    previousBlockchain = null;
    resultIsPrevious = false;
    if (failure != VerificationFailure.rateLimited) failure = null;
    notifyListeners();
  }

  Future<void> submit() async {
    if (!canSubmit || _disposed) return;
    final code = normalizeCredentialCode(input);
    final previous = result;
    resultIsPrevious = previous != null;
    failure = null;
    if (code == null) {
      result = null;
      failure = VerificationFailure.invalidInput;
      notifyListeners();
      return;
    }
    input = code;
    loading = true;
    _clearComparison();
    final generation = ++_generation;
    notifyListeners();
    try {
      final response = await repository.verify(code);
      if (_disposed || generation != _generation) return;
      result = response;
      resultIsPrevious = false;
      previousBlockchain = null;
    } catch (error) {
      // A rate limit belongs to the public budget, even if its form was replaced.
      if (error is VerificationException &&
          error.failure == VerificationFailure.rateLimited) {
        _rateLimit(error);
      }
      if (_disposed) return;
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

  void _rateLimit(VerificationException error) =>
      _cooldown.block(error.retryAfter ?? const Duration(seconds: 60));

  void _clearComparison() {
    _fileGeneration++;
    if (repository case final CancellablePublicQueries transport) {
      transport.cancelPending();
    }
    if (!identical(repository, comparisonRepository) &&
        comparisonRepository is CancellablePublicQueries) {
      (comparisonRepository as CancellablePublicQueries).cancelPending();
    }
    picker?.cancel();
    _candidateHash = null;
    integrity = null;
    comparisonFailure = null;
    localPdfFailure = null;
    comparisonPhase = ComparisonPhase.idle;
  }

  void cancelComparison() {
    if (_disposed) return;
    _clearComparison();
    comparisonPhase = ComparisonPhase.cancelled;
    notifyListeners();
  }

  Future<void> selectAndCompare() async {
    if (!canCompare || _disposed) return;
    _clearComparison();
    final fileGeneration = _fileGeneration, generation = _generation;
    final code = normalizeCredentialCode(input)!;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        fileGeneration == _fileGeneration;
    comparisonPhase = ComparisonPhase.selecting;
    notifyListeners();
    try {
      var bytes = await picker!.pick();
      if (!current()) return;
      if (bytes == null) {
        comparisonPhase = ComparisonPhase.cancelled;
        notifyListeners();
        return;
      }
      validateComparisonBytes(bytes.length);
      comparisonPhase = ComparisonPhase.hashing;
      notifyListeners();
      final digest = await hasher!.hash(bytes, isCancelled: () => !current());
      bytes = null;
      if (!current()) return;
      _candidateHash = digest;
      await _compare(code, generation, fileGeneration);
    } catch (error) {
      if (!current()) return;
      localPdfFailure = error is LocalPdfException
          ? error.failure
          : LocalPdfFailure.unreadable;
      comparisonPhase = ComparisonPhase.error;
      notifyListeners();
    }
  }

  Future<void> retryComparison() async {
    if (!canCompare ||
        _candidateHash == null ||
        _disposed ||
        comparisonPhase != ComparisonPhase.error) {
      return;
    }
    await _compare(
      normalizeCredentialCode(input)!,
      _generation,
      _fileGeneration,
    );
  }

  Future<void> _compare(String code, int generation, int fileGeneration) async {
    // A late 429 from a replaced operation may arrive while selecting/hashing.
    // Keep the candidate for explicit retry, but do not send during its wait.
    if (waitSeconds > 0) {
      comparisonFailure = VerificationFailure.rateLimited;
      comparisonPhase = ComparisonPhase.error;
      notifyListeners();
      return;
    }
    comparisonFailure = null;
    // The old timestamp belongs to the previous successful query. A pending
    // or failed comparison must never make that snapshot appear fresh.
    resultIsPrevious = true;
    comparisonPhase = ComparisonPhase.querying;
    notifyListeners();
    try {
      final response = await comparisonRepository!.compare(
        code,
        _candidateHash!,
      );
      if (_disposed ||
          generation != _generation ||
          fileGeneration != _fileGeneration) {
        return;
      }
      previousBlockchain = result?.blockchain ?? previousBlockchain;
      result = response.verification;
      resultIsPrevious = false;
      integrity = response.integrity;
      _candidateHash = null;
      comparisonPhase = ComparisonPhase.done;
    } catch (error) {
      if (error is VerificationException &&
          error.failure == VerificationFailure.rateLimited) {
        _rateLimit(error);
      }
      if (_disposed) return;
      if (generation != _generation || fileGeneration != _fileGeneration) {
        notifyListeners();
        return;
      }
      comparisonFailure = error is VerificationException
          ? error.failure
          : VerificationFailure.unexpected;
      comparisonPhase = ComparisonPhase.error;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clearComparison();
    _generation++;
    _cooldown.removeListener(_cooldownChanged);
    if (_ownsCooldown) _cooldown.dispose();
    super.dispose();
  }
}

enum ComparisonPhase {
  idle,
  selecting,
  hashing,
  querying,
  done,
  cancelled,
  error,
}
