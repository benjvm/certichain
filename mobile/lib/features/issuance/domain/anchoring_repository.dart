import '../../verification/domain/blockchain_verification.dart';

enum AnchorStatus {
  requested,
  prepared,
  submitted,
  included,
  confirmed,
  reorged,
  blocked,
  failed,
  divergence,
}

class AnchorOperation {
  const AnchorOperation(this.id, this.status);
  final String id;
  final AnchorStatus status;
  bool get canReauthorize =>
      status == AnchorStatus.blocked || status == AnchorStatus.failed;
}

class AnchorScope {
  const AnchorScope(this.userId, this.institutionId, this.certificateId);
  final String userId, institutionId, certificateId;
  @override
  bool operator ==(Object other) =>
      other is AnchorScope &&
      userId == other.userId &&
      institutionId == other.institutionId &&
      certificateId == other.certificateId;
  @override
  int get hashCode => Object.hash(userId, institutionId, certificateId);
}

class AnchorReceipt {
  const AnchorReceipt(this.key, this.createdAt, {this.operation});
  final String key;
  final DateTime createdAt;
  final AnchorOperation? operation;
}

class AnchoringException implements Exception {
  const AnchoringException(this.code, {this.retryAfter});
  final String code;
  final Duration? retryAfter;
}

abstract interface class AnchoringRepository {
  Future<AnchorOperation> request(AnchorScope scope, String key);
  Future<AnchorOperation> progress(AnchorScope scope, String operationId);
  Future<AnchorOperation> reauthorize(AnchorScope scope, String operationId);
  void cancel(AnchorScope scope);
}

abstract interface class AnchorReceiptStore {
  Future<AnchorReceipt?> read(AnchorScope scope);
  Future<void> save(AnchorScope scope, AnchorReceipt receipt);
}

abstract interface class OpeningRepository {
  Future<CertificateOpening> obtain(String userId, String certificateId);
  void cancelOpening(String userId, String certificateId);
}

abstract interface class OpeningTransfer {
  String serialize(CertificateOpening opening);
  Future<bool> export(CertificateOpening opening);
}
