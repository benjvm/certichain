import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/verification_repository.dart';

class SupabaseCredentialRepository implements CredentialRepository {
  SupabaseCredentialRepository(this._client);
  final SupabaseClient _client;
  Session _session(String holder, [String? token]) {
    final current = _client.auth.currentSession;
    if (current == null ||
        current.isExpired ||
        current.user.id != holder ||
        (token != null && current.accessToken != token)) {
      throw const FormatException('Invalid credential session');
    }
    return current;
  }

  @override
  Future<String?> readOwnCode(String holderId, String certificateId) async {
    final session = _session(holderId);
    final row = await _client
        .from('certificates')
        .select('id,holder_id,credential_code,issuance_operation_id')
        .eq('id', certificateId)
        .eq('holder_id', holderId)
        .maybeSingle()
        .timeout(const Duration(seconds: 20));
    _session(holderId, session.accessToken);
    if (row == null) return null;
    if (row['id'] != certificateId || row['holder_id'] != holderId) {
      throw const FormatException('Invalid credential owner');
    }
    // Linked publications have composite FK/check/inmutability evidence from 7B.
    // Legacy rows have no such link. No operations/profiles or technical RPC read.
    if (row['issuance_operation_id'] == null) return null;
    final raw = row['credential_code'];
    if (raw is! String ||
        normalizeCredentialCode(raw) != raw ||
        row['issuance_operation_id'] is! String) {
      throw const FormatException('Invalid public code');
    }
    return raw;
  }
}
