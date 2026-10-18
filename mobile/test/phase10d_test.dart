import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/app/theme/app_theme.dart';
import 'package:mobile/features/revocation/domain/revocation_repository.dart';
import 'package:mobile/features/revocation/presentation/revocation_panel.dart';
import 'package:mobile/features/revocation/data/revocation_key_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/features/institutions/presentation/institution_workspace.dart';
import 'package:mobile/features/institutions/domain/institution_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_repository.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/verification/data/http_verification_repository.dart';
import 'package:mobile/features/verification/data/public_revocation_models.dart';
import 'package:mobile/features/verification/domain/verification_repository.dart';
import 'package:mobile/features/verification/presentation/public_revocation_panel.dart';
import 'package:mobile/features/verification/presentation/verification_controller.dart';
import 'package:mobile/features/verification/presentation/verification_screen.dart';

import 'phase10_test.dart' as f;
import 'phase9d_test.dart' show code, registryDto, evidenceDto;
import 'phase8c_test.dart' show TestPicker, ImmediateHasher;
import 'issuance_fakes.dart' as issuance;

Map<String, Object?> publicDto(String state) => {
  'schema_version': '3',
  'registry': registryDto('revoked'),
  'blockchain': {...evidenceDto(), 'revoked': true},
  'revocation': {
    'state': state,
    'revoked_at': '2026-10-13T00:00:00Z',
    'checked_at': '2026-10-13T00:00:01Z',
    'source': ['confirmed', 'included'].contains(state)
        ? 'backend_rpc'
        : state == 'unavailable'
        ? 'unavailable'
        : 'certichain_registry',
    'evidence': state == 'confirmed'
        ? {
            'transaction_hash': '0x${'44' * 32}',
            'block_number': '14',
            'block_hash': '0x${'55' * 32}',
            'confirmations': '1',
            'revoked_at': '2026-10-13T00:00:00Z',
            'checked_at': '2026-10-13T00:00:01Z',
            'finality': 'not_applicable',
          }
        : null,
    'last_evidence': state == 'unavailable'
        ? {
            'transaction_hash': '0x${'44' * 32}',
            'block_number': '14',
            'block_hash': '0x${'55' * 32}',
            'checked_at': '2026-10-13T00:00:00Z',
          }
        : null,
  },
};

