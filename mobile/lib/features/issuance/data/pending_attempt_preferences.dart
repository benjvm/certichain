import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/issuance_repository.dart';

/// Non-secret receipt only. No PDF, JWT, filenames or personal metadata.
class PendingAttemptPreferences implements PendingAttemptStore {
  static const _prefix = 'certichain.pending.v1.';
  static const retention = Duration(days: 7);
  static const maxReceipts = 20;
  String _key(String user, String institution) => '$_prefix$user.$institution';
  Future<SharedPreferences> _pruned() async {
    final prefs = await SharedPreferences.getInstance();
    final receipts = <(String, DateTime)>[];
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      try {
        final data = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
        final created = DateTime.parse(data['created'] as String);
        if (DateTime.now().difference(created) > retention ||
            created.isAfter(DateTime.now())) {
          await prefs.remove(key);
        } else {
          receipts.add((key, created));
        }
      } catch (_) {
        await prefs.remove(key);
      }
    }
    receipts.sort((a, b) => b.$2.compareTo(a.$2));
    for (final old in receipts.skip(maxReceipts)) {
      await prefs.remove(old.$1);
    }
    return prefs;
  }

  @override
  Future<PendingAttempt?> read(String userId, String institutionId) async {
    final raw = (await _pruned()).getString(_key(userId, institutionId));
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final key = data['key'] as String, digest = data['digest'] as String;
      if (!isUuid(key) || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
        throw const FormatException();
      }
      return PendingAttempt(
        key: key,
        digest: digest,
        createdAt: DateTime.parse(data['created'] as String),
      );
    } catch (_) {
      await clear(userId, institutionId);
      return null;
    }
  }

  @override
  Future<void> save(
    String userId,
    String institutionId,
    PendingAttempt attempt,
  ) async {
    final prefs = await _pruned();
    final saved = await prefs.setString(
      _key(userId, institutionId),
      jsonEncode({
        'key': attempt.key,
        'digest': attempt.digest,
        'created': attempt.createdAt.toUtc().toIso8601String(),
      }),
    );
    if (!saved) throw const IssuanceException('receipt_failure');
    await _pruned();
  }

  @override
  Future<void> clear(String userId, String institutionId) async {
    await (await SharedPreferences.getInstance()).remove(
      _key(userId, institutionId),
    );
  }
}
