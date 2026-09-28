enum CertificateStatus { active, revoked }

enum CertificateValidity { valid, revoked, expired }

class Certificate {
  const Certificate({
    required this.id,
    required this.holderId,
    required this.institutionId,
    required this.title,
    required this.issuedAt,
    required this.status,
    this.expiresAt,
    this.institutionName,
  });
  final String id;
  final String holderId;
  final String institutionId;
  final String title;
  final String? institutionName;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final CertificateStatus status;

  CertificateValidity validityAt(DateTime now) {
    if (status == CertificateStatus.revoked) return CertificateValidity.revoked;
    if (expiresAt != null && !expiresAt!.isAfter(now)) {
      return CertificateValidity.expired;
    }
    return CertificateValidity.valid;
  }
}

class CertificateWallet {
  CertificateWallet({
    required List<Certificate> certificates,
    required this.total,
  }) : certificates = List.unmodifiable(certificates);
  final List<Certificate> certificates;
  final int total;
}

abstract interface class CertificateRepository {
  static const walletLimit = 50;

  /// Newest issued first, at most walletLimit records and an exact holder total.
  Future<CertificateWallet> readWallet(String userId);

  /// Only the holder's certificate. Missing and inaccessible rows both return null.
  Future<Certificate?> readCertificate(String userId, String certificateId);
}
