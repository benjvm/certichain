import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/features/verification/data/http_verification_repository.dart';
import 'package:mobile/features/verification/domain/verification_repository.dart';
import 'package:mobile/features/verification/domain/verification_link.dart';
import 'package:mobile/app/router/public_router.dart';

const publicCode = 'e42f105a-a36b-40de-8326-47da5749eae3';
Map<String, dynamic> publicDto({String result = 'valid'}) => {
  'schema_version': '1',
  'result': result,
  'credential_code': publicCode,
  'title': 'Formación sintética',
  'issuer': {'name': 'Emisor sintético'},
  'issued_at': '2020-01-01T10:00:00.123456+02:00',
  'expires_at': null,
  'checked_at': '2026-10-04T12:00:00.654321+00:00',
  'verification_source': 'certichain_registry',
};
TypeMatcher<VerificationException> failure(VerificationFailure value) =>
    isA<VerificationException>().having((e) => e.failure, 'failure', value);
void main() {
  test(
    'UUID canonical trim/case, all versions; reject alternate representations',
    () {
      expect(
        normalizeCredentialCode('  ${publicCode.toUpperCase()}  '),
        publicCode,
      );
      expect(
        normalizeCredentialCode('00000000-0000-0000-0000-000000000000'),
        isNotNull,
      );
      for (final invalid in [
        '',
        publicCode.replaceAll('-', ''),
        '{$publicCode}',
        'urn:uuid:$publicCode',
        '$publicCode/a',
        '$publicCode\nx',
        'é${publicCode.substring(1)}',
      ]) {
        expect(normalizeCredentialCode(invalid), isNull);
      }
    },
  );
  for (final state in ['valid', 'revoked', 'expired', 'issuer_unavailable']) {
    test('exact v1 $state and server dates with microseconds', () {
      final result = HttpVerificationRepository.decodeResult(
        publicDto(result: state),
        publicCode,
      );
      expect(
        result.record!.issuedAt,
        DateTime.utc(2020, 1, 1, 8, 0, 0, 123, 456),
      );
      expect(result.record!.checkedAt.microsecond, 321);
      expect(result.record!.expiresAt, isNull);
      expect(result.status, switch (state) {
        'valid' => VerificationStatus.valid,
        'revoked' => VerificationStatus.revoked,
        'expired' => VerificationStatus.expired,
        _ => VerificationStatus.issuerUnavailable,
      });
      // No classification from local dates: even a past expiry remains server valid.
      final dto = publicDto(result: state)
        ..['expires_at'] = '2021-01-01T00:00:00Z';
      expect(
        HttpVerificationRepository.decodeResult(dto, publicCode).status,
        result.status,
      );
    });
  }
  test('minimal not_found has no invented record or code', () {
    final result = HttpVerificationRepository.decodeResult({
      'schema_version': '1',
      'result': 'not_found',
    }, publicCode);
    expect(result.status, VerificationStatus.notFound);
    expect(result.record, isNull);
    expect(
      () => HttpVerificationRepository.decodeResult({
        'schema_version': '1',
        'result': 'not_found',
        'credential_code': publicCode,
      }, publicCode),
      throwsA(failure(VerificationFailure.unexpected)),
    );
  });
  test('closed types, version, source, issuer and all required keys', () {
    final variants = <Object?>[
      null,
      [],
      {'schema_version': 1, 'result': 'not_found'},
      {'schema_version': '2', 'result': 'not_found'},
    ];
    for (final field in publicDto().keys) {
      variants.add(publicDto()..remove(field));
    }
    for (final entry in {
      'schema_version': 1,
      'result': 'pending',
      'title': 24,
      'credential_code': 'another',
      'issuer': {'name': 'Issuer', 'logo': 'extra'},
      'verification_source': 'blockchain',
      'issued_at': 42,
      'expires_at': false,
    }.entries) {
      variants.add(publicDto()..[entry.key] = entry.value);
    }
    variants.add(publicDto()..['holder'] = 'private');
    for (final dto in variants) {
      expect(
        () => HttpVerificationRepository.decodeResult(dto, publicCode),
        throwsA(failure(VerificationFailure.unexpected)),
      );
    }
  });
  test(
    'reject impossible dates, absent zones, leap seconds and trailing data',
    () {
      for (final date in [
        '2026-02-30T12:00:00Z',
        '2026-13-01T00:00:00Z',
        '2026-01-01T24:00:00Z',
        '2026-01-01T00:00:60Z',
        '2026-01-01T00:00:00',
        '2026-01-01',
        '2026-01-01T00:00:00+24:00',
        '2026-01-01T00:00:00.1234567Z',
        '2026-01-01T00:00:00Z\n',
      ]) {
        expect(
          () => HttpVerificationRepository.decodeResult(
            publicDto()..['checked_at'] = date,
            publicCode,
          ),
          throwsA(failure(VerificationFailure.unexpected)),
        );
      }
    },
  );
  test(
    'HTTP has one canonical JSON field and no SDK/session headers',
    () async {
      var calls = 0;
      final repo = HttpVerificationRepository(
        apiUrl: 'http://127.0.0.1:55321',
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'http://127.0.0.1:55321/functions/v1/verify-certificate',
          );
          expect(jsonDecode(request.body), {'credential_code': publicCode});
          expect(
            request.headers.keys.map((k) => k.toLowerCase()),
            isNot(
              anyOf(
                contains('authorization'),
                contains('apikey'),
                contains('cookie'),
              ),
            ),
          );
          return http.Response(
            jsonEncode(publicDto()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await expectLater(
        repo.verify('invalid'),
        throwsA(failure(VerificationFailure.invalidInput)),
      );
      expect(calls, 0);
      expect(
        (await repo.verify(' ${publicCode.toUpperCase()} ')).status,
        VerificationStatus.valid,
      );
      expect(calls, 1);
    },
  );
  test('bounded response, invalid JSON, unknown HTTP and infrastructure distinction', () async {
    for (final vector in [
      (503, '{}', VerificationFailure.unavailable),
      (401, '{}', VerificationFailure.unexpected),
      (400, '{}', VerificationFailure.invalidInput),
      (200, '<html>', VerificationFailure.unexpected),
      (200, ' ' * 8193, VerificationFailure.unexpected),
    ]) {
      final repo = HttpVerificationRepository(
        apiUrl: 'https://example.invalid',
        client: MockClient((_) async => http.Response(vector.$2, vector.$1)),
      );
      await expectLater(repo.verify(publicCode), throwsA(failure(vector.$3)));
    }
  });
  test('429 Retry-After and prudent fallback', () async {
    for (final seconds in ['12', 'invalid']) {
      final repo = HttpVerificationRepository(
        apiUrl: 'https://example.invalid',
        client: MockClient(
          (_) async =>
              http.Response('{}', 429, headers: {'retry-after': seconds}),
        ),
      );
      await expectLater(
        repo.verify(publicCode),
        throwsA(
          failure(VerificationFailure.rateLimited).having(
            (dynamic e) => e.retryAfter,
            'wait',
            Duration(seconds: seconds == '12' ? 12 : 60),
          ),
        ),
      );
    }
  });
  test('timeout and transport error are not absence', () async {
    final stalled = Completer<http.Response>();
    final repo = HttpVerificationRepository(
      apiUrl: 'https://example.invalid',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) => stalled.future),
    );
    await expectLater(
      repo.verify(publicCode),
      throwsA(failure(VerificationFailure.timeout)),
    );
    stalled.complete(http.Response('{}', 503));
    final broken = HttpVerificationRepository(
      apiUrl: 'https://example.invalid',
      client: MockClient(
        (_) async => throw http.ClientException('private error'),
      ),
    );
    await expectLater(
      broken.verify(publicCode),
      throwsA(failure(VerificationFailure.network)),
    );
  });
  test('trusted Web base, hash link and strict public route', () {
    final link = VerificationLink(
      'http://localhost:7357',
      allowLocalHttp: true,
    );
    expect(
      link.forCode(publicCode.toUpperCase()),
      'http://localhost:7357/#/verify/$publicCode',
    );
    expect(
      VerificationLink('https://example.org/app').forCode(publicCode),
      'https://example.org/app/#/verify/$publicCode',
    );
    for (final base in [
      '',
      'http://example.org',
      'https://user:pass@example.org',
      'https://example.org?x=1',
      'https://example.org/#x',
      'http://10.0.2.2:7357',
      'https://example.org/../app',
    ]) {
      expect(VerificationLink.tryCreate(base, allowLocalHttp: true), isNull);
    }
    expect(VerificationLink.tryCreate('http://localhost:7357'), isNull);
    expect(
      PublicLocation.parse(Uri.parse('/verify/$publicCode')).code,
      publicCode,
    );
    for (final route in [
      '/verify/bad',
      '/verify/$publicCode/extra',
      '/verify/$publicCode?server=https://evil.invalid',
      '/verify/%20$publicCode',
    ]) {
      expect(PublicLocation.parse(Uri.parse(route)).invalid, isTrue);
    }
  });
}
