import 'blockchain_verification.dart';

String? normalizeCredentialCode(String input) {
  final code = input.trim().toLowerCase();
  return code.length == 36 &&
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(code)
      ? code
      : null;
}

enum VerificationStatus { valid, revoked, expired, issuerUnavailable, notFound }

/// Server classification. Never inferred from the device clock.
class VerificationResult {
  const VerificationResult(this.status, {this.record, this.blockchain});
  final VerificationStatus status;
  final VerifiedRecord? record;
  final BlockchainEvidence? blockchain;
}

class VerifiedRecord {
  const VerifiedRecord({
    required this.code,
    required this.title,
    required this.issuer,
    required this.issuedAt,
    required this.expiresAt,
    required this.checkedAt,
  });
  final String code, title, issuer;
  final DateTime issuedAt, checkedAt;
  final DateTime? expiresAt;
}

enum VerificationFailure {
  invalidInput,
  network,
  timeout,
  rateLimited,
  unavailable,
  unexpected,
}

class VerificationException implements Exception {
  const VerificationException(this.failure, {this.retryAfter});
  final VerificationFailure failure;
  final Duration? retryAfter;
}

abstract interface class VerificationRepository {
  Future<VerificationResult> verify(String code);
}

/// The public route owns its in-flight operations, independently of Auth.
abstract interface class CancellablePublicQueries {
  void cancelPending();
}

/// Authorized own certificate only; null means no shareable publication evidence.
abstract interface class CredentialRepository {
  Future<String?> readOwnCode(String holderId, String certificateId);
}
