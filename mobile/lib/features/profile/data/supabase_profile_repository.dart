import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile_repository.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<UserProfile?> readProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select('id,full_name,role')
        .eq('id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 20));
    if (row == null) return null;
    final profile = UserProfile(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      role: row['role'] as String,
    );
    if (profile.id != userId || profile.fullName.trim().isEmpty) {
      throw const FormatException('Invalid profile');
    }
    return profile;
  }
}