void main() {
  testWidgets(
    'suspended owner/admin can revoke without issuance or document actions',
    (t) async {
      for (final role in InstitutionalRole.values) {
        final institutions = issuance.FakeInstitutions()
          ..members = [
            issuance.membership(
              role: role,
              status: InstitutionStatus.suspended,
            ),
          ];
        institutions.wallets[issuance.institutionId] = CertificateWallet(
          certificates: [
            Certificate(
              id: code,
              holderId: issuance.holderId,
              institutionId: issuance.institutionId,
              title: 'Certificado suspendido',
              issuedAt: DateTime.utc(2026),
              status: CertificateStatus.active,
            ),
          ],
          total: 1,
        );
        await t.pumpWidget(
          MaterialApp(
            home: InstitutionWorkspace(
              key: ValueKey(role),
              userId: issuance.actorId,
              repository: institutions,
              issuance: issuance.FakeIssuance(),
              picker: issuance.FakePdfPicker(),
              store: issuance.MemoryAttempts(),
              revocations: f.Repo(),
              revocationKeys: f.Keys(),
              documents: issuance.FakeDocuments(),
              onSessionExpired: () {},
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
        expect(find.text('Consultar PDF'), findsNothing);
        expect(find.text('Consultar apertura privada'), findsNothing);
        expect(
          find.text('Revocación / consultar estado'),
          role == InstitutionalRole.issuer ? findsNothing : findsOneWidget,
        );
      }
    },
  );
  testWidgets('rebuilt form reuses persisted key after lost response', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = f.Repo();
    Future<void> mount() async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RevocationPanel(
              scope: f.scope,
              repository: repo,
              keys: RevocationKeyPreferences(),
              onSessionExpired: () {},
            ),
          ),
        ),
      );
      await t.enterText(find.byType(TextField), 'Original');
      await t.tap(find.text('Revocar certificado'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirmar revocación'));
      await t.pumpAndSettle();
    }

    await mount();
    repo.calls.first.$3.completeError(const RevocationException('network'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await mount();
    expect(repo.calls.length, 2);
    expect(repo.calls.last.$1, repo.calls.first.$1);
    repo.calls.last.$3.complete(f.decision);
    await t.pumpAndSettle();
  });
  testWidgets(
    'scope replacement and session change discard late private progress',
    (t) async {
      for (final sessionChange in [true, false]) {
        final repo = f.Repo()..delayedRead = Completer<RevocationDecision>();
        final session = ChangeNotifier();
        var callbacks = 0;
        Widget panel(RevocationScope scope) => MaterialApp(
          home: Scaffold(
            body: RevocationPanel(
              scope: scope,
              repository: repo,
              keys: f.Keys(),
              sessionChanges: session,
              onRevoked: () => callbacks++,
              onSessionExpired: () {},
            ),
          ),
        );
        await t.pumpWidget(panel(f.scope));
        await t.tap(find.text('Consultar revocación / recuperar respuesta'));
        await t.pump();
        if (sessionChange) {
          session.notifyListeners();
        } else {
          await t.pumpWidget(
            panel(const RevocationScope('other', 'other', code)),
          );
        }
        repo.delayedRead!.complete(f.decision);
        await t.pumpAndSettle();
        expect(find.textContaining('Motivo privado: Private'), findsNothing);
        expect(callbacks, 0);
        await t.pumpWidget(const SizedBox());
        session.dispose();
      }
    },
  );
  for (final state in [
    'not_applicable',
    'pending',
    'blocked',
    'confirmed',
    'reorged',
    'unavailable',
    'divergence',
  ]) {
    testWidgets(
      'public $state keeps SQL revoked and issue/revoke evidence separate',
      (t) async {
        final r = decodeV3(publicDto(state), code);
        expect(r.status, VerificationStatus.revoked);
        if (state == 'confirmed') {
          expect(
            r.blockchain!.transactionHash,
            isNot(r.revocation!.evidence!.hash),
          );
        }
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PublicRevocationPanel(revocation: r.revocation!),
              ),
            ),
          ),
        );
        expect(find.textContaining('Revocado en CertiChain:'), findsOneWidget);
        expect(find.textContaining('Private'), findsNothing);
        if (state == 'confirmed') {
          expect(
            find.textContaining('Finalidad no aplicable: red local Anvil.'),
            findsOneWidget,
          );
        }
        if (state == 'unavailable') {
          expect(
            find.textContaining('no comprobada actualmente'),
            findsOneWidget,
          );
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'included is distinct from confirmed; v3 not_requested is explicit',
    (t) async {
      final v = publicDto('confirmed');
      v['blockchain'] = {
        ...evidenceDto(),
        'revoked': true,
        'chain_id': '11155111',
        'confirmations': '12',
        'finality': 'unknown',
      };
      final q = v['revocation']! as Map<String, Object?>;
      q['state'] = 'included';
      q['evidence'] = {
        ...q['evidence']! as Map<String, Object?>,
        'finality': 'unknown',
      };
      final included = decodeV3(v, code).revocation!;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PublicRevocationPanel(revocation: included)),
        ),
      );
      expect(
        find.text('Revocación EVM incluida; confirmación pendiente.'),
        findsOneWidget,
      );
      expect(find.text('Revocación EVM confirmada.'), findsNothing);
      q['revoked_at'] = null;
      q['state'] = 'not_requested';
      q['source'] = 'certichain_registry';
      q['evidence'] = null;
      v['registry'] = registryDto();
      v['blockchain'] = evidenceDto();
      expect(decodeV3(v, code).revocation!.revokedAt, isNull);
    },
  );
  test('v1/v2/v3 choose one endpoint; PDF retains dated revoke evidence without another verify', () async {
    for (final version in [1, 2, 3]) {
      final paths = <String>[];
      final repo = HttpVerificationRepository(
        apiUrl: 'https://example.invalid',
        useV2: version == 2,
        useV3: version == 3,
        client: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('compare-certificate-hash')
                  ? {
                      'schema_version': '1',
                      'verification': registryDto('revoked'),
                      'file_integrity': 'match',
                    }
                  : version == 3
                  ? publicDto('confirmed')
                  : version == 2
                  ? {
                      'schema_version': '2',
                      'registry': registryDto('revoked'),
                      'blockchain': {...evidenceDto(), 'revoked': true},
                    }
                  : registryDto('revoked'),
            ),
            200,
          );
        }),
      );
      final picker = TestPicker();
      final c = VerificationController(
        repo,
        comparisonRepository: repo,
        picker: picker,
        hasher: ImmediateHasher(),
      );
      c.changeCode(code);
      await c.submit();
      final observation = c.result!.revocation;
      expect(paths, [
        '/functions/v1/verify-certificate${version == 1 ? '' : '-v$version'}',
      ]);
      expect(observation == null, version != 3);
      final comparison = c.selectAndCompare();
      picker.requests.single.complete(Uint8List.fromList([1]));
      await comparison;
      expect(paths.length, 2);
      expect(paths.last, '/functions/v1/compare-certificate-hash');
      expect(c.result!.status, VerificationStatus.revoked);
      expect(c.result!.revocation, isNull);
      expect(c.previousRevocation, same(observation));
      c.changeCode('another');
      expect(c.previousRevocation, isNull);
      c.dispose();
      repo.close();
    }
  });
  testWidgets(
    'small scaled form validates, confirms once, recovers and reauthorizes explicitly',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final repo = f.Repo()
        ..result = RevocationDecision(
          certificateId: code,
          requestId: code,
          revokedAt: DateTime.utc(2026),
          reason: '<b>Privado</b>',
          synchronization: const [
            RevocationSync(code, RevocationSyncStatus.blocked),
          ],
        );
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: RevocationPanel(
                  scope: f.scope,
                  repository: repo,
                  keys: f.Keys(),
                  certificateTitle: 'Título institucional largo ' * 4,
                  onSessionExpired: () {},
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String label) async {
        await t.ensureVisible(find.text(label));
        await t.tap(find.text(label));
        await t.pumpAndSettle();
      }

      await tap('Revocar certificado');
      expect(find.text('Introduce un motivo privado.'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await t.enterText(find.byType(TextField), 'Privado');
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await tap('Revocar certificado');
      expect(find.textContaining(code), findsOneWidget);
      await tap('Cancelar');
      expect(repo.calls, isEmpty);
      await tap('Revocar certificado');
      await tap('Confirmar revocación');
      await t.tap(
        find.text('Reintentar la misma solicitud'),
        warnIfMissed: false,
      );
      expect(repo.calls.length, 1);
      repo.calls.single.$3.completeError(const RevocationException('timeout'));
      await t.pumpAndSettle();
      expect(find.textContaining('puede haberse aplicado'), findsOneWidget);
      await tap('Consultar revocación / recuperar respuesta');
      expect(find.text('Revocado en CertiChain'), findsOneWidget);
      expect(find.text('Motivo privado: <b>Privado</b>'), findsOneWidget);
      expect(repo.auths, 0);
      await tap('Reautorizar explícitamente');
      expect(repo.auths, 0);
      await tap('Cancelar');
      expect(repo.auths, 0);
      await tap('Reautorizar explícitamente');
      await tap('Confirmar reautorización');
      expect(repo.auths, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'PDF v1 comparison displays both dated v3 evidence panels as previous',
    (t) async {
      var requests = 0;
      final repo = HttpVerificationRepository(
        apiUrl: 'https://example.invalid',
        useV3: true,
        client: MockClient((r) async {
          requests++;
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('v3')
                  ? publicDto('confirmed')
                  : {
                      'schema_version': '1',
                      'verification': registryDto('revoked'),
                      'file_integrity': 'match',
                    },
            ),
            200,
          );
        }),
      );
      final picker = TestPicker();
      await t.pumpWidget(
        MaterialApp(
          home: VerificationScreen(
            repository: repo,
            comparisonRepository: repo,
            comparisonPicker: picker,
            pdfHasher: ImmediateHasher(),
            initialCode: code,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Comparar mi PDF'));
      await t.tap(find.text('Comparar mi PDF'));
      await t.pump();
      picker.requests.single.complete(Uint8List.fromList([1]));
      await t.pumpAndSettle();
      expect(find.text('Evidencia de emisión'), findsOneWidget);
      expect(find.text('Evidencia de revocación'), findsOneWidget);
      expect(
        find.text(
          'Evidencia anterior de revocación; no comprobada actualmente. Se conserva la fecha de observación.',
        ),
        findsOneWidget,
      );
      expect(find.text('Certificado revocado'), findsOneWidget);
      expect(requests, 2);
      await t.pumpWidget(const SizedBox());
      repo.close();
    },
  );
  testWidgets('server denial clears private reason and hides actions', (
    t,
  ) async {
    final r = f.Repo();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RevocationPanel(
            scope: f.scope,
            repository: r,
            keys: f.Keys(),
            onSessionExpired: () {},
          ),
        ),
      ),
    );
    await t.tap(find.text('Consultar revocación / recuperar respuesta'));
    await t.pumpAndSettle();
    expect(find.textContaining('Motivo privado: Private'), findsOneWidget);
    r.readError = 'revocation_unavailable';
    await t.tap(find.text('Consultar revocación / recuperar respuesta'));
    await t.pumpAndSettle();
    expect(find.textContaining('Motivo privado: Private'), findsNothing);
    expect(
      find.text('Consultar revocación / recuperar respuesta'),
      findsNothing,
    );
    expect(find.textContaining('ya no tienes permiso'), findsOneWidget);
  });
}
