import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/certificates/data/supabase_certificate_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_repository.dart';
import 'package:mobile/features/profile/data/supabase_profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late Uri uri;
  late String? prefer;
  late Object response;
  late int status;

  Map<String, dynamic> row({
    String holder = 'holder-a',
    String state = 'active',
    Object? institution,
  }) => {
    'id': 'certificate-a',
    'holder_id': holder,
    'institution_id': 'institution-a',
    'title': 'Formación sintética',
    'issued_at': '2026-01-01T00:00:00Z',
    'expires_at': '2026-12-01T00:00:00Z',
    'status': state,
    'institutions': institution,
  };

  setUp(() async {
    response = <Object>[];
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      uri = request.uri;
      prefer = request.headers.value('prefer');
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('content-range', '0-0/73');
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'profile reads only own id and maps trusted fields; missing is null',
    () async {
      final repository = SupabaseProfileRepository(client);
      response = [
        {'id': 'holder-a', 'full_name': 'Nombre del perfil', 'role': 'holder'},
      ];
      final profile = await repository.readProfile('holder-a');
      expect(profile?.fullName, 'Nombre del perfil');
      expect(profile?.role, 'holder');
      expect(uri.path, '/rest/v1/profiles');
      expect(uri.queryParameters['id'], 'eq.holder-a');
      expect(uri.queryParameters['select'], 'id,full_name,role');
      response = <Object>[];
      expect(await repository.readProfile('holder-a'), isNull);
    },
  );

  test(
    'wallet is holder scoped, bounded, ordered and left embeds optional issuer',
    () async {
      response = [row()];
      final repository = SupabaseCertificateRepository(client);
      final wallet = await repository.readWallet('holder-a');
      expect(wallet.total, 73);
      expect(wallet.certificates.single.title, 'Formación sintética');
      expect(wallet.certificates.single.institutionName, isNull);
      expect(wallet.certificates.single.expiresAt, DateTime.utc(2026, 12));
      expect(uri.path, '/rest/v1/certificates');
      expect(uri.queryParameters['holder_id'], 'eq.holder-a');
      expect(
        uri.queryParameters['order'],
        'issued_at.desc.nullslast,id.desc.nullslast',
      );
      expect(uri.queryParameters['limit'], '50');
      expect(uri.queryParameters['select'], contains('institutions(name)'));
      expect(uri.queryParameters['select'], isNot(contains('!inner')));
      expect(uri.queryParameters['select'], isNot(contains('document')));
      expect(prefer, contains('count=exact'));
      response = [
        row(institution: {'name': 'Institución sintética'}),
      ];
      expect(
        (await repository.readWallet('holder-a'))
            .certificates
            .single
            .institutionName,
        'Institución sintética',
      );
      response = <Object>[];
      expect((await repository.readWallet('holder-a')).certificates, isEmpty);
    },
  );

  test('unexpected owner and unknown status fail closed', () async {
    final repository = SupabaseCertificateRepository(client);
    response = [row(holder: 'holder-b')];
    await expectLater(repository.readWallet('holder-a'), throwsFormatException);
    response = [row(state: 'unknown')];
    await expectLater(repository.readWallet('holder-a'), throwsFormatException);
  });
  test('holder reads SQL revocation timestamp only; historical absence stays unknown', () async {
    final repository = SupabaseCertificateRepository(client);
    response = [
      {...row(state: 'revoked'), 'revoked_at': '2026-10-18T11:22:33.123456Z'},
    ];
    final revoked = await repository.readCertificate(
      'holder-a',
      'certificate-a',
    );
    expect(revoked!.revokedAt, DateTime.parse('2026-10-18T11:22:33.123456Z'));
    expect(revoked.validityAt(DateTime.now()), CertificateValidity.revoked);
    for (final forbidden in [
      'reason',
      'requested_by',
      'request_id',
      'revocations',
      'salt',
    ]) {
      expect(uri.queryParameters['select'], isNot(contains(forbidden)));
    }
    response = [row(state: 'revoked')];
    expect(
      (await repository.readCertificate(
        'holder-a',
        'certificate-a',
      ))!.revokedAt,
      isNull,
    );
  });

  test(
    'detail scopes id and holder, preserves hidden issuer and missing rows',
    () async {
      final repository = SupabaseCertificateRepository(client);
      response = [row()];
      final certificate = await repository.readCertificate(
        'holder-a',
        'certificate-a',
      );
      expect(certificate?.title, 'Formación sintética');
      expect(certificate?.institutionName, isNull);
      expect(uri.queryParameters['holder_id'], 'eq.holder-a');
      expect(uri.queryParameters['id'], 'eq.certificate-a');
      expect(
        uri.queryParameters['select'],
        'id,holder_id,institution_id,title,issued_at,expires_at,status,revoked_at,institutions(name)',
      );
      response = <Object>[];
      expect(
        await repository.readCertificate('holder-a', 'certificate-a'),
        isNull,
      );
    },
  );

  test(
    'detail rejects unexpected identities and states, propagates errors',
    () async {
      final repository = SupabaseCertificateRepository(client);
      for (final invalid in [
        row(holder: 'holder-b'),
        {...row(), 'id': 'other'},
        row(state: 'unknown'),
      ]) {
        response = [invalid];
        await expectLater(
          repository.readCertificate('holder-a', 'certificate-a'),
          throwsFormatException,
        );
      }
      status = 403;
      response = {'message': 'private payload', 'code': '42501'};
      await expectLater(
        repository.readCertificate('holder-a', 'certificate-a'),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test(
    'backend failure is propagated for retry, never interpreted as empty',
    () async {
      status = 403;
      response = {'message': 'private payload', 'code': '42501'};
      await expectLater(
        SupabaseProfileRepository(client).readProfile('holder-a'),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        SupabaseCertificateRepository(client).readWallet('holder-a'),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test('revocation takes priority; expiration includes the exact instant and time zones', () {
    Certificate certificate(CertificateStatus status, DateTime? expiry) =>
        Certificate(
          id: 'c',
          holderId: 'a',
          institutionId: 'i',
          title: 'Synthetic',
          issuedAt: DateTime.utc(2025),
          status: status,
          expiresAt: expiry,
        );
    final now = DateTime.utc(2026, 9, 25, 12);
    expect(
      certificate(
        CertificateStatus.revoked,
        DateTime.utc(2020),
      ).validityAt(now),
      CertificateValidity.revoked,
    );
    expect(
      certificate(CertificateStatus.active, DateTime.utc(2020)).validityAt(now),
      CertificateValidity.expired,
    );
    expect(
      certificate(
        CertificateStatus.active,
        DateTime.parse('2026-09-25T14:00:00+02:00'),
      ).validityAt(now),
      CertificateValidity.expired,
    );
    expect(
      certificate(
        CertificateStatus.active,
        now.add(const Duration(seconds: 1)),
      ).validityAt(now),
      CertificateValidity.valid,
    );
    expect(
      certificate(CertificateStatus.active, null).validityAt(now),
      CertificateValidity.valid,
    );
  });
}
