import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/certificate_repository.dart';

class SupabaseCertificateRepository implements CertificateRepository {
  SupabaseCertificateRepository(this._client);
  final SupabaseClient _client;
  static const _fields =
      'id,holder_id,institution_id,title,issued_at,expires_at,status,revoked_at,institutions(name)';

  @override
  Future<CertificateWallet> readWallet(String userId) async {
    // Left embedding preserves certificates when institution RLS hides the issuer.
    // RLS alone also permits institutional/admin reads: explicitly scope the wallet.
    final result = await _client
        .from('certificates')
        .select(_fields)
        .eq('holder_id', userId)
        .order('issued_at', ascending: false)
        .order('id', ascending: false)
        .limit(CertificateRepository.walletLimit)
        .count(CountOption.exact)
        .timeout(const Duration(seconds: 20));
    final certificates = result.data.map(fromRow).toList();
    if (certificates.any((certificate) => certificate.holderId != userId)) {
      throw const FormatException('Invalid wallet owner');
    }
    return CertificateWallet(certificates: certificates, total: result.count);
  }

  @override
  Future<Certificate?> readCertificate(
    String userId,
    String certificateId,
  ) async {
    final row = await _client
        .from('certificates')
        .select(_fields)
        .eq('holder_id', userId)
        .eq('id', certificateId)
        .maybeSingle()
        .timeout(const Duration(seconds: 20));
    if (row == null) return null;
    final certificate = fromRow(row);
    if (certificate.holderId != userId || certificate.id != certificateId) {
      throw const FormatException('Invalid certificate identity');
    }
    return certificate;
  }

  static Certificate fromRow(Map<String, dynamic> row) {
    final institution = row['institutions'] as Map<String, dynamic>?;
    return Certificate(
      id: row['id'] as String,
      holderId: row['holder_id'] as String,
      institutionId: row['institution_id'] as String,
      title: row['title'] as String,
      institutionName: institution?['name'] as String?,
      issuedAt: DateTime.parse(row['issued_at'] as String),
      revokedAt: row['revoked_at'] == null
          ? null
          : DateTime.parse(row['revoked_at'] as String),
      expiresAt: row['expires_at'] == null
          ? null
          : DateTime.parse(row['expires_at'] as String),
      status: switch (row['status']) {
        'active' => CertificateStatus.active,
        'revoked' => CertificateStatus.revoked,
        _ => throw const FormatException('Unknown certificate status'),
      },
    );
  }
}
