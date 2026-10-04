import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/app/theme/app_theme.dart';
import 'package:mobile/features/auth/domain/auth_repository.dart';
import 'package:mobile/features/verification/domain/verification_repository.dart';
import 'package:mobile/features/verification/domain/verification_link.dart';
import 'package:mobile/features/verification/presentation/verification_controller.dart';
import 'package:mobile/features/verification/presentation/verification_screen.dart';
import 'package:mobile/features/verification/presentation/credential_share.dart';

import 'fake_auth_repository.dart';
import 'fake_wallet_repositories.dart';
import 'verification_repository_test.dart' show publicCode;

class ControlledVerification implements VerificationRepository {
  final requests = <Completer<VerificationResult>>[];
  final codes = <String>[];
  @override
  Future<VerificationResult> verify(String code) {
    codes.add(code);
    final c = Completer<VerificationResult>();
    requests.add(c);
    return c.future;
  }
}

class ControlledCredential implements CredentialRepository {
  final requests = <Completer<String?>>[];
  @override
  Future<String?> readOwnCode(String holderId, String certificateId) {
    final c = Completer<String?>();
    requests.add(c);
    return c.future;
  }
}

final dummyDate = DateTime.utc(2026, 10, 4);
VerificationResult result([
  VerificationStatus status = VerificationStatus.valid,
]) => VerificationResult(
  status,
  record: status == VerificationStatus.notFound
      ? null
      : VerifiedRecord(
          code: publicCode,
          title: 'Formación sintética',
          issuer: 'Institución sintética',
          issuedAt: dummyDate,
          expiresAt: null,
          checkedAt: dummyDate,
        ),
);

