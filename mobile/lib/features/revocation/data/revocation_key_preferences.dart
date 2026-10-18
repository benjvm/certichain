import 'package:shared_preferences/shared_preferences.dart';

import '../../issuance/domain/issuance_repository.dart';

import '../domain/revocation_repository.dart';

/// A recovery key only. Never reason, JWT or audit in preferences.
class RevocationKeyPreferences implements RevocationKeyStore {
  static final _pending = <RevocationScope, Future<String>>{};
  @override
  Future<String> obtain(RevocationScope scope) =>
      _pending.putIfAbsent(scope, () async {
        try {
          return await _obtain(scope);
        } finally {
          _pending.remove(scope);
        }
      });

  Future<String> _obtain(RevocationScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    final name =
        'revocation-key:${scope.userId}:${scope.institutionId}:${scope.certificateId}';
    final stored = prefs.getString(name);
    if (stored != null) {
      if (!isUuid(stored)) throw const RevocationException('receipt_failure');
      return stored;
    }
    final key = newAttemptKey();
    if (!await prefs.setString(name, key)) {
      throw const RevocationException('temporary_failure');
    }
    return key;
  }
}
