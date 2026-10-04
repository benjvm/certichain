import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/features/issuance/data/supabase_issuance_repository.dart';
import 'package:mobile/features/issuance/data/platform_pdf_picker.dart';
import 'package:mobile/features/issuance/domain/issuance_repository.dart';
import 'package:mobile/features/institutions/data/supabase_institution_repository.dart';
import 'package:mobile/features/certificates/data/supabase_certificate_document_repository.dart';
import 'package:mobile/features/certificates/data/pdf_saver_native.dart';
import 'package:mobile/features/certificates/domain/certificate_document_repository.dart';

import 'issuance_fakes.dart';

final class TestPlatformFile extends PlatformFile {
  TestPlatformFile(this.name, this.size, [this.chunks = const []]);
  @override
  final String name;
  final int size;
  final List<Uint8List> chunks;
  @override
  Uri get uri => Uri.file('synthetic.pdf');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => size;
  @override
  Future<int?> length() async => size;
  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(chunks.expand((c) => c).toList());
  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromIterable(chunks);
}

class PickerStub extends FilePickerPlatform {
  PlatformFile? result;
  Map<Symbol, dynamic>? arguments;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    arguments = {#type: type, #extensions: allowedExtensions};
    return result;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    void Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    arguments = {#fileName: fileName, #bytes: bytes, #mimeType: mimeType};
    return Uri.file('synthetic-destination.pdf');
  }
}

void main() {
  setUpAll(() {
    FilePickerPlatform.instance = PickerStub();
  });
  late SupabaseClient client;
  late http.Client transport;
  late Future<http.Response> Function(http.Request) action;
  late String token;
  setUp(() async {
    action = (request) async => http.Response('{}', 500);
    final expires =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    token =
        'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': expires}))).replaceAll('=', '')}.signature';
    transport = MockClient((request) async {
      if (request.url.path.endsWith('/token')) {
        return http.Response(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'synthetic',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': actorId,
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/logout')) {
        return http.Response('{}', 200);
      }
      final response = await action(request);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        request: request,
        headers: {'content-type': 'application/json', ...response.headers},
      );
    });
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'public-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'synthetic',
    );
  });
  tearDown(() async {
    await client.dispose();
    transport.close();
  });
  IssuanceRequest request() => IssuanceRequest(
    institutionId: institutionId,
    actorId: actorId,
    key: certificateId,
    data: issuanceData(),
    pdf: selectedPdf(),
  );
  SupabaseIssuanceRepository issuer() => SupabaseIssuanceRepository(
    client,
    apiUrl: 'http://127.0.0.1:54321',
    publicKey: 'public-key',
    transport: transport,
  );
  SupabaseCertificateDocumentRepository documents({
    Future<bool> Function(Uint8List)? saver,
  }) => SupabaseCertificateDocumentRepository(
    client,
    apiUrl: 'http://127.0.0.1:54321',
    publicKey: 'public-key',
    transport: transport,
    saver: saver ?? (_) async => true,
  );
  for (final status in [200, 201]) {
    test(
      'multipart and real current-session JWT; HTTP $status completed',
      () async {
        action = (r) async {
          expect(r.url.path, '/functions/v1/issue-certificate');
          expect(r.headers['authorization'], 'Bearer $token');
          expect(r.body, contains('name="idempotency_key"'));
          expect(r.body, contains(certificateId));
          expect(
            r.body.toLowerCase(),
            contains('content-type: application/pdf'),
          );
          expect(r.body, isNot(contains('issued_by')));
          expect(r.body, isNot(contains('service_role')));
          return http.Response(
            jsonEncode({
              'status': 'completed',
              'certificate_id': certificateId,
            }),
            status,
          );
        };
        expect(await issuer().issue(request()), certificateId);
      },
    );
  }
  test(
    'public errors, Retry-After, lost response and gateway 401 stay safe',
    () async {
      for (final code in [
        'forbidden',
        'invalid_input',
        'invalid_pdf',
        'payload_too_large',
        'idempotency_conflict',
        'operation_in_progress',
        'attempt_failed',
        'temporary_failure',
        'stored_object_invalid',
      ]) {
        action = (_) async => http.Response(
          jsonEncode({'error': code, 'message': 'private-secret'}),
          409,
          headers: {'retry-after': '120'},
        );
        await expectLater(
          issuer().issue(request()),
          throwsA(
            isA<IssuanceException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.retryAfter, 'retry', 120)
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('private-secret')),
                ),
          ),
        );
      }
      action = (_) async => http.Response('gateway html', 401);
      await expectLater(
        issuer().issue(request()),
        throwsA(
          isA<IssuanceException>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
      action = (_) async => throw http.ClientException('sensitive url');
      await expectLater(
        issuer().issue(request()),
        throwsA(
          isA<IssuanceException>().having(
            (e) => e.code,
            'code',
            'response_lost',
          ),
        ),
      );
    },
  );
  test('identity mismatch never sends another account request', () async {
    var called = false;
    action = (_) async {
      called = true;
      return http.Response('{}', 200);
    };
    await expectLater(
      issuer().issue(
        IssuanceRequest(
          institutionId: institutionId,
          actorId: holderId,
          key: certificateId,
          data: issuanceData(),
          pdf: selectedPdf(),
        ),
      ),
      throwsA(isA<IssuanceException>()),
    );
    expect(called, false);
  });
  test('memberships select only current user, minimum institution fields and real role', () async {
    action = (r) async {
      expect(r.url.queryParameters['user_id'], 'eq.$actorId');
      expect(
        r.url.queryParameters['select'],
        'user_id,role,institutions!inner(id,name,verification_status)',
      );
      return http.Response(
        jsonEncode([
          {
            'user_id': actorId,
            'role': 'issuer',
            'institutions': {
              'id': institutionId,
              'name': 'Visible',
              'verification_status': 'verified',
            },
          },
        ]),
        200,
      );
    };
    final members = await SupabaseInstitutionRepository(client)
        .readMemberships(actorId);
    expect(members.single.canIssue, true);
    expect(members.single.name, 'Visible');
    action = (_) async =>
        throw StateError('A foreign membership query must not be sent');
    await expectLater(
      SupabaseInstitutionRepository(client).readMemberships(holderId),
      throwsFormatException,
    );
    action = (_) async => http.Response(
      jsonEncode([
        {'user_id': holderId},
      ]),
      200,
    );
    await expectLater(
      SupabaseInstitutionRepository(client).readMemberships(actorId),
      throwsFormatException,
    );
  });
  test('issued list explicitly filters institution and stable order, bounded count', () async {
    action = (r) async {
      expect(r.url.queryParameters['institution_id'], 'eq.$institutionId');
      expect(
        r.url.queryParameters['order'],
        'issued_at.desc.nullslast,id.desc.nullslast',
      );
      expect(r.url.queryParameters['limit'], '50');
      expect(r.url.queryParameters['select'], isNot(contains('profiles')));
      return http.Response(
        jsonEncode([
          {
            'id': certificateId,
            'holder_id': holderId,
            'institution_id': institutionId,
            'title': 'Visible',
            'issued_at': '2026-01-01T00:00:00Z',
            'expires_at': null,
            'status': 'active',
          },
        ]),
        200,
        headers: {'content-range': '0-0/72'},
      );
    };
    final result = await SupabaseInstitutionRepository(client)
        .readIssued(institutionId);
    expect(result.total, 72);
    expect(result.certificates.single.holderId, holderId);
  });
  for (final memberships in [false, true]) {
    for (final change in ['logout', 'renewal']) {
      test(
        'institutional ${memberships ? 'memberships' : 'issued'} discards response after $change',
        () async {
          final arrived = Completer<void>();
          final release = Completer<http.Response>();
          action = (_) {
            arrived.complete();
            return release.future;
          };
          final repository = SupabaseInstitutionRepository(client);
          final result = memberships
              ? repository.readMemberships(actorId)
              : repository.readIssued(institutionId);
          final denied = expectLater(result, throwsFormatException);
          await arrived.future;
          if (change == 'logout') {
            await client.auth.signOut(scope: SignOutScope.local);
          } else {
            token = '${token}renewed';
            await client.auth.signInWithPassword(
              email: 'fixture@example.invalid',
              password: 'synthetic',
            );
          }
          release.complete(
            http.Response('[]', 200, headers: {'content-range': '*/0'}),
          );
          await denied;
        },
      );
    }
  }
  test('issued list without a valid session never starts HTTP', () async {
    await client.auth.signOut(scope: SignOutScope.local);
    action = (_) async => throw StateError('Must not query');
    await expectLater(
      SupabaseInstitutionRepository(client).readIssued(institutionId),
      throwsFormatException,
    );
  });
  test('document requests a fresh URL every action, exact bytes, no JWT on capability GET', () async {
    var signs = 0;
    Uint8List? saved;
    action = (r) async {
      if (r.method == 'POST') {
        signs++;
        expect(jsonDecode(r.body), {'certificate_id': certificateId});
        expect(r.headers['authorization'], 'Bearer $token');
        return http.Response(
          jsonEncode({
            'signed_url':
                '/storage/v1/object/sign/certificates/$institutionId/$certificateId.pdf?token=$signs',
            'expires_in': 60,
          }),
          200,
        );
      }
      expect(
        r.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
      return http.Response.bytes(
        [37, 80, 68, 70],
        200,
        headers: {'content-type': 'application/pdf'},
      );
    };
    final repo = documents(
      saver: (bytes) async {
        saved = bytes;
        return true;
      },
    );
    expect(await repo.isAvailable(actorId, certificateId), true);
    expect(await repo.download(actorId, certificateId), true);
    expect(await repo.download(actorId, certificateId), true);
    expect(signs, 3);
    expect(saved, [37, 80, 68, 70]);
  });
  test('document absent, invalid external URL, overlong TTL and 401', () async {
    action = (_) async =>
        http.Response('{"error":"document_unavailable"}', 404);
    expect(await documents().isAvailable(actorId, certificateId), false);
    for (final data in [
      {'signed_url': 'https://foreign.example/file', 'expires_in': 60},
      {
        'signed_url': '/storage/v1/object/sign/certificates/file',
        'expires_in': 61,
      },
    ]) {
      action = (_) async => http.Response(jsonEncode(data), 200);
      await expectLater(
        documents().download(actorId, certificateId),
        throwsA(isA<DocumentException>()),
      );
    }
    action = (_) async => http.Response('{}', 401);
    await expectLater(
      documents().download(actorId, certificateId),
      throwsA(
        isA<DocumentException>().having(
          (e) => e.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
  });
  test('multiplatform picker stream, cancellation, oversize and native saving contract', () async {
    final original = FilePickerPlatform.instance, stub = PickerStub();
    FilePickerPlatform.instance = stub;
    try {
      stub.result = TestPlatformFile('selected.pdf', 4, [
        Uint8List.fromList([37, 80, 68, 70]),
      ]);
      expect((await PlatformPdfPicker().pick())!.bytes, [37, 80, 68, 70]);
      expect(stub.arguments![#type], FileType.custom);
      expect(stub.arguments![#extensions], ['pdf']);
      stub.result = null;
      expect(await PlatformPdfPicker().pick(), null);
      stub.result = TestPlatformFile('big.pdf', maxPdfBytes + 1);
      await expectLater(
        PlatformPdfPicker().pick(),
        throwsA(isA<IssuanceException>()),
      );
      expect(await savePdf(Uint8List.fromList([37, 80, 68, 70])), true);
      expect(stub.arguments![#fileName], 'certificado.pdf');
      expect(stub.arguments![#bytes], [37, 80, 68, 70]);
    } finally {
      FilePickerPlatform.instance = original;
    }
  });
}
