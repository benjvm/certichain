import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/features/revocation/domain/revocation_repository.dart';
import 'package:mobile/features/revocation/domain/revocation_reason.dart';
import 'package:mobile/features/revocation/data/revocation_key_preferences.dart';
import 'package:mobile/features/revocation/presentation/revocation_controller.dart';
import 'package:mobile/features/revocation/presentation/revocation_panel.dart';
import 'package:mobile/features/verification/data/public_revocation_models.dart';
import 'package:mobile/features/verification/data/blockchain_models.dart';
import 'package:mobile/features/verification/domain/verification_repository.dart';
import 'package:mobile/features/verification/domain/public_revocation.dart';
import 'package:mobile/features/institutions/domain/institution_repository.dart';

import 'phase9d_test.dart' show registryDto, code;

const scope = RevocationScope('user', 'institution', code);
final decision = RevocationDecision(
  certificateId: code,
  requestId: code,
  revokedAt: DateTime.utc(2026, 10, 15),
  reason: 'Private reason',
  synchronization: const [],
);

class Keys implements RevocationKeyStore {
  Completer<String>? delayed;
  @override
  Future<String> obtain(RevocationScope s) async =>
      delayed == null ? code : delayed!.future;
}

class Repo implements RevocationRepository {
  final calls = <(String, String, Completer<RevocationDecision>)>[];
  int reads = 0, auths = 0, cancels = 0;
  RevocationDecision result = decision;
  String? readError, authError;
  Completer<RevocationDecision>? delayedRead;
  @override
  Future<RevocationDecision> request(
    RevocationScope s,
    String key,
    String reason,
  ) {
    final c = Completer<RevocationDecision>();
    calls.add((key, reason, c));
    return c.future;
  }

  @override
  Future<RevocationDecision> progress(RevocationScope s) async {
    reads++;
    if (delayedRead != null) return delayedRead!.future;
    if (readError != null) throw RevocationException(readError!);
    return result;
  }

  @override
  Future<RevocationDecision> reauthorize(RevocationScope s, String id) async {
    auths++;
    if (authError != null) throw RevocationException(authError!);
    return decision;
  }

