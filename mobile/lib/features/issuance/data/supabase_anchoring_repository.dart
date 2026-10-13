import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/files/strict_json.dart';
import '../../verification/data/blockchain_models.dart';
import '../../verification/domain/blockchain_verification.dart';
import '../domain/anchoring_repository.dart';
import '../domain/issuance_repository.dart';

class SupabaseAnchoringRepository
    implements AnchoringRepository, OpeningRepository {
  SupabaseAnchoringRepository(
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
      throw const AnchoringException('unauthenticated');
    }
    return s.accessToken;
  }

  void _cancel(Object scope) {
    for (final abort in _pending[scope] ?? <Completer<void>>{}) {
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  void cancel(AnchorScope scope) => _cancel(scope);
  @override
  void cancelOpening(String userId, String certificateId) =>
      _cancel((userId, certificateId));
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
            throw const AnchoringException('temporary_failure');
          }
          bytes.addAll(chunk);
        }
        if (abort.isCompleted || _token(user) != token) {
          throw const AnchoringException('stale_session');
        }
        if (response.statusCode == 401) {
          throw const AnchoringException('unauthenticated');
        }
        if (response.statusCode == 429) {
          throw AnchoringException(
            'rate_limited',
            retryAfter: Duration(
              seconds:
                  int.tryParse(response.headers['retry-after'] ?? '') ?? 60,
            ),
          );
        }
        final data = decodeStrictJson(utf8.decode(bytes));
        if (response.statusCode != 200 && response.statusCode != 202) {
          final error = closedObject(data, {'error'})['error'];
          final allowed = switch (response.statusCode) {
            400 => {'invalid_input'},
            403 => {'authorization_denied'},
            404 => {'publication_unavailable', 'opening_unavailable'},
            409 => {'idempotency_conflict', 'busy'},
            503 => {'temporary_failure'},
            _ => const <String>{},
          };
          throw AnchoringException(
            error is String && allowed.contains(error)
                ? error
                : 'temporary_failure',
          );
        }
        if (endpoint != 'anchor-certificate' && response.statusCode != 200) {
          throw const AnchoringException('temporary_failure');
        }
        return data;
      }

      return await query().timeout(timeout);
    } on AnchoringException {
      rethrow;
    } on TimeoutException {
      throw const AnchoringException('timeout');
    } on http.ClientException {
      throw const AnchoringException('network');
    } catch (_) {
      throw const AnchoringException('temporary_failure');
    } finally {
      if (!abort.isCompleted) abort.complete();
      _pending[scope]?.remove(abort);
      if (_pending[scope]?.isEmpty ?? false) _pending.remove(scope);
    }
  }

  Future<AnchorOperation> _operation(
    AnchorScope scope,
    String endpoint,
    Map<String, String> body, {
    String? expected,
  }) async {
    final v = closedObject(await _post(scope, scope.userId, endpoint, body), {
      'operation_id',
      'status',
    });
    if (v['operation_id'] is! String ||
        (v['operation_id']! as String).length != 36 ||
        !isUuid(v['operation_id']! as String) ||
        (expected != null && v['operation_id'] != expected)) {
      throw const AnchoringException('temporary_failure');
    }
    try {
      return AnchorOperation(
        v['operation_id']! as String,
        AnchorStatus.values.byName(v['status']! as String),
      );
    } catch (_) {
      throw const AnchoringException('temporary_failure');
    }
  }

  @override
  Future<AnchorOperation> request(AnchorScope scope, String key) => _operation(
    scope,
    'anchor-certificate',
    {'certificate_id': scope.certificateId, 'idempotency_key': key},
  );
  @override
  Future<AnchorOperation> progress(AnchorScope scope, String operationId) =>
      _operation(scope, 'anchor-progress', {
        'operation_id': operationId,
      }, expected: operationId);
  @override
  Future<AnchorOperation> reauthorize(AnchorScope scope, String operationId) =>
      _operation(scope, 'reauthorize-anchor', {
        'operation_id': operationId,
      }, expected: operationId);
  @override
  Future<CertificateOpening> obtain(
    String userId,
    String certificateId,
  ) async => decodeOpening(
    await _post(
      (userId, certificateId),
      userId,
      'certificate-opening',
      {'certificate_id': certificateId},
    ),
  );
}
