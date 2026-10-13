import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/app/theme/app_theme.dart';
import 'package:mobile/core/files/strict_json.dart';
import 'package:mobile/features/issuance/domain/anchoring_repository.dart';
import 'package:mobile/features/issuance/data/anchor_receipt_preferences.dart';
import 'package:mobile/features/issuance/data/supabase_anchoring_repository.dart';
import 'package:mobile/features/issuance/presentation/anchoring_controller.dart';
import 'package:mobile/features/issuance/presentation/anchoring_panel.dart';
import 'package:mobile/features/verification/domain/blockchain_verification.dart';
import 'package:mobile/features/verification/domain/verification_repository.dart';
import 'package:mobile/features/verification/domain/hash_comparison.dart';
import 'package:mobile/features/verification/data/blockchain_models.dart';
import 'package:mobile/features/verification/data/http_verification_repository.dart';
import 'package:mobile/features/verification/data/protocol_opening_tools.dart';
import 'package:mobile/features/verification/data/sha256_pdf_hasher.dart';
import 'package:mobile/features/verification/presentation/verification_screen.dart';
import 'package:mobile/features/verification/presentation/opening_check_controller.dart';
import 'package:mobile/features/certificates/presentation/opening_action.dart';

import 'phase8c_test.dart' show TestPicker, ImmediateHasher, flush;

const code = '00112233-4455-6677-8899-aabbccddeeff';
const user = '9d000000-0000-4000-8000-000000000001';
const institution = '9d000000-0000-4000-8000-000000000011';
const scope = AnchorScope(user, institution, code);
final fixture = jsonDecode(
  File('../blockchain/fixtures/protocol-v1.json').readAsStringSync(),
) as Map<String, dynamic>;
Map<String, Object?> openingDto() => {
  'protocol_version': 1,
  'credential_code': code,
  'issuer_id': fixture['issuer_id'],
  'document_sha256': fixture['document_sha256'],
  'salt': fixture['salt'],
  'chain_id': '31337',
  'contract_address': '0x${'11' * 20}',
};
Map<String, Object?> registryDto([String result = 'valid']) => {
  'schema_version': '1',
  'result': result,
  'credential_code': code,
  'title': 'Synthetic 9D',
  'issuer': {'name': 'Synthetic Issuer'},
  'issued_at': '2020-01-01T00:00:00Z',
  'expires_at': null,
  'checked_at': '2026-10-13T00:00:00.123456Z',
  'verification_source': 'certichain_registry',
};
Map<String, Object?> evidenceDto([String state = 'confirmed']) => {
  'state': state,
  'finality': 'not_applicable',
  'checked_at': '2026-10-13T00:00:01Z',
  'source': 'backend_rpc',
  'chain_id': '31337',
  'contract_address': '0x${'11' * 20}',
  'protocol_version': 1,
  'certificate_key': fixture['certificate_key'],
  'issuer_id': fixture['issuer_id'],
  'commitment': fixture['commitment'],
  'revoked': false,
  'transaction_hash': '0x${'22' * 32}',
  'block_number': '12',
  'block_hash': '0x${'33' * 32}',
  'confirmations': '1',
  'registered_at': '2026-10-13T00:00:00Z',
};

class MemoryReceipts implements AnchorReceiptStore {
  final values = <AnchorScope, AnchorReceipt>{};
  @override
  Future<AnchorReceipt?> read(AnchorScope s) async => values[s];
  @override
  Future<void> save(AnchorScope s, AnchorReceipt r) async {
    values[s] = r;
  }
}

class AnchorFake implements AnchoringRepository {
  final requests = <(AnchorScope, String, Completer<AnchorOperation>)>[];
  int cancelled = 0, reauthorizations = 0, updates = 0;
  @override
  Future<AnchorOperation> request(AnchorScope s, String key) {
    final c = Completer<AnchorOperation>();
    requests.add((s, key, c));
    return c.future;
  }

  @override
  Future<AnchorOperation> progress(AnchorScope s, String id) async {
    updates++;
    return AnchorOperation(id, AnchorStatus.confirmed);
  }

  @override
  Future<AnchorOperation> reauthorize(AnchorScope s, String id) async {
    reauthorizations++;
    return AnchorOperation(id, AnchorStatus.requested);
  }

  @override
  void cancel(AnchorScope s) {
    cancelled++;
  }
}

