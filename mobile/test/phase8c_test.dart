import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile/features/verification/data/mobile_scanner_camera.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/app/theme/app_theme.dart';
import 'package:mobile/core/files/bounded_local_file.dart';
import 'package:mobile/features/verification/domain/hash_comparison.dart';
import 'package:mobile/features/verification/domain/qr_camera.dart';
import 'package:mobile/features/verification/domain/verification_link.dart';
import 'package:mobile/features/verification/domain/verification_repository.dart';
import 'package:mobile/features/verification/data/http_verification_repository.dart';
import 'package:mobile/features/verification/data/sha256_pdf_hasher.dart';
import 'package:mobile/features/verification/presentation/verification_controller.dart';
import 'package:mobile/features/verification/presentation/verification_screen.dart';
import 'package:mobile/features/verification/presentation/qr_scan_controller.dart';
import 'package:mobile/features/verification/presentation/qr_scanner_panel.dart';
import 'package:mobile/features/verification/presentation/public_query_cooldown.dart';

import 'verification_repository_test.dart' show publicCode, publicDto, failure;

class FakeCamera implements QrCamera {
  final events = StreamController<String>.broadcast(sync: true);
  int starts = 0, stops = 0, disposals = 0;
  QrCameraFailure? failure;
  Completer<void>? startBarrier;
  @override
  Stream<String> get detections => events.stream;
  @override
  Future<void> start() async {
    starts++;
    await startBarrier?.future;
    if (failure != null) throw QrCameraException(failure!);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await events.close();
  }
}

class TestScannerPlugin extends MobileScannerController {
  final events = StreamController<BarcodeCapture>.broadcast();
  int stops = 0, disposals = 0;
  @override
  Stream<BarcodeCapture> get barcodes => events.stream;
  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {}
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await events.close();
    try {
      await super.dispose();
    } on MissingPluginException {
      // Hardware platform is deliberately absent in this controller fake.
    } on UnsupportedError {
      // Native scanner is not supported by the Windows VM runner.
    }
    throw StateError('synthetic platform disposal failure');
  }
}

class TestPicker implements ComparisonPdfPicker {
  final requests = <Completer<Uint8List?>>[];
  int cancellations = 0;
  @override
  Future<Uint8List?> pick() {
    final c = Completer<Uint8List?>();
    requests.add(c);
    return c.future;
  }

  @override
  void cancel() {
    cancellations++;
  }
}

class ImmediateHasher implements PdfHasher {
  @override
  Future<String> hash(Uint8List bytes, {bool Function()? isCancelled}) async =>
      bytes.first.toRadixString(16).padLeft(64, '0');
}

class TestRepository
    implements VerificationRepository, HashComparisonRepository {
  final comparisons = <Completer<HashComparison>>[];
  final hashes = <String>[];
  int verifies = 0;
  @override
  Future<VerificationResult> verify(String code) async {
    verifies++;
    return HttpVerificationRepository.decodeResult(publicDto(), code);
  }

  @override
  Future<HashComparison> compare(String code, String digest) {
    hashes.add(digest);
    final c = Completer<HashComparison>();
    comparisons.add(c);
    return c.future;
  }
}

HashComparison compared({
  String status = 'valid',
  FileIntegrity integrity = FileIntegrity.match,
}) => HashComparison(
  HttpVerificationRepository.decodeResult(
    publicDto(result: status),
    publicCode,
  ),
  integrity,
);
Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 20));
Map<String, Object?> dto({
  String state = 'valid',
  String integrity = 'match',
}) => {
  'schema_version': '1',
  'verification': state == 'not_found'
      ? {'schema_version': '1', 'result': 'not_found'}
      : publicDto(result: state),
  'file_integrity': integrity,
};

