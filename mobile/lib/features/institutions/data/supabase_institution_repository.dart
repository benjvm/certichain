import 'package:supabase_flutter/supabase_flutter.dart';

import '../../certificates/data/supabase_certificate_repository.dart';
import '../../certificates/domain/certificate_repository.dart';
import '../domain/institution_repository.dart';

class SupabaseInstitutionRepository implements InstitutionRepository {
  SupabaseInstitutionRepository(this._client);
  final SupabaseClient _client;
  void _ownSession(String userId) {
    final session = _client.auth.currentSession;
    if (session == null || session.user.id != userId || session.isExpired) {
      throw const FormatException('Invalid membership session');
    }
  }

  @override
  Future<List<InstitutionMembership>> readMemberships(String userId) async {
    _ownSession(userId);
    final rows = await _client
        .from('institution_members')
        .select('user_id,role,institutions!inner(id,name,verification_status)')
        .eq('user_id', userId)
        .order('institution_id')
        .timeout(const Duration(seconds: 20));
    _ownSession(userId);
    return rows
        .map((row) {
          if (row['user_id'] != userId) {
            throw const FormatException('Invalid membership identity');
          }
          final institution = row['institutions'] as Map<String, dynamic>;
          return InstitutionMembership(
            id: institution['id'] as String,
            name: institution['name'] as String,
            role: InstitutionalRole.values.byName(row['role'] as String),
            status: InstitutionStatus.values.byName(
              institution['verification_status'] as String,
            ),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<CertificateWallet> readIssued(String institutionId) async {
    final result = await _client
        .from('certificates')
        .select('id,holder_id,institution_id,title,issued_at,expires_at,status')
        .eq('institution_id', institutionId)
        .order('issued_at', ascending: false)
        .order('id', ascending: false)
        .limit(CertificateRepository.walletLimit)
        .count(CountOption.exact)
        .timeout(const Duration(seconds: 20));
    final certificates = result.data
        .map(SupabaseCertificateRepository.fromRow)
        .toList();
    if (certificates.any((c) => c.institutionId != institutionId)) {
      throw const FormatException('Invalid institution identity');
    }
    return CertificateWallet(certificates: certificates, total: result.count);
  }
}
