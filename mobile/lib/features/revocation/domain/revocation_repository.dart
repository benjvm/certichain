class RevocationScope {
  const RevocationScope(this.userId, this.institutionId, this.certificateId);
  final String userId, institutionId, certificateId;
  @override
  bool operator ==(Object other) =>
      other is RevocationScope &&
      other.userId == userId &&
      other.institutionId == institutionId &&
      other.certificateId == certificateId;
  @override
  int get hashCode => Object.hash(userId, institutionId, certificateId);
}

enum RevocationSyncStatus {
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

class RevocationSync {
  const RevocationSync(this.operationId, this.status);
  final String operationId;
  final RevocationSyncStatus status;
}

class RevocationDecision {
  const RevocationDecision({
    required this.certificateId,
    required this.requestId,
    required this.revokedAt,
    required this.reason,
    required this.synchronization,
  });
  final String certificateId;
  final String? requestId, reason;
  final DateTime? revokedAt;
  final List<RevocationSync> synchronization;
  bool get revoked => revokedAt != null;
}

class RevocationException implements Exception {
  const RevocationException(this.code);
  final String code;
}

abstract interface class RevocationRepository {
  Future<RevocationDecision> request(
    RevocationScope scope,
    String key,
    String reason,
  );
  Future<RevocationDecision> progress(RevocationScope scope);
  Future<RevocationDecision> reauthorize(
    RevocationScope scope,
    String operationId,
  );
  void cancel(RevocationScope scope);
}

abstract interface class RevocationKeyStore {
  Future<String> obtain(RevocationScope scope);
}