  @override
  void cancel(RevocationScope s) {
    cancels++;
  }
}

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reason matches backend NFC, ASCII trim, newline and Unicode point rules',
    () {
      expect(
        normalizeRevocationReason(' \tCafe\u0301\r\ntexto\r\t '),
        'Café\ntexto',
      );
      expect(
        normalizeRevocationReason('\u00a0texto\u00a0'),
        '\u00a0texto\u00a0',
      );
      expect(revocationReasonError('😀' * 500), isNull);
      expect(revocationReasonError('😀' * 501), isNotNull);
      expect(revocationReasonError('e\u0301' * 500), isNull);
      expect(revocationReasonError(' \t\r\n '), isNotNull);
      for (final r in [0, 8, 11, 31, 127, 0xd800, 0xdfff]) {
        expect(revocationReasonError('x${String.fromCharCode(r)}'), isNotNull);
      }
      expect(revocationReasonError('x\t\ny\u0085'), isNull);
      expect(revocationReasonError('<b>Texto privado</b>'), isNull);
    },
  );
  test(
    'invalid reason never obtains key or sends; canonical reason freezes',
    () async {
      final r = Repo(), c = RevocationController(scope, Repo(), Keys());
      await c.request('  ');
      expect(c.error, 'invalid_input');
      expect(c.frozen, isFalse);
      c.dispose();
      final ctrl = RevocationController(scope, r, Keys());
      final pending = ctrl.request(' Cafe\u0301\r\n ');
      await flush();
      expect(r.calls.single.$2, 'Café');
      r.calls.single.$3.completeError(const RevocationException('timeout'));
      await pending;
      expect(ctrl.uncertain, isTrue);
      await ctrl.refresh();
      expect(ctrl.uncertain, isFalse);
      expect(ctrl.decision, same(decision));
      expect(r.auths, 0);
      ctrl.dispose();
    },
  );
  test(
    'loss of access removes private decision and disables further requests',
    () async {
      for (final error in [
        'revocation_unavailable',
        'authorization_denied',
        'unauthenticated',
        'stale_session',
      ]) {
        final r = Repo();
        final ctrl = RevocationController(scope, r, Keys());
        await ctrl.refresh();
        r.readError = error;
        await ctrl.refresh();
        expect(ctrl.decision, isNull);
        expect(ctrl.accessDenied, isTrue);
        await ctrl.request('private');
        await ctrl.reauthorize(code);
        expect(r.calls, isEmpty);
        expect(r.auths, 0);
        ctrl.dispose();
      }
    },
  );
  test(
    'owner/admin verified or suspended only; no global platform shortcut',
    () {
      for (final role in InstitutionalRole.values) {
        for (final state in InstitutionStatus.values) {
          expect(
            InstitutionMembership(
              id: 'i',
              name: 'i',
              role: role,
              status: state,
            ).canRevoke,
            role != InstitutionalRole.issuer &&
                [
                  InstitutionStatus.verified,
                  InstitutionStatus.suspended,
                ].contains(state),
          );
        }
      }
    },
  );
  test('busy reauthorization preserves original SQL decision and needs explicit retry', () async {
    final r = Repo(), c = RevocationController(scope, Repo(), Keys());
    c.dispose();
    final ctrl = RevocationController(scope, r, Keys());
    await ctrl.refresh();
    r.authError = 'busy';
    await ctrl.reauthorize(code);
    expect(ctrl.error, 'busy');
    expect(ctrl.decision, same(decision));
    expect(r.auths, 1);
    await ctrl.refresh();
    expect(r.auths, 1);
    ctrl.dispose();
  });
  test('corrupt receipt cannot silently generate a replacement key', () async {
    final name =
        'revocation-key:${scope.userId}:${scope.institutionId}:${scope.certificateId}';
    SharedPreferences.setMockInitialValues({name: 'corrupt'});
    await expectLater(
      RevocationKeyPreferences().obtain(scope),
      throwsA(
        isA<RevocationException>().having(
          (e) => e.code,
          'code',
          'receipt_failure',
        ),
      ),
    );
    expect((await SharedPreferences.getInstance()).getString(name), 'corrupt');
  });
  test('double send, lost response retry retains exact reason/key, refresh never reauthorizes', () async {
    final r = Repo(), c = RevocationController(scope, Repo(), Keys());
    c.dispose();
    final ctrl = RevocationController(scope, r, Keys());
    final first = ctrl.request('Original');
    await flush();
    await ctrl.request('Duplicate');
    expect(r.calls.length, 1);
    r.calls.first.$3.completeError(const RevocationException('timeout'));
    await first;
    final retry = ctrl.request('Changed');
    await flush();
    expect(r.calls.last.$1, r.calls.first.$1);
    expect(r.calls.last.$2, 'Original');
    r.calls.last.$3.complete(decision);
    await retry;
    expect(ctrl.decision!.revoked, isTrue);
    await ctrl.refresh();
    expect(r.auths, 0);
    expect(r.reads, 1);
    ctrl.dispose();
  });
  test('scope invalidation/dispose discard late reason and abort before delayed key sends', () async {
    for (final dispose in [false, true]) {
      final repo = Repo(), c = RevocationController(scope, repo, Keys());
      final pending = c.request('Private');
      await flush();
      if (dispose) {
        c.dispose();
      } else {
        c.invalidate();
      }
      repo.calls.single.$3.complete(decision);
      await pending;
      expect(c.decision, isNull);
      expect(repo.cancels, greaterThan(0));
      if (!dispose) c.dispose();
    }
    final keys = Keys()..delayed = Completer<String>(),
        r = Repo(),
        c = RevocationController(scope, r, keys);
    final pending = c.request('Private');
    c.invalidate();
    keys.delayed!.complete(code);
    await pending;
    expect(r.calls, isEmpty);
    c.dispose();
  });
  test('recovery keys are persisted and isolated, without reason', () async {
    SharedPreferences.setMockInitialValues({});
    final keys = RevocationKeyPreferences();
    final concurrent = await Future.wait(
      List.generate(8, (_) => RevocationKeyPreferences().obtain(scope)),
    );
    final key = concurrent.first;
    expect(concurrent, everyElement(key));
    expect(
      await Future.wait(
        List.generate(8, (_) => RevocationKeyPreferences().obtain(scope)),
      ),
      everyElement(key),
    );
    expect(await keys.obtain(scope), key);
    for (final other in [
      const RevocationScope('other', 'institution', code),
      const RevocationScope('user', 'other', code),
      const RevocationScope('user', 'institution', 'other'),
    ]) {
      expect(await keys.obtain(other), isNot(key));
    }
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().every(
        (k) => !prefs.get(k).toString().contains('Private'),
      ),
      isTrue,
    );
  });
  test(
    'v3 closed revoke evidence never widens v2; priority remains revoked',
    () {
      final dto = <String, Object?>{
        'schema_version': '3',
        'registry': registryDto('revoked'),
        'blockchain': {
          'state': 'off_chain_only',
          'finality': 'unknown',
          'checked_at': registryDto()['checked_at'],
          'source': 'certichain_registry',
        },
        'revocation': {
          'state': 'not_applicable',
          'revoked_at': '2026-10-15T00:00:00Z',
          'checked_at': '2026-10-15T00:00:01Z',
          'source': 'certichain_registry',
          'evidence': null,
          'last_evidence': null,
        },
      };
      expect(decodeV3(dto, code).status, VerificationStatus.revoked);
      expect(
        decodeV3(dto, code).revocation!.state,
        PublicRevocationState.notApplicable,
      );
      expect(() => decodeV2(dto, code), throwsFormatException);
      for (final extra in ['reason', 'actor', 'salt', 'raw']) {
        final widened = {
          ...dto,
          'revocation': {
            ...(dto['revocation']! as Map<String, Object?>),
            extra: 'private',
          },
        };
        expect(() => decodeV3(widened, code), throwsFormatException);
      }
    },
  );
  testWidgets(
    'explicit irreversible confirmation, no request on cancel, private session clears',
    (tester) async {
      final repo = Repo(), session = ChangeNotifier();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RevocationPanel(
              scope: scope,
              repository: repo,
              keys: Keys(),
              onSessionExpired: () {},
              sessionChanges: session,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Private reason');
      await tester.tap(find.text('Revocar certificado'));
      await tester.pumpAndSettle();
      expect(find.text('Revocación irreversible'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      await tester.tap(find.text('Revocar certificado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar revocación'));
      await tester.pump();
      expect(repo.calls.length, 1);
      repo.calls.single.$3.complete(decision);
      await tester.pumpAndSettle();
      expect(find.text('Revocado en CertiChain'), findsOneWidget);
      session.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.textContaining('Motivo privado: Private'), findsNothing);
      expect(repo.auths, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
}
