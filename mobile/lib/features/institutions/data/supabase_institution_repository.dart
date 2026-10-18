import 'package:supabase_flutter/supabase_flutter.dart';

import '../../certificates/data/supabase_certificate_repository.dart';
import '../../certificates/domain/certificate_repository.dart';
import '../domain/institution_repository.dart';

class SupabaseInstitutionRepository implements InstitutionRepository {
  SupabaseInstitutionRepository(this._client);
  final SupabaseClient _client;
  Session _ownSession(String? userId, {String? accessToken}) {
    final session = _client.auth.currentSession;
    if (session == null ||
        (userId != null && session.user.id != userId) ||
        (accessToken != null && session.accessToken != accessToken) ||
        session.isExpired) {
      throw const FormatException('Invalid membership session');
    }
    return session;
  }

  @override
  Future<List<InstitutionMembership>> readMemberships(String userId) async {
    final session = _ownSession(userId);
    final rows = await _client
        .from('institution_members')
        .select('user_id,role,institutions!inner(id,name,verification_status)')
        .eq('user_id', userId)
        .order('institution_id')
        .timeout(const Duration(seconds: 20));
    _ownSession(userId, accessToken: session.accessToken);
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
    final session = _ownSession(null);
    final result = await _client
        .from('certificates')
        .select(
          'id,holder_id,institution_id,title,issued_at,expires_at,status,revoked_at',
        )
        .eq('institution_id', institutionId)
        .order('issued_at', ascending: false)
        .order('id', ascending: false)
        .limit(CertificateRepository.walletLimit)
        .count(CountOption.exact)
        .timeout(const Duration(seconds: 20));
    _ownSession(session.user.id, accessToken: session.accessToken);
    final certificates = result.data
        .map(SupabaseCertificateRepository.fromRow)
        .toList();
    if (certificates.any((c) => c.institutionId != institutionId)) {
      throw const FormatException('Invalid institution identity');
    }
    return CertificateWallet(certificates: certificates, total: result.count);
  }
}
