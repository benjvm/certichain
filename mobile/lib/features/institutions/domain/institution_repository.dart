import '../../certificates/domain/certificate_repository.dart';

enum InstitutionalRole { owner, admin, issuer }

enum InstitutionStatus { pending, verified, rejected, suspended }

class InstitutionMembership {
  const InstitutionMembership({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
  });
  final String id;
  final String name;
  final InstitutionalRole role;
  final InstitutionStatus status;
  bool get canIssue => status == InstitutionStatus.verified;
  String get statusLabel => switch (status) {
    InstitutionStatus.pending => 'Pendiente de aprobación',
    InstitutionStatus.verified => 'Verificada',
    InstitutionStatus.rejected => 'Solicitud rechazada',
    InstitutionStatus.suspended => 'Suspendida',
  };
  String get blockReason => switch (status) {
    InstitutionStatus.pending =>
      'La institución debe ser aprobada antes de emitir.',
    InstitutionStatus.rejected =>
      'La solicitud fue rechazada. Contacta con administración.',
    InstitutionStatus.suspended =>
      'La institución está suspendida y no puede emitir.',
    InstitutionStatus.verified => '',
  };
}

abstract interface class InstitutionRepository {
  Future<List<InstitutionMembership>> readMemberships(String userId);

  /// Session/RLS scoped, with an explicit institution filter and stable order.
  Future<CertificateWallet> readIssued(String institutionId);
}
