import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/verification/data/http_verification_repository.dart';
import 'package:mobile/core/files/picker_temporary_file.dart';
import 'package:mobile/features/verification/domain/hash_comparison.dart';
import 'package:mobile/features/verification/domain/verification_repository.dart';
import 'package:mobile/features/verification/presentation/verification_controller.dart';
import 'package:mobile/features/verification/presentation/verification_screen.dart';
import 'package:mobile/features/verification/presentation/qr_scan_controller.dart';
import 'package:mobile/features/verification/presentation/qr_scanner_panel.dart';
import 'package:mobile/features/verification/domain/qr_camera.dart';
import 'package:mobile/features/verification/domain/verification_link.dart';

import 'phase8c_test.dart'
    show
        TestRepository,
        TestPicker,
        ImmediateHasher,
        FakeCamera,
        compared,
        flush;
import 'verification_repository_test.dart' show publicCode;

class AbortProbe extends http.BaseClient {
  final started = Completer<void>();
  final aborted = Completer<void>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    started.complete();
    await (request as http.Abortable).abortTrigger;
    aborted.complete();
    throw http.ClientException('synthetic cancelled request');
  }
}

void main() {
  testWidgets(
    'permission dialog inactive state preserves the eventual denial',
    (t) async {
      final camera = FakeCamera()
        ..failure = QrCameraFailure.permissionDenied
        ..startBarrier = Completer<void>();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrScannerPanel(
              link: VerificationLink('https://example.invalid/'),
              createSession: () => ScannerSession(camera, const SizedBox()),
              onClose: () {},
              onCode: (_) {},
            ),
          ),
        ),
      );
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      camera.startBarrier!.complete();
      await t.pumpAndSettle();
      expect(find.textContaining('Permiso de cámara denegado'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  test('leaving the route aborts the production transport without notifying disposed UI', () async {
    final client = AbortProbe();
    final repo = HttpVerificationRepository(
      apiUrl: 'https://example.invalid',
      client: client,
    );
    final controller = VerificationController(repo)..changeCode(publicCode);
    final pending = controller.submit();
    await client.started.future;
    controller.dispose();
    await client.aborted.future;
    await pending;
    expect(controller.result, isNull);
    repo.close();
  });
  for (final system in ['android', 'ios']) {
    test(
      'native $system cleans only its selected copy, never originals or other selections',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'certichain-8d-files-',
        );
        try {
          final folder = system == 'android'
              ? 'file_picker/123456'
              : 'a1111111-2222-4333-8444-555555555555';
          final parent = await Directory('${root.path}/$folder')
              .create(recursive: true);
          final selected = await File('${parent.path}/selected.pdf')
              .writeAsBytes([0, 255, 13]);
          final other = await File('${parent.path}/other.pdf')
              .writeAsBytes([1]);
          final original = await File('${root.path}/original.pdf')
              .writeAsBytes([2]);
          await removePickerTemporaryFile(
            selected.path,
            temporaryDirectory: root,
            operatingSystem: system,
          );
          expect(await selected.exists(), false);
          expect(await other.readAsBytes(), [1]);
          expect(await original.readAsBytes(), [2]);
          await removePickerTemporaryFile(
            original.path,
            temporaryDirectory: root,
            operatingSystem: system,
          );
          expect(await original.exists(), true);
          await removePickerTemporaryFile(
            other.path,
            temporaryDirectory: root,
            operatingSystem: system,
          );
          expect(await parent.exists(), false);
        } finally {
          await root.delete(recursive: true);
        }
      },
    );
  }
  test(
    'Android code_cache temp root cleans only the sibling picker cache',
    () async {
      final app = await Directory.systemTemp.createTemp('certichain-8d-app-');
      try {
        final codeCache = await Directory('${app.path}/code_cache').create();
        final folder = await Directory('${app.path}/cache/file_picker/123456')
            .create(recursive: true);
        final copy = await File('${folder.path}/copy.pdf').writeAsBytes([1]);
        final original = await File('${app.path}/cache/original.pdf')
            .writeAsBytes([2]);
        await removePickerTemporaryFile(
          copy.path,
          temporaryDirectory: codeCache,
          operatingSystem: 'android',
        );
        expect(await copy.exists(), false);
        expect(await original.readAsBytes(), [2]);
      } finally {
        await app.delete(recursive: true);
      }
    },
  );
  test('desktop selected original is never deleted', () async {
    final root = await Directory.systemTemp.createTemp(
      'certichain-8d-original-',
    );
    try {
      final file = await File('${root.path}/original.pdf').writeAsBytes([1]);
      await removePickerTemporaryFile(
        file.path,
        temporaryDirectory: root,
        operatingSystem: 'windows',
      );
      expect(await file.exists(), true);
    } finally {
      await root.delete(recursive: true);
    }
  });
  for (var iteration = 0; iteration < 3; iteration++) {
    test(
      'comparison failure preserves marked previous checked_at and explicit recovery $iteration',
      () async {
        final repo = TestRepository(), picker = TestPicker();
        final c = VerificationController(
          repo,
          comparisonRepository: repo,
          picker: picker,
          hasher: ImmediateHasher(),
        )..changeCode(publicCode);
        await c.submit();
        final checked = c.result!.record!.checkedAt;
        final pending = c.selectAndCompare();
        picker.requests.last.complete(Uint8List.fromList([1]));
        await flush();
        expect(c.resultIsPrevious, true);
        expect(c.integrity, isNull);
        repo.comparisons.last.completeError(
          const VerificationException(VerificationFailure.unavailable),
        );
        await pending;
        expect(c.comparisonFailure, VerificationFailure.unavailable);
        expect(c.resultIsPrevious, true);
        expect(c.result!.record!.checkedAt, checked);
        expect(repo.comparisons.length, 1);
        final retry = c.retryComparison();
        repo.comparisons.last.complete(compared(status: 'revoked'));
        await retry;
        expect(c.resultIsPrevious, false);
        expect(c.result!.status, VerificationStatus.revoked);
        expect(c.integrity, FileIntegrity.match);
        c.dispose();
      },
    );
    test(
      'cancel/read/dispose late bytes and response do not query or notify $iteration',
      () async {
        final repo = TestRepository(), picker = TestPicker();
        final c = VerificationController(
          repo,
          comparisonRepository: repo,
          picker: picker,
          hasher: ImmediateHasher(),
        )..changeCode(publicCode);
        await c.submit();
        final reading = c.selectAndCompare();
        c.cancelComparison();
        picker.requests.last.complete(Uint8List(8));
        await reading;
        expect(repo.comparisons, isEmpty);
        final query = c.selectAndCompare();
        picker.requests.last.complete(Uint8List.fromList([2]));
        await flush();
        c.dispose();
        repo.comparisons.last.complete(compared());
        await query;
        expect(c.integrity, isNull);
        expect(picker.cancellations, greaterThan(1));
      },
    );
  }
  test(
    'camera deny, grant, background/resume, permission revocation and disposal',
    () async {
      final camera = FakeCamera()..failure = QrCameraFailure.permissionDenied;
      final c = QrScanController(
        camera,
        VerificationLink('https://example.invalid/'),
      );
      await c.start();
      expect(c.failure, QrCameraFailure.permissionDenied);
      camera.failure = null;
      await c.start();
      expect(c.phase, QrScanPhase.reading);
      await c.pause();
      expect(c.phase, QrScanPhase.paused);
      camera.failure = QrCameraFailure.permissionDenied;
      await c.start();
      expect(c.failure, QrCameraFailure.permissionDenied);
      c.dispose();
      await flush();
      expect(camera.disposals, 1);
      expect(camera.events.isClosed, true);
    },
  );
  testWidgets(
    'small screen text x2, previous snapshot and error semantics remain separate',
    (t) async {
      final repo = TestRepository(), picker = TestPicker();
      final semantics = t.ensureSemantics();
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(
        () => {t.view.resetPhysicalSize(), t.view.resetDevicePixelRatio()},
      );
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: VerificationScreen(
              repository: repo,
              initialCode: publicCode,
              comparisonRepository: repo,
              comparisonPicker: picker,
              pdfHasher: ImmediateHasher(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Comparar mi PDF'));
      await t.tap(find.text('Comparar mi PDF'));
      await t.pump();
      picker.requests.last.complete(Uint8List.fromList([1]));
      await t.runAsync(flush);
      await t.pump();
      repo.comparisons.last.completeError(
        const VerificationException(VerificationFailure.unavailable),
      );
      await t.runAsync(flush);
      await t.pump();
      expect(find.textContaining('Resultado anterior.'), findsOneWidget);
      expect(find.textContaining('Consulta anterior:'), findsOneWidget);
      expect(
        find.text('La comparación está temporalmente no disponible.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
  testWidgets(
    'repeated QR detections and double confirmation invoke one action',
    (t) async {
      final camera = FakeCamera();
      var confirmations = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrScannerPanel(
              link: VerificationLink('https://example.invalid/'),
              createSession: () => ScannerSession(camera, const SizedBox()),
              onClose: () {},
              onCode: (_) => confirmations++,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      camera.events.add(publicCode);
      camera.events.add(publicCode);
      await t.pump();
      await t.tap(find.text('Verificar código identificado'));
      await t.tap(find.text('Verificar código identificado'));
      expect(confirmations, 1);
      // Resource lifecycle itself is checked by the controller test above.
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
