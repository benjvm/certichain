import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/features/institutions/domain/institution_repository.dart';
import 'package:mobile/features/issuance/domain/issuance_repository.dart';
import 'package:mobile/features/issuance/data/pending_attempt_preferences.dart';
import 'package:mobile/features/issuance/presentation/issuance_controller.dart';

import 'issuance_fakes.dart';

void main() {
  test(
    'fingerprint matches the backend published NFC/microsecond/PDF vector',
    () {
      final pdf = base64Decode(
        'JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgID4+CmVuZG9iagoyIDAgb2JqCjw8IC9UeXBlIC9QYWdlcyAvS2lkcyBbMyAwIFJdIC9Db3VudCAxID4+CmVuZG9iagozIDAgb2JqCjw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMiAwIFIgL01lZGlhQm94IFswIDAgMTAwIDEwMF0gPj4KZW5kb2JqCnhyZWYKMCA0CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU5IDAwMDAwIG4gCjAwMDAwMDAxMTYgMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA0IC9Sb290IDEgMCBSID4+CnN0YXJ0eHJlZgoxODcKJSVFT0YK',
      );
      final request = IssuanceRequest(
        institutionId: institutionId,
        actorId: actorId,
        key: certificateId,
        data: IssuanceData(
          holderId: holderId,
          title: '  Ti\u0301tulo 🎓  ',
          description: ' e\u0301 ',
          expiresAt: DateTime.parse('2030-01-02T03:04:05.123456+01:00'),
          now: DateTime.utc(2026),
        ),
        pdf: SelectedPdf(name: 'vector.pdf', bytes: pdf),
      );
      expect(
        request.digest,
        '2e6d33776958d6fcb51ec56e238fc347cca05327df127100e2c82925a7d78162',
      );
    },
  );
  test('real roles authorize only verified; blocked states explain why', () {
    for (final role in InstitutionalRole.values) {
      expect(membership(role: role).canIssue, true);
    }
    for (final state in [
      InstitutionStatus.pending,
      InstitutionStatus.rejected,
      InstitutionStatus.suspended,
    ]) {
      expect(membership(status: state).canIssue, false);
      expect(membership(status: state).blockReason, isNotEmpty);
    }
  });
  test('UUID, NFC codepoint limits, controls and stable expiration', () {
    final data = IssuanceData(
      holderId: holderId.toUpperCase(),
      title: '  Ti\u0301tulo 🎓 ',
      description: ' ',
      expiresAt: DateTime.parse('2030-01-02T03:04:05.123456+01:00'),
      now: DateTime.utc(2026),
    );
    expect(data.holderId, holderId);
    expect(data.title, 'Título 🎓');
    expect(data.description, null);
    expect(data.expiresAt, '2030-01-02T02:04:05.123456Z');
    expect(IssuanceData.titleError('🎓' * 200), null);
    for (final title in ['', 'a' * 201, 'bad\x00']) {
      expect(
        () => IssuanceData(holderId: holderId, title: title),
        throwsA(isA<IssuanceException>()),
      );
    }
    expect(
      () => IssuanceData(holderId: 'mail@example.invalid', title: 'a'),
      throwsA(isA<IssuanceException>()),
    );
    expect(
      () =>
          IssuanceData(holderId: holderId, title: 'a', description: 'a' * 4001),
      throwsA(isA<IssuanceException>()),
    );
    expect(
      () => IssuanceData(
        holderId: holderId,
        title: 'a',
        expiresAt: DateTime.utc(2000),
      ),
      throwsA(isA<IssuanceException>()),
    );
    expect(
      IssuanceData(
        holderId: holderId,
        title: 'a',
        expiresAt: DateTime.utc(2000),
        reconstructing: true,
      ).expiresAt,
      '2000-01-01T00:00:00.000000Z',
    );
    expect(isUuid(newAttemptKey()), true);
  });
  test('PDF exact 8 MiB, excess, empty, extension and immutable bytes', () {
    for (final pdf in [
      () => SelectedPdf(name: 'a.pdf', bytes: []),
      () => SelectedPdf(name: 'a.txt', bytes: [1]),
      () => SelectedPdf(name: 'a.pdf', bytes: Uint8List(maxPdfBytes + 1)),
    ]) {
      expect(pdf, throwsA(isA<IssuanceException>()));
    }
    expect(
      SelectedPdf(name: 'a.PDF', bytes: Uint8List(maxPdfBytes)).bytes.length,
      maxPdfBytes,
    );
    final source = [1, 2], pdf = SelectedPdf(name: 'a.pdf', bytes: source);
    source[0] = 9;
    expect(pdf.bytes, [1, 2]);
    expect(() => pdf.bytes[0] = 9, throwsUnsupportedError);
  });
  test(
    'single flight, persist before HTTP and clear after completion',
    () async {
      final repo = FakeIssuance()..pending = Completer<String>(),
          store = MemoryAttempts();
      final c = IssuanceController(
        userId: actorId,
        institutionId: institutionId,
        repository: repo,
        store: store,
      );
      await c.restore();
      final first = c.submit(issuanceData(), selectedPdf());
      await Future<void>.delayed(Duration.zero);
      await c.submit(issuanceData(), selectedPdf());
      expect(repo.requests.length, 1);
      expect(store.values.length, 1);
      repo.pending!.complete(certificateId);
      await first;
      expect(c.certificateId, certificateId);
      expect(store.values, isEmpty);
      c.dispose();
    },
  );
  for (final error in [
    'operation_in_progress',
    'temporary_failure',
    'response_lost',
  ]) {
    test('manual retry keeps exact request for $error', () async {
      final repo = FakeIssuance()..error = IssuanceException(error),
          store = MemoryAttempts();
      final c = IssuanceController(
        userId: actorId,
        institutionId: institutionId,
        repository: repo,
        store: store,
      );
      await c.restore();
      await c.submit(issuanceData(), selectedPdf());
      expect(c.canRetry, false);
      await c.submit(issuanceData(), selectedPdf());
      expect(repo.requests.length, 1);
      c.retryAt = DateTime.utc(2000);
      repo.error = null;
      await c.submit(issuanceData(), selectedPdf());
      expect(repo.requests.length, 2);
      expect(identical(repo.requests[0], repo.requests[1]), true);
      expect(c.certificateId, certificateId);
      c.dispose();
    });
  }
  for (final error in [
    'idempotency_conflict',
    'attempt_failed',
    'stored_object_invalid',
    'unauthenticated',
  ]) {
    test('no retry for $error', () async {
      final repo = FakeIssuance()..error = IssuanceException(error);
      final c = IssuanceController(
        userId: actorId,
        institutionId: institutionId,
        repository: repo,
        store: MemoryAttempts(),
      );
      await c.restore();
      await c.submit(issuanceData(), selectedPdf());
      await c.submit(issuanceData(), selectedPdf());
      expect(repo.requests.length, 1);
      expect(c.canRetry, false);
      expect(c.failure!.message, isNot(contains('private')));
      c.dispose();
    });
  }
  test(
    'restart requires identical reconstruction and identity isolation',
    () async {
      final store = MemoryAttempts(),
          repo = FakeIssuance()
            ..error = const IssuanceException('response_lost');
      final first = IssuanceController(
        userId: actorId,
        institutionId: institutionId,
        repository: repo,
        store: store,
      );
      await first.restore();
      await first.submit(issuanceData(), selectedPdf());
      final key = first.request!.key;
      first.dispose();
      final restored = IssuanceController(
        userId: actorId,
        institutionId: institutionId,
        repository: repo,
        store: store,
      );
      await restored.restore();
      await restored.submit(
        IssuanceData(holderId: holderId, title: 'Changed'),
        selectedPdf(),
      );
      expect(restored.failure!.code, 'reconstruction_mismatch');
      expect(repo.requests.length, 1);
      repo.error = null;
      await restored.submit(issuanceData(), selectedPdf());
      expect(repo.requests.last.key, key);
      expect(restored.certificateId, certificateId);
      restored.dispose();
      expect(await store.read(holderId, institutionId), null);
      expect(await store.read(actorId, certificateId), null);
    },
  );
  test(
    'receipt failure blocks HTTP and disposed completion stays hidden',
    () async {
      final repo = FakeIssuance(), store = MemoryAttempts()..fail = true;
      final c = IssuanceController(
        userId: actorId,
        institutionId: institutionId,
        repository: repo,
        store: store,
      );
      await c.restore();
      await c.submit(issuanceData(), selectedPdf());
      expect(repo.requests, isEmpty);
      expect(c.failure!.code, 'receipt_failure');
      c.dispose();
      store.fail = false;
      repo.pending = Completer<String>();
      final other = IssuanceController(
        userId: actorId,
        institutionId: institutionId,
        repository: repo,
        store: store,
      );
      await other.restore();
      final future = other.submit(issuanceData(), selectedPdf());
      await Future<void>.delayed(Duration.zero);
      other.dispose();
      repo.pending!.complete(certificateId);
      await future;
      expect(other.certificateId, null);
      expect(store.values, isNotEmpty);
    },
  );
  test(
    'preferences keep bounded nonsecret separated receipt with retention',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingAttemptPreferences();
      await store.save(
        actorId,
        institutionId,
        PendingAttempt(
          key: newAttemptKey(),
          digest: 'a' * 64,
          createdAt: DateTime.now(),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefs.getKeys().single)!;
      expect(raw, isNot(contains('holder_id')));
      expect(raw, isNot(contains('pdf')));
      expect(await store.read(holderId, institutionId), null);
      await store.save(
        actorId,
        certificateId,
        PendingAttempt(
          key: newAttemptKey(),
          digest: 'a' * 64,
          createdAt: DateTime.now().subtract(const Duration(days: 8)),
        ),
      );
      expect(await store.read(actorId, certificateId), null);
      for (var i = 0; i < 22; i++) {
        await store.save(
          actorId,
          'institution-$i',
          PendingAttempt(
            key: newAttemptKey(),
            digest: 'a' * 64,
            createdAt: DateTime.now(),
          ),
        );
      }
      expect(prefs.getKeys().length, lessThanOrEqualTo(20));
    },
  );
}
