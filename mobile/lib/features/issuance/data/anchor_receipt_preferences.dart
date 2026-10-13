import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/files/strict_json.dart';
import '../domain/anchoring_repository.dart';
import '../domain/issuance_repository.dart';

/// Only scope IDs, idempotency key, real operation/status and creation date.
class AnchorReceiptPreferences implements AnchorReceiptStore {
  static const prefix = 'certichain.anchor.v1.';
  String _key(AnchorScope s) =>
      '$prefix${s.userId}.${s.institutionId}.${s.certificateId}';
  Future<SharedPreferences> _prune() async {
    final prefs = await SharedPreferences.getInstance();
    final receipts = <(String, DateTime)>[];
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      try {
        final data = decodeStrictJson(
          prefs.getString(key)!,
          maxBytes: 1024,
        ) as Map<String, Object?>;
        final created = DateTime.parse(data['created']! as String);
        if (created.isAfter(DateTime.now()) ||
            DateTime.now().difference(created) > const Duration(days: 7)) {
          await prefs.remove(key);
        } else {
          receipts.add((key, created));
        }
      } catch (_) {
        await prefs.remove(key);
      }
    }
    receipts.sort((a, b) => b.$2.compareTo(a.$2));
    for (final r in receipts.skip(20)) {
      await prefs.remove(r.$1);
    }
    return prefs;
  }

  @override
  Future<AnchorReceipt?> read(AnchorScope scope) async {
    final raw = (await _prune()).getString(_key(scope));
    if (raw == null) return null;
    try {
      final v = closedObject(decodeStrictJson(raw, maxBytes: 1024), {
        'key',
        'created',
        'operation_id',
        'status',
      });
      if (v['key'] is! String || !isUuid(v['key']! as String)) {
        throw const FormatException();
      }
      AnchorOperation? operation;
      if (v['operation_id'] != null) {
        if (v['operation_id'] is! String ||
            !isUuid(v['operation_id']! as String)) {
          throw const FormatException();
        }
        operation = AnchorOperation(
          v['operation_id']! as String,
          AnchorStatus.values.byName(v['status']! as String),
        );
      } else if (v['status'] != null) {
        throw const FormatException();
      }
      return AnchorReceipt(
        v['key']! as String,
        DateTime.parse(v['created']! as String),
        operation: operation,
      );
    } catch (_) {
      throw const AnchoringException('receipt_failure');
    }
  }

  @override
  Future<void> save(AnchorScope scope, AnchorReceipt receipt) async {
    final prefs = await _prune();
    if (!await prefs.setString(
      _key(scope),
      jsonEncode({
        'key': receipt.key,
        'created': receipt.createdAt.toUtc().toIso8601String(),
        'operation_id': receipt.operation?.id,
        'status': receipt.operation?.status.name,
      }),
    )) {
      throw const AnchoringException('receipt_failure');
    }
    await _prune();
  }
}
