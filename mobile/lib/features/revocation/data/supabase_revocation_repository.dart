import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/files/strict_json.dart';
import '../../issuance/domain/issuance_repository.dart';
import '../../verification/data/http_verification_repository.dart';
import '../domain/revocation_repository.dart';
import '../domain/revocation_reason.dart';

class SupabaseRevocationRepository implements RevocationRepository {
  SupabaseRevocationRepository(
    this.client, {
    required this.apiUrl,
    required this.publicKey,
    http.Client? transport,
    this.timeout = const Duration(seconds: 30),
  }) : transport = transport ?? http.Client();
  final SupabaseClient client;
  final String apiUrl, publicKey;
  final http.Client transport;
  final Duration timeout;
  final _pending = <Object, Set<Completer<void>>>{};
  String _token(String user) {
    final s = client.auth.currentSession;
    if (s == null || s.user.id != user || s.isExpired) {
      throw const RevocationException('unauthenticated');
    }
    return s.accessToken;
  }

  void _cancel(Object scope) {
    for (final abort in _pending[scope] ?? <Completer<void>>{}) {
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  void cancel(RevocationScope scope) => _cancel(scope);
  void close() {
    for (final s in _pending.keys.toList()) {
      _cancel(s);
    }
    transport.close();
  }

  Future<Object?> _post(
    Object scope,
    String user,
    String endpoint,
    Map<String, String> body,
  ) async {
    final token = _token(user), abort = Completer<void>();
    (_pending[scope] ??= <Completer<void>>{}).add(abort);
    try {
      Future<Object?> query() async {
        final request =
            http.AbortableRequest(
                'POST',
                Uri.parse('$apiUrl/functions/v1/$endpoint'),
                abortTrigger: abort.future,
              )
              ..followRedirects = false
              ..headers.addAll({
                'apikey': publicKey,
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              })
              ..body = jsonEncode(body);
        final response = await transport.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 16384) {
            throw const RevocationException('temporary_failure');
          }
          bytes.addAll(chunk);
        }
        if (abort.isCompleted || _token(user) != token) {
          throw const RevocationException('stale_session');
        }
        if (response.statusCode == 401) {
          throw const RevocationException('unauthenticated');
        }
        if (response.statusCode == 429) {
          throw const RevocationException('rate_limited');
        }
        final data = decodeStrictJson(utf8.decode(bytes));
        if (response.statusCode != 200 && response.statusCode != 202) {
          final error = closedObject(data, {'error'})['error'];
          final allowed = switch (response.statusCode) {
            400 => {'invalid_input'},
            413 => {'payload_too_large'},
            403 => {'authorization_denied'},
            404 => {'revocation_unavailable'},
            409 => {'idempotency_conflict', 'busy'},
            503 => {'temporary_failure'},
            _ => const <String>{},
          };
          throw RevocationException(
            error is String && allowed.contains(error)
                ? error
                : 'temporary_failure',
          );
        }
        if (endpoint != 'revoke-certificate' && response.statusCode != 200) {
          throw const RevocationException('temporary_failure');
        }
        return data;
      }

      return await query().timeout(timeout);
    } on RevocationException {
      rethrow;
    } on TimeoutException {
      throw const RevocationException('timeout');
    } on http.ClientException {
      throw const RevocationException('network');
    } catch (_) {
      throw const RevocationException('temporary_failure');
    } finally {
      if (!abort.isCompleted) abort.complete();
      _pending[scope]?.remove(abort);
      if (_pending[scope]?.isEmpty ?? false) _pending.remove(scope);
    }
  }

  Future<RevocationDecision> _decision(
    RevocationScope scope,
    String endpoint,
    Map<String, String> body,
  ) async {
    try {
      final v = closedObject(await _post(scope, scope.userId, endpoint, body), {
        'certificate_id',
        'request_id',
        'status',
        'revoked_at',
        'reason',
        'synchronization',
      });
      if (v['certificate_id'] != scope.certificateId ||
          !['active', 'revoked'].contains(v['status']) ||
          (v['request_id'] != null &&
              (v['request_id'] is! String ||
                  !isUuid(v['request_id']! as String))) ||
          (v['reason'] != null &&
              (v['reason'] is! String ||
                  revocationReasonError(v['reason']! as String) != null ||
                  normalizeRevocationReason(v['reason']! as String) !=
                      v['reason'])) ||
          (v['revoked_at'] != null &&
              (v['revoked_at'] is! String ||
                  DateTime.tryParse(v['revoked_at']! as String) == null)) ||
          ((v['status'] == 'revoked') != (v['revoked_at'] != null)) ||
          (v['reason'] != null && v['request_id'] == null) ||
          (v['status'] == 'active' &&
              (v['request_id'] != null || v['reason'] != null)) ||
          (v['request_id'] != null && v['reason'] == null) ||
          v['synchronization'] is! List<Object?>) {
        throw const RevocationException('temporary_failure');
      }
      final entries = v['synchronization']! as List<Object?>;
      if (entries.length > 32 ||
          (v['status'] == 'active' && entries.isNotEmpty)) {
        throw const RevocationException('temporary_failure');
      }
      final sync = <RevocationSync>[];
      final seen = <String>{};
      for (final raw in entries) {
        final item = closedObject(raw, {'operation_id', 'status'});
        if (item['operation_id'] is! String ||
            !isUuid(item['operation_id']! as String) ||
            !seen.add(item['operation_id']! as String)) {
          throw const RevocationException('temporary_failure');
        }
        sync.add(
          RevocationSync(
            item['operation_id']! as String,
            RevocationSyncStatus.values.byName(item['status']! as String),
          ),
        );
      }
      return RevocationDecision(
        certificateId: scope.certificateId,
        requestId: v['request_id'] as String?,
        revokedAt: v['revoked_at'] == null
            ? null
            : HttpVerificationRepository.decodeDate(v['revoked_at']),
        reason: v['reason'] as String?,
        synchronization: List.unmodifiable(sync),
      );
    } on RevocationException {
      rethrow;
    } catch (_) {
      throw const RevocationException('temporary_failure');
    }
  }

  @override
  Future<RevocationDecision> request(
    RevocationScope scope,
    String key,
    String reason,
  ) {
    if (revocationReasonError(reason) != null) {
      throw const RevocationException('invalid_input');
    }
    return _decision(scope, 'revoke-certificate', {
      'certificate_id': scope.certificateId,
      'idempotency_key': key,
      'reason': normalizeRevocationReason(reason),
    });
  }

  @override
  Future<RevocationDecision> progress(RevocationScope scope) => _decision(
    scope,
    'revocation-progress',
    {'certificate_id': scope.certificateId},
  );
  @override
  Future<RevocationDecision> reauthorize(
    RevocationScope scope,
    String operationId,
  ) =>
      _decision(scope, 'reauthorize-revocation', {'operation_id': operationId});
}