void main() {
  final link = VerificationLink('https://certichain.example/app/');
  test('8B canonical QR, direct UUID and strict trust/base/size/encoding', () {
    expect(link.codeFromQr(link.forCode(publicCode)), publicCode);
    final encodedBase = VerificationLink(
      'https://certichain.example/my%20app/',
    );
    expect(encodedBase.codeFromQr(encodedBase.forCode(publicCode)), publicCode);
    expect(link.codeFromQr(publicCode.toUpperCase()), publicCode);
    expect(link.codeFromQr(link.forCode(publicCode.toUpperCase())), publicCode);
    for (final bad in [
      '',
      ' $publicCode',
      '$publicCode\n',
      'x' * 2049,
      'https://evil.example/app/#/verify/$publicCode',
      'https://certichain.example/#/verify/$publicCode',
      'http://certichain.example/app/#/verify/$publicCode',
      'https://user@certichain.example/app/#/verify/$publicCode',
      'https://certichain.example/app/?x=1#/verify/$publicCode',
      'https://certichain.example/app/#/verify/$publicCode?x=1',
      'https://certichain.example/app/#/verify/%65${publicCode.substring(1)}',
      'https://certichain.example/app/../app/#/verify/$publicCode',
      'https://certichain.example/app/#/verify/$publicCode/',
      'javascript:alert(1)',
      '{$publicCode}',
      publicCode.replaceAll('-', ''),
    ]) {
      expect(link.codeFromQr(bad), isNull, reason: bad);
    }
  });
  test('SHA-256 known vector and exact binary byte mutations', () async {
    final hasher = Sha256PdfHasher();
    expect(
      await hasher.hash(Uint8List.fromList(utf8.encode('abc'))),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    final bytes = Uint8List.fromList([0, 255, 128, 13, 10, 0, 1]);
    final original = await hasher.hash(bytes);
    expect(
      original,
      'fb329f8defe047af577e860c6a44adcd49c1f2106b41234d93cf69bda0c3ae33',
    );
    expect(await hasher.hash(Uint8List.fromList(bytes)), original);
    bytes[3] ^= 1;
    expect(await hasher.hash(bytes), isNot(original));
    expect(() => validateComparisonBytes(0), throwsA(isA<LocalPdfException>()));
    expect(
      () => validateComparisonBytes(8388609),
      throwsA(isA<LocalPdfException>()),
    );
    expect(() => validateComparisonBytes(8388608), returnsNormally);
    expect((await hasher.hash(Uint8List(8388608))).length, 64);
  });
  test(
    'hash yields and cancels without processing a superseded file',
    () async {
      var checks = 0;
      await expectLater(
        Sha256PdfHasher().hash(
          Uint8List(comparisonPdfLimit),
          isCancelled: () => ++checks > 2,
        ),
        throwsA(isA<PdfHashCancelled>()),
      );
      expect(checks, 3);
    },
  );
  test(
    'late budget block during file selection prevents a new request',
    () async {
      var now = DateTime.utc(2026, 10, 5);
      final budget = PublicQueryCooldown(clock: () => now);
      final repo = TestRepository(), picker = TestPicker();
      final c = VerificationController(
        repo,
        comparisonRepository: repo,
        picker: picker,
        hasher: ImmediateHasher(),
        cooldown: budget,
      )..changeCode(publicCode);
      await c.submit();
      final selection = c.selectAndCompare();
      budget.block(const Duration(seconds: 2));
      picker.requests.last.complete(Uint8List.fromList([1]));
      await selection;
      expect(repo.comparisons, isEmpty);
      expect(c.comparisonFailure, VerificationFailure.rateLimited);
      await c.retryComparison();
      expect(repo.comparisons, isEmpty);
      now = now.add(const Duration(seconds: 3));
      final retry = c.retryComparison();
      final duplicate = c.retryComparison();
      expect(repo.comparisons.length, 1);
      repo.comparisons.last.complete(compared());
      await retry;
      await duplicate;
      c.dispose();
      budget.dispose();
    },
  );
  test('shared native byte reader cancels stream on limit, keeps binary bytes and honors cancellation', () async {
    final bytes = await readBoundedLocalFile(
      Stream.fromIterable([
        Uint8List.fromList([0, 255]),
        Uint8List.fromList([13, 10]),
      ]),
      4,
    );
    expect(bytes, [0, 255, 13, 10]);
    var consumed = 0;
    Stream<Uint8List> chunks() async* {
      consumed++;
      yield Uint8List(4);
      consumed++;
      yield Uint8List(1);
      consumed++;
      yield Uint8List(100);
    }

    await expectLater(
      readBoundedLocalFile(chunks(), 4),
      throwsA(isA<LocalFileReadException>()),
    );
    expect(consumed, 2);
    expect(
      await readBoundedLocalFile(
        Stream.value(Uint8List(4)),
        4,
        cancelled: () => true,
      ),
      isEmpty,
    );
  });
  test(
    'production adapter forwards decoder stream failure safely and releases',
    () async {
      final plugin = TestScannerPlugin();
      final camera = MobileScannerCamera(controller: plugin);
      final scan = QrScanController(camera, link);
      await scan.start();
      plugin.events.addError(StateError('private decoder detail'));
      await flush();
      expect(scan.failure, QrCameraFailure.failed);
      expect(scan.phase, QrScanPhase.error);
      expect(plugin.stops, greaterThan(0));
      scan.dispose();
      await flush();
      expect(plugin.disposals, 1);
    },
  );
  for (final f in QrCameraFailure.values) {
    test('camera error $f with resource disposal', () async {
      final camera = FakeCamera()..failure = f;
      final scan = QrScanController(camera, link);
      expect(camera.starts, 0);
      await scan.start();
      expect(scan.failure, f);
      scan.dispose();
      await flush();
      expect(camera.disposals, 1);
    });
  }
  test(
    'unknown/repeated QR accepts once, stops, ignores disposed events',
    () async {
      final camera = FakeCamera();
      final scan = QrScanController(camera, link);
      await scan.start();
      camera.events.add('https://evil.example');
      expect(scan.unknown, true);
      camera.events.add(link.forCode(publicCode));
      camera.events.add(link.forCode(publicCode));
      expect(scan.code, publicCode);
      expect(scan.phase, QrScanPhase.found);
      expect(camera.stops, 1);
      scan.dispose();
      await flush();
      expect(camera.disposals, 1);
    },
  );
  test('pause/dispose while permission pending stops late camera without callbacks', () async {
    final camera = FakeCamera()..startBarrier = Completer<void>();
    final scan = QrScanController(camera, link);
    final start = scan.start();
    final pause = scan.pause();
    scan.dispose();
    camera.startBarrier!.complete();
    await start;
    await pause;
    await flush();
    expect(camera.disposals, 1);
    expect(camera.stops, greaterThan(0));
  });
  test('comparison replacement, cancellation, code change and out of order responses', () async {
    final repo = TestRepository(), picker = TestPicker();
    final c = VerificationController(
      repo,
      comparisonRepository: repo,
      picker: picker,
      hasher: ImmediateHasher(),
    )..changeCode(publicCode);
    await c.submit();
    final a = c.selectAndCompare();
    picker.requests.last.complete(Uint8List.fromList([1]));
    await flush();
    expect(repo.comparisons.length, 1);
    final b = c.selectAndCompare();
    picker.requests.last.complete(Uint8List.fromList([2]));
    await flush();
    repo.comparisons[1].complete(compared(status: 'revoked'));
    await b;
    repo.comparisons[0].complete(
      compared(integrity: FileIntegrity.integrityMismatch),
    );
    await a;
    expect(c.integrity, FileIntegrity.match);
    expect(c.result!.status, VerificationStatus.revoked);
    expect(repo.hashes[0], isNot(repo.hashes[1]));
    final cancel = c.selectAndCompare();
    picker.requests.last.complete(null);
    await cancel;
    expect(c.comparisonPhase, ComparisonPhase.cancelled);
    expect(c.integrity, isNull);
    final old = c.selectAndCompare();
    picker.requests.last.complete(Uint8List.fromList([3]));
    await flush();
    c.changeCode('00000000-0000-0000-0000-000000000000');
    repo.comparisons.last.complete(compared());
    await old;
    expect(c.result, isNull);
    expect(c.integrity, isNull);
    c.dispose();
    expect(picker.cancellations, greaterThan(0));
  });
  testWidgets(
    'late 429 shares cooldown across verify/compare/reopened controller',
    (t) async {
      var now = DateTime.utc(2026, 10, 5);
      final budget = PublicQueryCooldown(clock: () => now),
          repo = TestRepository(),
          picker = TestPicker();
      final c = VerificationController(
        repo,
        comparisonRepository: repo,
        picker: picker,
        hasher: ImmediateHasher(),
        cooldown: budget,
      )..changeCode(publicCode);
      await c.submit();
      final a = c.selectAndCompare();
      picker.requests.last.complete(Uint8List.fromList([1]));
      await t.runAsync(flush);
      c.cancelComparison();
      repo.comparisons.last.completeError(
        const VerificationException(
          VerificationFailure.rateLimited,
          retryAfter: Duration(seconds: 2),
        ),
      );
      await a;
      expect(c.waitSeconds, 2);
      await c.submit();
      expect(repo.verifies, 1);
      c.dispose();
      final reopened = VerificationController(repo, cooldown: budget)
        ..changeCode(publicCode);
      expect(reopened.canSubmit, false);
      now = now.add(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      expect(reopened.canSubmit, true);
      reopened.dispose();
      budget.dispose();
    },
  );
  for (final state in [
    'valid',
    'expired',
    'revoked',
    'issuer_unavailable',
    'not_found',
  ]) {
    for (final integrity
        in state == 'not_found'
            ? ['unavailable']
            : ['match', 'integrity_mismatch']) {
      test(
        'closed transport $state/$integrity, only code/hash/no credentials',
        () async {
          final repo = HttpVerificationRepository(
            apiUrl: 'https://api.example',
            client: MockClient((request) async {
              expect(
                request.url.path,
                '/functions/v1/compare-certificate-hash',
              );
              expect(
                request.headers.keys
                    .map((k) => k.toLowerCase())
                    .any(
                      (k) => ['authorization', 'apikey', 'cookie'].contains(k),
                    ),
                false,
              );
              expect(jsonDecode(request.body), {
                'credential_code': publicCode,
                'document_sha256': 'a' * 64,
              });
              return http.Response(
                jsonEncode(dto(state: state, integrity: integrity)),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          );
          final result = await repo.compare(publicCode, 'a' * 64);
          expect(result.integrity.name, switch (integrity) {
            'integrity_mismatch' => 'integrityMismatch',
            _ => integrity,
          });
        },
      );
    }
  }
  test(
    'comparison rejects widening/inconsistent/excess/timeout and HTTP errors',
    () async {
      for (final body in [
        dto()..['document_hash'] = 'a' * 64,
        dto()..['schema_version'] = 1,
        dto(state: 'not_found'),
        dto(integrity: 'unavailable'),
        'x' * 8193,
      ]) {
        final repo = HttpVerificationRepository(
          apiUrl: 'https://api.example',
          client: MockClient(
            (_) async => http.Response(
              body is String ? body : jsonEncode(body),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
        await expectLater(
          repo.compare(publicCode, 'a' * 64),
          throwsA(failure(VerificationFailure.unexpected)),
        );
      }
      for (final (status, f) in [
        (400, VerificationFailure.invalidInput),
        (429, VerificationFailure.rateLimited),
        (503, VerificationFailure.unavailable),
        (405, VerificationFailure.unexpected),
      ]) {
        final repo = HttpVerificationRepository(
          apiUrl: 'https://api.example',
          client: MockClient((_) async => http.Response('{}', status)),
        );
        await expectLater(
          repo.compare(publicCode, 'a' * 64),
          throwsA(failure(f)),
        );
      }
      final repo = HttpVerificationRepository(
        apiUrl: 'https://api.example',
        timeout: const Duration(milliseconds: 1),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(jsonEncode(dto()), 200);
        }),
      );
      await expectLater(
        repo.compare(publicCode, 'a' * 64),
        throwsA(failure(VerificationFailure.timeout)),
      );
      expect(
        () => repo.compare(publicCode, 'A' * 64),
        throwsA(failure(VerificationFailure.invalidInput)),
      );
      expect(
        () => repo.compare(publicCode, '${'a' * 64}\n'),
        throwsA(failure(VerificationFailure.invalidInput)),
      );
    },
  );
  testWidgets(
    'small screen/text x2 scanner manual alternative, revoked and matching PDF',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final camera = FakeCamera()..failure = QrCameraFailure.permissionDenied;
      final repo = TestRepository(), picker = TestPicker();
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
              verificationLink: link,
              scannerFactory: () => ScannerSession(camera, const SizedBox()),
              initialCode: publicCode,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Escanear QR'));
      await t.tap(find.text('Escanear QR'));
      await t.pumpAndSettle();
      expect(find.textContaining('Permiso de cámara denegado'), findsOneWidget);
      final close = find.widgetWithText(
        TextButton,
        'Cancelar escáner · Introducir código',
      );
      await t.ensureVisible(close);
      await t.tap(close);
      await t.pumpAndSettle();
      expect(find.byType(QrScannerPanel), findsNothing);
      await t.runAsync(flush);
      for (var i = 0; i < 10 && camera.disposals == 0; i++) {
        await t.pump(const Duration(milliseconds: 10));
      }
      expect(camera.disposals, 1);
      await t.ensureVisible(find.text('Comparar mi PDF'));
      await t.tap(find.text('Comparar mi PDF'));
      await t.pump();
      picker.requests.last.complete(Uint8List.fromList([1]));
      await t.runAsync(flush);
      await t.pump();
      repo.comparisons.last.complete(compared(status: 'revoked'));
      await t.pumpAndSettle();
      expect(find.text('Certificado revocado'), findsOneWidget);
      expect(
        find.text('El PDF coincide byte a byte con el documento registrado.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
}