Future<void> tap(WidgetTester t, String label) async {
  final f = find.text(label);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter');
    loader.addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    loader.addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'));
    loader.addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
    loader.addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    await loader.load();
  });
  test('single-flight, edit invalidates previous result, B cannot be replaced by A, disposal', () async {
    final repo = ControlledVerification();
    final controller = VerificationController(repo)..changeCode(publicCode);
    final a = controller.submit();
    await controller.submit();
    expect(repo.requests.length, 1);
    controller.changeCode('00000000-0000-0000-0000-000000000000');
    expect(controller.result, isNull);
    final b = controller.submit();
    repo.requests[1].complete(result(VerificationStatus.notFound));
    await b;
    repo.requests[0].complete(result());
    await a;
    expect(controller.result!.status, VerificationStatus.notFound);
    controller.changeCode(publicCode);
    final d = controller.submit();
    controller.dispose();
    repo.requests.last.complete(result());
    await d;
  });
  testWidgets('Retry-After survives edit and blocks manual retry, no polling', (
    t,
  ) async {
    final repo = ControlledVerification();
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: VerificationScreen(repository: repo),
      ),
    );
    await t.enterText(find.byType(TextField), publicCode);
    await tap(t, 'Verificar');
    repo.requests.single.completeError(
      const VerificationException(
        VerificationFailure.rateLimited,
        retryAfter: Duration(seconds: 3),
      ),
    );
    await t.pump();
    expect(find.textContaining('Espera 3 segundos'), findsOneWidget);
    await tap(t, 'Consultar otro código');
    await t.enterText(find.byType(TextField), publicCode);
    await tap(t, 'Verificar');
    expect(repo.requests.length, 1);
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3100)),
    );
    await t.pump(const Duration(seconds: 3));
    expect(repo.requests.length, 1);
    await tap(t, 'Verificar');
    expect(repo.requests.length, 2);
    repo.requests.last.complete(result());
    await t.pump();
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('form validation, loading, result, refresh and new query', (
    t,
  ) async {
    final repo = ControlledVerification();
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: VerificationScreen(repository: repo),
      ),
    );
    await tap(t, 'Verificar');
    expect(find.text('Introduce un código UUID válido.'), findsOneWidget);
    expect(repo.requests, isEmpty);
    await t.enterText(find.byType(TextField), ' ${publicCode.toUpperCase()} ');
    await tap(t, 'Verificar');
    expect(find.text('Consultando el registro'), findsOneWidget);
    expect(repo.codes.single, publicCode);
    repo.requests.single.complete(result());
    await t.pump();
    expect(find.text('Registro encontrado y vigente'), findsOneWidget);
    await tap(t, 'Actualizar comprobación');
    expect(repo.requests.length, 2);
    repo.requests.last.complete(result(VerificationStatus.notFound));
    await t.pump();
    expect(
      find.text('No encontramos un registro verificable con este código'),
      findsOneWidget,
    );
    expect(
      find.text('Código del certificado'),
      findsOneWidget,
    ); // Form label only.
    expect(find.byType(SelectableText), findsNothing);
    await tap(t, 'Consultar otro código');
    expect(
      find.text('No encontramos un registro verificable con este código'),
      findsNothing,
    );
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });
  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'public result and QR fit $size text x$scale, reachable actions',
        (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final repo = ControlledVerification();
          await t.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: VerificationScreen(
                repository: repo,
                initialCode: publicCode,
              ),
            ),
          );
          repo.requests.single.complete(result());
          await t.pump();
          await t.ensureVisible(find.text('Consultar otro código'));
          expect(t.takeException(), isNull);
          final credentials = ControlledCredential(),
              changes = ChangeNotifier();
          await t.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: CredentialShare(
                    repository: credentials,
                    holderId: 'own',
                    certificateId: 'internal',
                    link: VerificationLink(
                      'http://localhost:7357',
                      allowLocalHttp: true,
                    ),
                    sessionChanges: changes,
                  ),
                ),
              ),
            ),
          );
          await tap(t, 'Mostrar QR y enlace');
          credentials.requests.single.complete(publicCode);
          await t.pump();
          await t.ensureVisible(find.text('Copiar enlace'));
          expect(
            find.text('http://localhost:7357/#/verify/$publicCode'),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          changes.dispose();
        },
      );
    }
  }
  testWidgets(
    'share code independent of id, accessible copy, session change clears and late read ignored',
    (t) async {
      final credentials = ControlledCredential(), changes = ChangeNotifier();
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CredentialShare(
                repository: credentials,
                holderId: 'own',
                certificateId: 'internal',
                link: VerificationLink('https://example.org'),
                sessionChanges: changes,
              ),
            ),
          ),
        ),
      );
      await tap(t, 'Mostrar QR y enlace');
      credentials.requests.single.complete(publicCode);
      await t.pump();
      await tap(t, 'Copiar enlace');
      await t.pump();
      expect(copied, 'https://example.org/#/verify/$publicCode');
      expect(find.text('Enlace copiado'), findsOneWidget);
      changes.notifyListeners();
      await t.pump();
      expect(find.byType(VerificationQr), findsNothing);
      await tap(t, 'Mostrar QR y enlace');
      changes.notifyListeners();
      await t.pump();
      credentials.requests.last.complete(publicCode);
      await t.pump();
      expect(find.byType(VerificationQr), findsNothing);
      await tap(t, 'Mostrar QR y enlace');
      credentials.requests.last.complete(null);
      await t.pump();
      expect(
        find.text('Este certificado no dispone de enlace verificable.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      changes.dispose();
    },
  );
  testWidgets('closing the public screen discards a late response', (t) async {
    final repo = ControlledVerification();
    await t.pumpWidget(
      MaterialApp(
        home: VerificationScreen(repository: repo, initialCode: publicCode),
      ),
    );
    expect(repo.requests.length, 1);
    await t.pumpWidget(const SizedBox());
    repo.requests.single.complete(result());
    await t.pump();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'infrastructure failures remain errors and require manual retry',
    (t) async {
      final repo = ControlledVerification();
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: VerificationScreen(repository: repo),
        ),
      );
      await t.enterText(find.byType(TextField), publicCode);
      for (final entry in {
        VerificationFailure.network:
            'No pudimos conectar. Reintenta manualmente.',
        VerificationFailure.timeout:
            'No pudimos conectar. Reintenta manualmente.',
        VerificationFailure.unavailable:
            'La comprobación está temporalmente no disponible.',
        VerificationFailure.unexpected:
            'No pudimos interpretar la respuesta. Reintenta más tarde.',
      }.entries) {
        await tap(t, 'Verificar');
        repo.requests.last.completeError(VerificationException(entry.key));
        await t.pump();
        expect(find.text(entry.value), findsOneWidget);
        expect(
          find.text('No encontramos un registro verificable con este código'),
          findsNothing,
        );
      }
      expect(repo.requests.length, 4);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('QR rendered PNG for independent decode and public semantics', (
    t,
  ) async {
    final boundary = GlobalKey();
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: const SizedBox(
              width: 280,
              height: 280,
              child: VerificationQr(
                url: 'http://localhost:7357/#/verify/$publicCode',
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('QR del enlace de verificación'),
      findsOneWidget,
    );
    final target = Platform.environment['CERTICHAIN_QR_CAPTURE'];
    if (target != null) {
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(target).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    semantics.dispose();
  });
  testWidgets(
    'public URL survives Auth restoration/error, rebuild and logout without duplicate requests',
    (t) async {
      final repo = ControlledVerification(),
          auth = FakeAuthRepository(
            currentSession: AuthSession(
              userId: 'own',
              expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
            ),
          );
      final app = CertiChainApp(
        authRepository: auth,
        profileRepository: FakeProfileRepository(),
        certificateRepository: FakeCertificateRepository(),
        verification: repo,
      );
      await t.pumpWidget(app);
      await t.binding.handlePushRoute('/verify/$publicCode');
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(repo.requests.length, 1);
      expect(find.text('Restaurando sesión'), findsNothing);
      auth.emit(testSession());
      await t.pump();
      repo.requests.single.complete(result());
      await t.pump();
      auth.events.addError(AuthFailure.network);
      await t.pump();
      expect(find.text('Registro encontrado y vigente'), findsOneWidget);
      auth.emit(null);
      await t.pump();
      await t.pumpWidget(app);
      expect(repo.requests.length, 1);
      await t.pumpWidget(const SizedBox());
      await auth.events.close();
    },
  );
}
