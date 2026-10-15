enum PublicRevocationState {
  notRequested,
  notApplicable,
  pending,
  blocked,
  included,
  confirmed,
  reorged,
  unavailable,
  divergence,
}

class PublicRevocationReceipt {
  const PublicRevocationReceipt({
    required this.hash,
    required this.blockNumber,
    required this.blockHash,
    required this.checkedAt,
    this.revokedAt,
    this.confirmations,
    this.finality,
  });
  final String hash, blockNumber, blockHash;
  final DateTime checkedAt;
  final DateTime? revokedAt;
  final String? confirmations, finality;
}

class PublicRevocation {
  const PublicRevocation({
    required this.state,
    required this.revokedAt,
    required this.checkedAt,
    required this.source,
    required this.evidence,
    required this.previous,
  });
  final PublicRevocationState state;
  final DateTime? revokedAt;
  final DateTime checkedAt;
  final String source;
  final PublicRevocationReceipt? evidence, previous;
}
