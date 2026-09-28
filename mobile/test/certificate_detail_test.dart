import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/domain/auth_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_repository.dart';
import 'package:mobile/features/certificates/presentation/certificate_detail_screen.dart';
import 'package:mobile/features/certificates/presentation/certificate_card.dart';
import 'package:mobile/features/profile/domain/profile_repository.dart';

import 'fake_auth_repository.dart';
import 'fake_wallet_repositories.dart';

Certificate certificate({
  String title = 'Formación de prueba',
  CertificateStatus status = CertificateStatus.active,
  DateTime? expiresAt,
}) => Certificate(
  id: '11111111-2222-3333-4444-555555555555',
  holderId: 'synthetic-user',
  institutionId: 'institution',
  title: title,
  issuedAt: DateTime(2026, 1, 2),
  status: status,
  expiresAt: expiresAt,
);

void main() {
  late FakeAuthRepository auth;
  late FakeCertificateRepository certificates;
  late FakeProfileRepository profiles;

  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    auth = FakeAuthRepository(currentSession: testSession());
    profiles = FakeProfileRepository();
    certificates = FakeCertificateRepository()
      ..wallet = CertificateWallet(certificates: [certificate()], total: 1);
  });
  tearDown(() async => auth.events.close());

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: CertiChainApp(
          authRepository: auth,
          profileRepository: profiles,
          certificateRepository: certificates,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async =>
      tap(tester, find.text(certificates.wallet.certificates.first.title));

  for (final origin in ['Inicio', 'Certificados']) {
    testWidgets(
      'opens fresh detail from $origin and returns to its original destination',
      (tester) async {
        final reads = <(String, String)>[];
        certificates.detailHandler = (userId, id) async {
          reads.add((userId, id));
          return certificate();
        };
        await start(tester);
        if (origin == 'Certificados') {
          await tap(tester, find.text('Certificados'));
        }
        await open(tester);
        expect(find.byType(CertificateDetailScreen), findsOneWidget);
        expect(find.text('Detalle del certificado'), findsOneWidget);
        expect(reads, [('synthetic-user', certificate().id)]);
        expect(find.text('Institución no disponible'), findsOneWidget);
        expect(find.text('Sin fecha de expiración'), findsOneWidget);
        expect(find.text('Vista previa no disponible'), findsOneWidget);
        final share = tester.widget<AppButton>(find.byType(AppButton));
        expect(share.onPressed, isNull);
        expect(find.textContaining('No acredita verificación'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(CertificateDetailScreen), findsNothing);
        expect(
          find.text(
            origin == 'Inicio' ? 'Hola, Ana del perfil' : 'Mis certificados',
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'loading, missing and error are distinct; retry presents actual fields',
    (tester) async {
      final pending = Completer<Certificate?>();
      certificates.detailHandler = (_, _) => pending.future;
      await start(tester);
      await tester.ensureVisible(find.text('Formación de prueba'));
      await tester.tap(find.text('Formación de prueba'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.bySemanticsLabel('Cargando certificado'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CertificateDetailScreen),
          matching: find.text('Formación de prueba'),
        ),
        findsNothing,
      );
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Certificado no disponible'), findsOneWidget);
      certificates.detailHandler = (_, _) async =>
          throw StateError('private SQL token payload');
      await tap(tester, find.text('Reintentar'));
      expect(find.text('No pudimos cargar este certificado.'), findsOneWidget);
      expect(find.textContaining('private SQL'), findsNothing);
      certificates.detailHandler = (_, _) async => certificate(
        status: CertificateStatus.revoked,
        expiresAt: DateTime(2020),
      );
      await tap(tester, find.text('Reintentar'));
      expect(find.text('Revocado'), findsOneWidget);
      expect(find.text('Expirado'), findsNothing);
      expect(find.text('Expira: 01/01/2020'), findsOneWidget);
    },
  );

  testWidgets('consecutive card activations open a single detail route', (
    tester,
  ) async {
    var reads = 0;
    certificates.detailHandler = (_, _) async {
      reads++;
      return certificate();
    };
    await start(tester);
    final card = tester.widget<CertificateCard>(find.byType(CertificateCard));
    card.onOpen();
    card.onOpen();
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(CertificateDetailScreen), findsNothing);
    expect(find.text('Hola, Ana del perfil'), findsOneWidget);
  });

  testWidgets('tabs explicitly describe absent blockchain and history', (
    tester,
  ) async {
    await start(tester);
    await open(tester);
    await tap(tester, find.text('Blockchain'));
    expect(find.text('Sin datos de blockchain'), findsOneWidget);
    expect(find.textContaining('0x'), findsNothing);
    await tap(tester, find.text('Historial'));
    expect(find.text('Historial no disponible'), findsOneWidget);
    await tap(tester, find.text('Detalles'));
    expect(find.text(certificate().id), findsOneWidget);
  });

  testWidgets(
    'token refresh preserves detail; refresh hides stale data and ignores superseded replies',
    (tester) async {
      var reads = 0;
      final slow = Completer<Certificate?>();
      final newest = Completer<Certificate?>();
      certificates.detailHandler = (_, _) {
        reads++;
        return reads == 1
            ? Future.value(certificate())
            : reads == 2
            ? slow.future
            : newest.future;
      };
      await start(tester);
      await open(tester);
      auth.emit(testSession());
      await tester.pumpAndSettle();
      expect(find.byType(CertificateDetailScreen), findsOneWidget);
      expect(reads, 1);
      await tester.tap(find.byTooltip('Actualizar datos'));
      await tester.pump();
      expect(find.text('Formación de prueba'), findsNothing);
      await tester.tap(find.byTooltip('Actualizar datos'));
      await tester.pump();
      slow.complete(certificate(title: 'Respuesta obsoleta'));
      await tester.pump();
      expect(find.text('Respuesta obsoleta'), findsNothing);
      newest.complete(certificate(title: 'Respuesta vigente'));
      await tester.pumpAndSettle();
      expect(find.text('Respuesta vigente'), findsOneWidget);
    },
  );

  for (final change in ['identity', 'logout']) {
    testWidgets('$change removes detail and discards late private responses', (
      tester,
    ) async {
      final pending = Completer<Certificate?>();
      certificates.detailHandler = (_, _) => pending.future;
      certificates.handler = (userId) async => userId == 'synthetic-user'
          ? certificates.wallet
          : CertificateWallet(certificates: [], total: 0);
      profiles.handler = (userId) async => userId == 'synthetic-user'
          ? profiles.profile
          : const UserProfile(
              id: 'second',
              fullName: 'Segunda persona',
              role: 'holder',
            );
      await start(tester);
      await tester.ensureVisible(find.text('Formación de prueba'));
      await tester.tap(find.text('Formación de prueba'));
      await tester.pump();
      auth.emit(
        change == 'logout'
            ? null
            : AuthSession(
                userId: 'second',
                expiresAt: DateTime.now().add(const Duration(hours: 1)),
              ),
      );
      await tester.pumpAndSettle();
      pending.complete(certificate(title: 'Certificado privado anterior'));
      await tester.pumpAndSettle();
      expect(find.byType(CertificateDetailScreen), findsNothing);
      expect(find.textContaining('privado anterior'), findsNothing);
      expect(find.text('Formación de prueba'), findsNothing);
      if (change == 'identity') {
        expect(find.text('Hola, Segunda persona'), findsOneWidget);
        expect(find.text('Hola, Ana del perfil'), findsNothing);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CertificateDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resuming detail reloads current revocation', (tester) async {
    var reads = 0;
    certificates.detailHandler = (_, _) async => certificate(
      status: ++reads == 1
          ? CertificateStatus.active
          : CertificateStatus.revoked,
    );
    await start(tester);
    await open(tester);
    expect(find.text('Válido'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Revocado'), findsOneWidget);
    expect(reads, 2);
  });

  for (final (width, height, scale) in [
    (390.0, 844.0, 1.0),
    (360.0, 800.0, 1.0),
    (320.0, 568.0, 1.0),
    (390.0, 844.0, 2.0),
    (320.0, 568.0, 2.0),
  ]) {
    testWidgets(
      'four screens and detail tabs fit ${width}x$height at text scale $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (scale > 1) {
          certificates.wallet = CertificateWallet(
            certificates: [
              certificate(
                title: 'Un título largo de formación para comprobar el ajuste del texto',
                expiresAt: DateTime(2020),
              ),
            ],
            total: 1,
          );
        }
        await start(tester);
        await capture(tester, 'home-$width-$scale');
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Certificados'));
        await capture(tester, 'wallet-$width-$scale');
        expect(tester.takeException(), isNull);
        await open(tester);
        await capture(tester, 'detail-$width-$scale');
        expect(tester.takeException(), isNull);
        for (final label in ['Blockchain', 'Historial', 'Detalles']) {
          await tap(tester, find.text(label));
          expect(tester.takeException(), isNull);
        }
        // Scroll to the last real detail field: it remains reachable at large text.
        await tester.ensureVisible(find.text(certificate().id));
        await tester.pumpAndSettle();
        expect(find.text(certificate().id).hitTestable(), findsOneWidget);
        await capture(tester, 'detail-bottom-$width-$scale');
        await tester.tap(find.byTooltip('Volver'));
        await tester.pumpAndSettle();
        await tap(tester, find.text('Perfil'));
        await capture(tester, 'profile-$width-$scale');
        await tester.ensureVisible(find.text('Cerrar sesión'));
        await tester.pumpAndSettle();
        expect(find.text('Cerrar sesión').hitTestable(), findsOneWidget);
        await capture(tester, 'profile-bottom-$width-$scale');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['CERTICHAIN_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
