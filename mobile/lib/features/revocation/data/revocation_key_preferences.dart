import 'package:shared_preferences/shared_preferences.dart';

import '../../issuance/domain/issuance_repository.dart';

import '../domain/revocation_repository.dart';

/// A recovery key only. Never reason, JWT or audit in preferences.
class RevocationKeyPreferences implements RevocationKeyStore {
  @override
  Future<String> obtain(RevocationScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    final name =
        'revocation-key:${scope.userId}:${scope.institutionId}:${scope.certificateId}';
    final stored = prefs.getString(name);
    if (stored != null && isUuid(stored)) return stored;
    final key = newAttemptKey();
    if (!await prefs.setString(name, key)) {
      throw const RevocationException('temporary_failure');
    }
    return key;
  }
}