class OpeningsFake implements OpeningRepository, OpeningTransfer {
  int obtained = 0, serialized = 0, exports = 0, cancelled = 0;
  Completer<CertificateOpening>? barrier;
  @override
  Future<CertificateOpening> obtain(String u, String id) async {
    obtained++;
    return barrier == null
        ? decodeOpening(openingDto())
        : await barrier!.future;
  }

  @override
  void cancelOpening(String u, String id) {
    cancelled++;
  }

  @override
  String serialize(CertificateOpening o) {
    serialized++;
    return encodeOpening(o);
  }

  @override
  Future<bool> export(CertificateOpening o) async {
    exports++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '9B fixture exact PDF, binary UUID, SHA-256 K/C, uppercase code',
    () async {
      final pdf = File('../blockchain/fixtures/synthetic.pdf')
          .readAsBytesSync();
      expect(
        '0x${await Sha256PdfHasher().hash(pdf)}',
        fixture['document_sha256'],
      );
      expect(certificateKey(code), fixture['certificate_key']);
      expect(certificateKey(code.toUpperCase()), fixture['certificate_key']);
      expect(
        documentCommitment(
          fixture['certificate_key'] as String,
          fixture['issuer_id'] as String,
          fixture['document_sha256'] as String,
          fixture['salt'] as String,
        ),
        fixture['commitment'],
      );
      final check = checkOpening(
        decodeOpening(openingDto()),
        code,
        (fixture['document_sha256'] as String).substring(2),
        decodeEvidence(evidenceDto(), code),
      );
      expect(check.validity, OpeningValidity.match);
    },
  );
  for (final bad in <Object?>[
    null,
    <Object?>[],
    {'extra': true},
    {...openingDto(), 'protocol_version': 1.0},
    {...openingDto(), 'chain_id': 31337},
    {...openingDto(), 'salt': '0x${'AA' * 32}'},
    {...openingDto(), 'contract_address': 'https://evil.invalid'},
    {...openingDto(), 'document_sha256': '0x00'},
  ]) {
    test(
      'opening parser rejects invalid variant ${bad.hashCode}',
      () => expect(() => decodeOpening(bad), throwsFormatException),
    );
  }
  test('JSON duplicates, escapes, UTF8 bounds and recursion fail closed', () {
    for (final bad in [
      '{"a":1,"\\u0061":2}',
      'x' * 2049,
      '${'[' * 17}0${']' * 17}',
      '1e999',
    ]) {
      expect(
        () => decodeStrictJson(bad, maxBytes: 2048),
        throwsFormatException,
      );
    }
    expect(() => parseOpening('é' * 1100), throwsFormatException);
  });
  for (final state in [
    'off_chain_only',
    'pending',
    'unavailable',
    'reorged',
    'divergence',
  ]) {
    test('registry valid remains independent from $state', () {
      final result = decodeV2({
        'schema_version': '2',
        'registry': registryDto(),
        'blockchain': {
          'state': state,
          'finality': 'unknown',
          'checked_at': registryDto()['checked_at'],
          'source': state == 'off_chain_only'
              ? 'certichain_registry'
              : state == 'pending'
              ? 'backend_rpc'
              : 'unavailable',
        },
      }, code);
      expect(result.status, VerificationStatus.valid);
      expect(result.blockchain, isNotNull);
    });
  }
  test('strict evidence types/finality/privacy/date/identity', () {
    for (final changes in [
      {'chain_id': 31337},
      {'block_number': 12},
      {'confirmations': '01'},
      {'protocol_version': 1.0},
      {'finality': 'finalized'},
      {'certificate_key': '0x${'44' * 32}'},
      {'checked_at': '2026-02-30T00:00:00Z'},
      {'revoked': 'false'},
      {'source': 'unknown'},
      {'source': 'unavailable'},
      {'confirmations': '0'},
      {'url': 'https://evil.invalid'},
    ]) {
      expect(
        () => decodeEvidence({...evidenceDto(), ...changes}, code),
        throwsA(anything),
      );
    }
    expect(
      () => decodeV2({
        'schema_version': '2',
        'registry': {'schema_version': '1', 'result': 'not_found'},
        'blockchain': evidenceDto(),
      }, code),
      throwsFormatException,
    );
  });
  test(
    'opening invalid versus PDF mismatch versus unavailable and prior evidence',
    () {
      final o = decodeOpening(openingDto()),
          e = decodeEvidence(evidenceDto(), code),
          h = (fixture['document_sha256'] as String).substring(2);
      expect(
        checkOpening(o, code, '00' * 32, e).validity,
        OpeningValidity.pdfMismatch,
      );
      expect(
        checkOpening(
          decodeOpening({...openingDto(), 'salt': '0x${'44' * 32}'}),
          code,
          h,
          e,
        ).validity,
        OpeningValidity.invalidOpening,
      );
      expect(
        checkOpening(
          decodeOpening({
            ...openingDto(),
            'contract_address': '0x${'44' * 20}',
          }),
          code,
          h,
          e,
        ).validity,
        OpeningValidity.invalidOpening,
      );
      expect(
        checkOpening(o, code, h, null).validity,
        OpeningValidity.evidenceUnavailable,
      );
      final prior = decodeEvidence(
        {
          ...evidenceDto()..remove('registered_at'),
          'source': 'persisted_receipt',
        },
        code,
        previous: true,
      );
      expect(
        checkOpening(o, code, h, prior).validity,
        OpeningValidity.evidenceUnavailable,
      );
    },
  );
  test('Anvil no explorer and allowlisted Sepolia hash link', () {
    expect(decodeEvidence(evidenceDto(), code).explorer, isNull);
    expect(
      decodeEvidence({
        ...evidenceDto(),
        'chain_id': '11155111',
        'finality': 'unknown',
        'confirmations': '12',
      }, code).explorer!.host,
      'sepolia.etherscan.io',
    );
  });
  test(
    'public v2 single POST without credentials and preserves comparison v1',
    () async {
      final paths = <String>[];
      final repo = HttpVerificationRepository(
        apiUrl: 'https://example.invalid',
        useV2: true,
        client: MockClient((r) async {
          paths.add(r.url.path);
          expect(
            r.headers.keys.any(
              (k) => [
                'authorization',
                'apikey',
                'cookie',
              ].contains(k.toLowerCase()),
            ),
            false,
          );
          if (r.url.path.endsWith('v2')) {
            return http.Response(
              jsonEncode({
                'schema_version': '2',
                'registry': registryDto(),
                'blockchain': evidenceDto(),
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'schema_version': '1',
              'verification': registryDto(),
              'file_integrity': 'match',
            }),
            200,
          );
        }),
      );
      expect(
        (await repo.verify(code)).blockchain?.state,
        BlockchainState.confirmed,
      );
      expect(
        (await repo.compare(code, '00' * 32)).integrity,
        FileIntegrity.match,
      );
      expect(paths, [
        '/functions/v1/verify-certificate-v2',
        '/functions/v1/compare-certificate-hash',
      ]);
      repo.close();
    },
  );
  test('lost request response keeps persisted key; double submit prevented; explicit progress', () async {
    final store = MemoryReceipts(),
        repo = AnchorFake(),
        c = AnchoringController(scope, repo, MemoryReceipts());
    final controller = AnchoringController(scope, repo, store);
    await controller.load();
    final a = controller.request();
    await flush();
    expect(store.values[scope]?.key, repo.requests.single.$2);
    await controller.request();
    expect(repo.requests.length, 1);
    repo.requests.single.$3.completeError(const AnchoringException('timeout'));
    await a;
    final b = controller.request();
    await flush();
    expect(repo.requests[1].$2, repo.requests[0].$2);
    repo.requests[1].$3.complete(
      const AnchorOperation(code, AnchorStatus.requested),
    );
    await b;
    expect(controller.receipt?.operation?.status, AnchorStatus.requested);
    await controller.progress();
    expect(controller.receipt?.operation?.status, AnchorStatus.confirmed);
    controller.dispose();
    c.dispose();
  });
  test(
    'session invalidation and dispose discard late private responses',
    () async {
      for (final dispose in [false, true]) {
        final repo = AnchorFake(),
            c = AnchoringController(scope, repo, MemoryReceipts());
        await c.load();
        final pending = c.request();
        await flush();
        if (dispose) {
          c.dispose();
        } else {
          c.invalidate();
        }
        repo.requests.single.$3.complete(
          const AnchorOperation(code, AnchorStatus.confirmed),
        );
        await pending;
        expect(c.receipt?.operation, isNull);
        expect(repo.cancelled, greaterThan(0));
        if (!dispose) c.dispose();
      }
    },
  );
  test('receipt scopes isolate account/institution/certificate and failed/divergence do not retry automatically', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AnchorReceiptPreferences();
    await store.save(
      scope,
      AnchorReceipt(
        code,
        DateTime.now(),
        operation: const AnchorOperation(code, AnchorStatus.blocked),
      ),
    );
    for (final other in [
      const AnchorScope(code, institution, code),
      const AnchorScope(user, code, code),
      const AnchorScope(user, institution, user),
    ]) {
      expect(await store.read(other), isNull);
    }
    final repo = AnchorFake(), c = AnchoringController(scope, repo, store);
    await c.load();
    expect(repo.requests, isEmpty);
    await c.reauthorize();
    expect(repo.reauthorizations, 1);
    c.dispose();
    final divergent = MemoryReceipts()
      ..values[scope] = AnchorReceipt(
        code,
        DateTime.now(),
        operation: const AnchorOperation(code, AnchorStatus.divergence),
      );
    final d = AnchoringController(scope, repo, divergent);
    await d.load();
    await d.reauthorize();
    await d.request();
    expect(repo.reauthorizations, 1);
    expect(repo.requests, isEmpty);
    d.dispose();
  });
  for (final length in [0, 8388609]) {
    test('opening PDF bound $length', () async {
      final picker = TestPicker(),
          c = OpeningCheckController(
            ProtocolOpeningTools(),
            picker,
            Sha256PdfHasher(),
          );
      final pending = c.check(
        jsonEncode(openingDto()),
        code,
        decodeEvidence(evidenceDto(), code),
      );
      await flush();
      picker.requests.single.complete(Uint8List(length));
      await pending;
      expect(
        c.pdfFailure,
        length == 0 ? LocalPdfFailure.empty : LocalPdfFailure.tooLarge,
      );
      c.dispose();
    });
  }
  test('opening PDF cancelled, late selection after reset and malformed JSON never uploads', () async {
    final picker = TestPicker(),
        c = OpeningCheckController(
          ProtocolOpeningTools(),
          picker,
          Sha256PdfHasher(),
        );
    await c.check('{}', code, null);
    expect(c.result?.validity, OpeningValidity.invalidOpening);
    expect(picker.requests, isEmpty);
    final pending = c.check(jsonEncode(openingDto()), code, null);
    await flush();
    c.reset();
    picker.requests.single.complete(Uint8List.fromList([1]));
    await pending;
    expect(c.result, isNull);
    c.dispose();
  });
  test('opening local original and altered PDF against fixture', () async {
    for (final altered in [false, true]) {
      final picker = TestPicker(),
          c = OpeningCheckController(
            ProtocolOpeningTools(),
            picker,
            Sha256PdfHasher(),
          );
      final pending = c.check(
        jsonEncode(openingDto()),
        code,
        decodeEvidence(evidenceDto(), code),
      );
      await flush();
      final bytes = File('../blockchain/fixtures/synthetic.pdf')
          .readAsBytesSync();
      if (altered) bytes[bytes.length - 1] ^= 1;
      picker.requests.single.complete(bytes);
      await pending;
      expect(
        c.result?.validity,
        altered ? OpeningValidity.pdfMismatch : OpeningValidity.match,
      );
      c.dispose();
    }
  });
  test('unreadable PDF is separate from invalid opening', () async {
    final picker = TestPicker(),
        c = OpeningCheckController(
          ProtocolOpeningTools(),
          picker,
          Sha256PdfHasher(),
        );
    final pending = c.check(
      jsonEncode(openingDto()),
      code,
      decodeEvidence(evidenceDto(), code),
    );
    await flush();
    picker.requests.single.completeError(
      StateError('Synthetic unreadable file'),
    );
    await pending;
    expect(c.pdfFailure, LocalPdfFailure.unreadable);
    expect(c.result, isNull);
    c.dispose();
  });
  testWidgets(
    'opening only obtained/copied/exported explicitly, session clears and late response ignored',
    (t) async {
      final repo = OpeningsFake(), session = ChangeNotifier();
      var copies = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') copies++;
            return null;
          });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpeningAction(
              userId: user,
              certificateId: code,
              repository: repo,
              transfer: repo,
              onSessionExpired: () {},
              sessionChanges: session,
            ),
          ),
        ),
      );
      expect(repo.obtained, 0);
      await t.tap(find.text('Obtener apertura'));
      await t.pumpAndSettle();
      expect(repo.obtained, 1);
      expect(repo.exports, 0);
      expect(copies, 0);
      await t.tap(find.text('Copiar apertura'));
      await t.pumpAndSettle();
      expect(copies, 1);
      await t.tap(find.text('Exportar apertura JSON'));
      await t.pumpAndSettle();
      expect(repo.exports, 1);
      session.notifyListeners();
      await t.pump();
      expect(find.text('Copiar apertura'), findsNothing);
      repo.barrier = Completer<CertificateOpening>();
      await t.tap(find.text('Obtener apertura'));
      await t.pump();
      session.notifyListeners();
      repo.barrier!.complete(decodeOpening(openingDto()));
      await t.pumpAndSettle();
      expect(find.text('Copiar apertura'), findsNothing);
      await t.pumpWidget(const SizedBox());
      session.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
  testWidgets(
    '320 px text x2 four results and independent revoked PDF comparison without camera',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(
        () => {t.view.resetPhysicalSize(), t.view.resetDevicePixelRatio()},
      );
      final repo = HttpVerificationRepository(
            apiUrl: 'https://example.invalid',
            useV2: true,
            client: MockClient(
              (r) async => http.Response(
                jsonEncode(
                  r.url.path.endsWith('v2')
                      ? {
                          'schema_version': '2',
                          'registry': registryDto(),
                          'blockchain': evidenceDto(),
                        }
                      : {
                          'schema_version': '1',
                          'verification': registryDto('revoked'),
                          'file_integrity': 'match',
                        },
                ),
                200,
              ),
            ),
          ),
          picker = TestPicker();
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: VerificationScreen(
              repository: repo,
              comparisonRepository: repo,
              comparisonPicker: picker,
              pdfHasher: ImmediateHasher(),
              openingInput: ProtocolOpeningTools(),
              initialCode: code,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Registro CertiChain'), findsOneWidget);
      expect(find.text('Blockchain'), findsOneWidget);
      await t.ensureVisible(find.text('Comparar mi PDF'));
      await t.tap(find.text('Comparar mi PDF'));
      await t.pump();
      picker.requests.single.complete(Uint8List.fromList([1]));
      await t.pumpAndSettle();
      expect(find.text('Certificado revocado'), findsOneWidget);
      expect(
        find.text('Evidencia anterior; pertenece a otra consulta.'),
        findsOneWidget,
      );
      expect(
        find.text('El PDF coincide byte a byte con el documento registrado.'),
        findsOneWidget,
      );
      await t.ensureVisible(find.text('Comprobar con apertura'));
      await t.tap(find.text('Comprobar con apertura'));
      await t.pumpAndSettle();
      expect(find.text('Validez de la apertura'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      repo.close();
    },
  );
  testWidgets('anchor confirmation and operation fit 320px text x2', (t) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(
      () => {t.view.resetPhysicalSize(), t.view.resetDevicePixelRatio()},
    );
    final repo = AnchorFake();
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: AnchoringPanel(
                scope: scope,
                repository: repo,
                store: MemoryReceipts(),
                onSessionExpired: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Solicitar anclaje'));
    await t.pumpAndSettle();
    expect(repo.requests, isEmpty);
    await t.ensureVisible(find.text('Confirmar solicitud'));
    await t.tap(find.text('Confirmar solicitud'));
    await t.pump();
    await t.runAsync(flush);
    repo.requests.single.$3.complete(
      const AnchorOperation(code, AnchorStatus.requested),
    );
    await t.pumpAndSettle();
    expect(find.text('Solicitud pendiente del worker.'), findsOneWidget);
    await t.ensureVisible(find.text('Actualizar estado'));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  test(
    'private Retry-After enables manual retry without an automatic POST',
    () async {
      final repo = AnchorFake(),
          c = AnchoringController(scope, repo, MemoryReceipts());
      await c.load();
      final pending = c.request();
      await flush();
      repo.requests.single.$3.completeError(
        const AnchoringException(
          'rate_limited',
          retryAfter: Duration(milliseconds: 20),
        ),
      );
      await pending;
      expect(c.canAct, false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.canAct, true);
      expect(repo.requests.length, 1);
      c.dispose();
    },
  );
  testWidgets(
    'existing operation remains readable when a new anchor is ineligible',
    (t) async {
      final repo = AnchorFake(),
          store = MemoryReceipts()
            ..values[scope] = AnchorReceipt(
              code,
              DateTime.now(),
              operation: const AnchorOperation(code, AnchorStatus.requested),
            );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnchoringPanel(
                scope: scope,
                repository: repo,
                store: store,
                canRequest: false,
                onSessionExpired: () {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Solicitar anclaje'), findsNothing);
      await t.tap(find.text('Actualizar estado'));
      await t.pumpAndSettle();
      expect(repo.updates, 1);
      expect(repo.requests, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  group('private transport', () {
    late SupabaseClient client;
    late MockClient transport;
    late SupabaseAnchoringRepository repo;
    late Future<http.Response> Function(http.Request) action;
    var tokenVersion = 0;
    setUp(() async {
      action = (r) async => http.Response(
        jsonEncode({'operation_id': code, 'status': 'requested'}),
        202,
      );
      transport = MockClient((r) async {
        if (r.url.path.endsWith('/token')) {
          final token =
              'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600, 'version': tokenVersion}))).replaceAll('=', '')}.signature';
          return http.Response(
            jsonEncode({
              'access_token': token,
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': user,
                'aud': 'authenticated',
                'created_at': '2026-01-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.endsWith('/logout')) return http.Response('{}', 200);
        return action(r);
      });
      client = SupabaseClient(
        'http://127.0.0.1:54321',
        'public',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.signInWithPassword(
        email: 'synthetic@example.invalid',
        password: 'synthetic',
      );
      repo = SupabaseAnchoringRepository(
        client,
        apiUrl: 'http://127.0.0.1:54321',
        publicKey: 'public',
        transport: transport,
        timeout: const Duration(milliseconds: 100),
      );
    });
    tearDown(() async {
      await client.dispose();
      repo.close();
    });
    for (final error in {
      401: 'unauthenticated',
      403: 'authorization_denied',
      409: 'idempotency_conflict',
      429: 'rate_limited',
      503: 'temporary_failure',
    }.entries) {
      test('maps HTTP ${error.key} sanitized', () async {
        action = (r) async => http.Response(
          jsonEncode({'error': error.value}),
          error.key,
          headers: {'retry-after': '10'},
        );
        await expectLater(
          repo.request(scope, code),
          throwsA(
            isA<AnchoringException>().having(
              (e) => e.code,
              'code',
              error.value,
            ),
          ),
        );
      });
    }
    test('request uses only certificate/key and current JWT, 202 remains requested', () async {
      action = (r) async {
        expect(jsonDecode(r.body), {
          'certificate_id': code,
          'idempotency_key': code,
        });
        expect(r.headers['Authorization'], startsWith('Bearer '));
        return http.Response(
          jsonEncode({'operation_id': code, 'status': 'requested'}),
          202,
        );
      };
      expect((await repo.request(scope, code)).status, AnchorStatus.requested);
    });
    test('same-user token refresh rejects stale private response', () async {
      final barrier = Completer<http.Response>();
      action = (r) => barrier.future;
      final pending = repo.request(scope, code);
      await flush();
      tokenVersion++;
      await client.auth.signInWithPassword(
        email: 'synthetic@example.invalid',
        password: 'synthetic',
      );
      barrier.complete(
        http.Response(
          jsonEncode({'operation_id': code, 'status': 'confirmed'}),
          200,
        ),
      );
      await expectLater(
        pending,
        throwsA(
          isA<AnchoringException>().having(
            (e) => e.code,
            'code',
            'stale_session',
          ),
        ),
      );
    });
    test(
      'logout rejects in-flight response and no opening from another account',
      () async {
        final barrier = Completer<http.Response>();
        action = (r) => barrier.future;
        final pending = repo.obtain(user, code);
        await flush();
        await client.auth.signOut(scope: SignOutScope.local);
        barrier.complete(http.Response(jsonEncode(openingDto()), 200));
        await expectLater(pending, throwsA(isA<AnchoringException>()));
        await expectLater(
          repo.obtain(code, code),
          throwsA(isA<AnchoringException>()),
        );
      },
    );
    test('private timeout/cancellation preserves error and rejects operation mismatch', () async {
      final barrier = Completer<http.Response>();
      action = (r) => barrier.future;
      final pending = repo.request(scope, code);
      await expectLater(
        pending,
        throwsA(
          isA<AnchoringException>().having((e) => e.code, 'code', 'timeout'),
        ),
      );
      barrier.complete(http.Response('{}', 503));
      action = (r) async => http.Response(
        jsonEncode({'operation_id': user, 'status': 'confirmed'}),
        200,
      );
      await expectLater(
        repo.progress(scope, code),
        throwsA(isA<AnchoringException>()),
      );
    });
  });
}
