import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/verification_repository.dart';
import '../domain/hash_comparison.dart';
import 'public_http_client.dart';
import '../../../core/files/strict_json.dart';
import 'blockchain_models.dart';

class HttpVerificationRepository
    implements
        VerificationRepository,
        HashComparisonRepository,
        CancellablePublicQueries {
  HttpVerificationRepository({
    required String apiUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.useV2 = false,
  }) : _endpoint = Uri.parse('$apiUrl/functions/v1/verify-certificate'),
       _client = client ?? createPublicHttpClient();
  final Uri _endpoint;
  final bool useV2;
  final http.Client _client;
  final _pendingAborts = <Completer<void>>{};
  @override
  void cancelPending() {
    for (final abort in _pendingAborts) {
      if (!abort.isCompleted) abort.complete();
    }
  }

  void close() {
    cancelPending();
    _client.close();
  }

  final Duration timeout;
  static const maxResponseBytes = 8192;

  @override
  Future<VerificationResult> verify(String input) => _run(
    input,
    decode: (value, code) =>
        useV2 ? decodeV2(value, code) : decodeResult(value, code),
  );

  @override
  Future<HashComparison> compare(String input, String documentSha256) {
    if (documentSha256.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(documentSha256)) {
      throw const VerificationException(VerificationFailure.invalidInput);
    }
    return _run(
      input,
      hash: documentSha256,
      decode: (value, code) {
        const unexpected = VerificationException(
          VerificationFailure.unexpected,
        );
        if (value is! Map<String, dynamic> ||
            value.length != 3 ||
            !value.keys.every(
              const {
                'schema_version',
                'verification',
                'file_integrity',
              }.contains,
            ) ||
            value['schema_version'] != '1') {
          throw unexpected;
        }
        final verification = decodeResult(value['verification'], code);
        final integrity = switch (value['file_integrity']) {
          'match' => FileIntegrity.match,
          'integrity_mismatch' => FileIntegrity.integrityMismatch,
          'unavailable' => FileIntegrity.unavailable,
          _ => throw unexpected,
        };
        if ((verification.status == VerificationStatus.notFound) !=
            (integrity == FileIntegrity.unavailable)) {
          throw unexpected;
        }
        return HashComparison(verification, integrity);
      },
    );
  }

  Future<T> _run<T>(
    String input, {
    String? hash,
    required T Function(Object?, String) decode,
  }) async {
    final code = normalizeCredentialCode(input);
    if (code == null) {
      throw const VerificationException(VerificationFailure.invalidInput);
    }
    final abort = Completer<void>();
    _pendingAborts.add(abort);
    try {
      return decode(
        await _query(code, abort.future, hash: hash).timeout(timeout),
        code,
      );
    } on VerificationException {
      rethrow;
    } on TimeoutException {
      throw const VerificationException(VerificationFailure.timeout);
    } on http.ClientException {
      throw const VerificationException(VerificationFailure.network);
    } catch (_) {
      throw const VerificationException(VerificationFailure.unexpected);
    } finally {
      if (!abort.isCompleted) abort.complete();
      _pendingAborts.remove(abort);
    }
  }

  Future<Object?> _query(
    String code,
    Future<void> abort, {
    String? hash,
  }) async {
    // Independent transport. Web explicitly omits even same-origin cookies.
    final request =
        http.AbortableRequest(
            'POST',
            hash == null
                ? (useV2
                      ? _endpoint.replace(
                          path: _endpoint.path.replaceFirst(
                            'verify-certificate',
                            'verify-certificate-v2',
                          ),
                        )
                      : _endpoint)
                : _endpoint.replace(
                    path: _endpoint.path.replaceFirst(
                      'verify-certificate',
                      'compare-certificate-hash',
                    ),
                  ),
            abortTrigger: abort,
          )
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({
            'credential_code': code,
            'document_sha256': ?hash,
          });
    final response = await _client.send(request);
    final bytes = <int>[];
    final subscription = response.stream;
    await for (final chunk in subscription) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const VerificationException(VerificationFailure.unexpected);
      }
      bytes.addAll(chunk);
    }
    switch (response.statusCode) {
      case 400:
        throw const VerificationException(VerificationFailure.invalidInput);
      case 429:
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        // v1 sends an integer. Missing/invalid headers fail conservatively with
        // a full window, never an immediate retry or an automatic loop.
        throw VerificationException(
          VerificationFailure.rateLimited,
          retryAfter: Duration(
            seconds: seconds != null && seconds > 0 ? seconds : 60,
          ),
        );
      case 503:
        throw const VerificationException(VerificationFailure.unavailable);
      case 200:
        return decodeStrictJson(utf8.decode(bytes));
      default:
        throw const VerificationException(VerificationFailure.unexpected);
    }
  }

  static VerificationResult decodeResult(Object? value, String requestedCode) {
    const unexpected = VerificationException(VerificationFailure.unexpected);
    if (value is! Map<String, dynamic> || value['schema_version'] != '1') {
      throw unexpected;
    }
    final status = switch (value['result']) {
      'valid' => VerificationStatus.valid,
      'revoked' => VerificationStatus.revoked,
      'expired' => VerificationStatus.expired,
      'issuer_unavailable' => VerificationStatus.issuerUnavailable,
      'not_found' => VerificationStatus.notFound,
      _ => throw unexpected,
    };
    bool exactKeys(Map<String, dynamic> map, Set<String> keys) =>
        map.length == keys.length && map.keys.every(keys.contains);
    if (status == VerificationStatus.notFound) {
      if (!exactKeys(value, {'schema_version', 'result'})) throw unexpected;
      return VerificationResult(status);
    }
    if (!exactKeys(value, {
          'schema_version',
          'result',
          'credential_code',
          'title',
          'issuer',
          'issued_at',
          'expires_at',
          'checked_at',
          'verification_source',
        }) ||
        value['verification_source'] != 'certichain_registry' ||
        value['credential_code'] != requestedCode ||
        value['title'] is! String ||
        (value['title'] as String).trim().isEmpty) {
      throw unexpected;
    }
    final issuer = value['issuer'];
    if (issuer is! Map<String, dynamic> ||
        !exactKeys(issuer, {'name'}) ||
        issuer['name'] is! String ||
        (issuer['name'] as String).trim().isEmpty) {
      throw unexpected;
    }
    return VerificationResult(
      status,
      record: VerifiedRecord(
        code: requestedCode,
        title: value['title'] as String,
        issuer: issuer['name'] as String,
        issuedAt: decodeDate(value['issued_at']),
        checkedAt: decodeDate(value['checked_at']),
        expiresAt: value['expires_at'] == null
            ? null
            : decodeDate(value['expires_at']),
      ),
    );
  }

  static DateTime decodeDate(Object? input) {
    const unexpected = VerificationException(VerificationFailure.unexpected);
    if (input is! String) throw unexpected;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(input);
    if (match == null || match.end != input.length) throw unexpected;
    final parts = List.generate(6, (i) => int.parse(match.group(i + 1)!));
    final calendar = DateTime.utc(parts[0], parts[1], parts[2]);
    if (parts[0] < 1 ||
        calendar.year != parts[0] ||
        calendar.month != parts[1] ||
        calendar.day != parts[2] ||
        parts[3] > 23 ||
        parts[4] > 59 ||
        parts[5] > 59) {
      throw unexpected;
    }
    final zone = match.group(8)!;
    if (zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 23 ||
            int.parse(zone.substring(4)) > 59)) {
      throw unexpected;
    }
    final date = DateTime.tryParse(input);
    if (date == null) throw unexpected;
    return date.toUtc();
  }
}
