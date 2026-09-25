import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/features/auth/domain/auth_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_repository.dart';
import 'package:mobile/features/profile/domain/profile_repository.dart';

import 'fake_auth_repository.dart';
import 'fake_wallet_repositories.dart';

Certificate sample({
  String title = 'Título real sintético',
  CertificateStatus status = CertificateStatus.active,
  DateTime? expiresAt,
  String? institutionName,
}) => Certificate(
  id: title,
  holderId: 'synthetic-user',
  institutionId: 'institution',
  title: title,
  issuedAt: DateTime(2026, 1, 2),
  status: status,
  expiresAt: expiresAt,
  institutionName: institutionName,
);

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeCertificateRepository certificates;

  setUp(() {
    auth = FakeAuthRepository(currentSession: testSession());
    profiles = FakeProfileRepository();
    certificates = FakeCertificateRepository();
  });
  tearDown(() async {
    await auth.events.close();
  });

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      CertiChainApp(
        authRepository: auth,
        profileRepository: profiles,
        certificateRepository: certificates,
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'home greets backend profile, wallet empty, profile and back navigation work',
    (tester) async {
      await start(tester);
      expect(find.text('Hola, Ana del perfil'), findsOneWidget);
      await tap(tester, 'Certificados');
      expect(find.text('Aún no tienes certificados'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Hola, Ana del perfil'), findsOneWidget);
      await tap(tester, 'Perfil');
      expect(find.text('Ana del perfil'), findsOneWidget);
      expect(find.text('Estudiante'), findsOneWidget);
      expect(find.textContaining('Edición no disponible'), findsOneWidget);
    },
  );

  testWidgets(
    'missing profile is recoverable and never substitutes auth metadata',
    (tester) async {
      profiles.profile = null;
      await start(tester);
      expect(
        find.textContaining('Tu perfil no está disponible.'),
        findsOneWidget,
      );
      expect(find.textContaining('Hola,'), findsNothing);
      profiles.profile = const UserProfile(
        id: 'synthetic-user',
        fullName: 'Perfil reparado',
        role: 'holder',
      );
      await tap(tester, 'Reintentar');
      expect(find.text('Hola, Perfil reparado'), findsOneWidget);
    },
  );

  testWidgets('profile loading and error are safe and retryable', (
    tester,
  ) async {
    final pending = Completer<UserProfile?>();
    profiles.handler = (_) => pending.future;
    await start(tester);
    expect(find.bySemanticsLabel('Cargando perfil'), findsOneWidget);
    pending.completeError(StateError('private secret payload'));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar tu perfil.'), findsOneWidget);
    expect(find.textContaining('private secret'), findsNothing);
    profiles.handler = null;
    await tap(tester, 'Reintentar');
    expect(find.text('Hola, Ana del perfil'), findsOneWidget);
  });

  testWidgets('home and wallet share loading and error with retry', (
    tester,
  ) async {
    final pending = Completer<CertificateWallet>();
    certificates.handler = (_) => pending.future;
    await start(tester);
    await tester.tap(find.text('Certificados'));
    await tester.pump();
    expect(find.bySemanticsLabel('Cargando certificados'), findsOneWidget);
    pending.completeError(StateError('private SQL payload'));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar tus certificados.'), findsOneWidget);
    await tap(tester, 'Inicio');
    await tester.ensureVisible(
      find.text('No pudimos cargar tus certificados.'),
    );
    expect(find.textContaining('private SQL'), findsNothing);
    certificates.handler = null;
    await tap(tester, 'Reintentar');
    await tester.ensureVisible(find.text('Aún no tienes certificados'));
    expect(find.text('Aún no tienes certificados'), findsOneWidget);
  });

  testWidgets('real fields, derived states and limit notice are presented', (
    tester,
  ) async {
    certificates.wallet = CertificateWallet(
      total: 73,
      certificates: [
        sample(institutionName: 'Institución visible'),
        sample(
          title: 'Revocado sintético',
          status: CertificateStatus.revoked,
          expiresAt: DateTime(2020),
        ),
        sample(title: 'Expirado sintético', expiresAt: DateTime(2020)),
      ],
    );
    await start(tester);
    await tap(tester, 'Certificados');
    expect(find.text('Título real sintético'), findsOneWidget);
    expect(find.text('Institución visible'), findsOneWidget);
    expect(find.text('Válido'), findsOneWidget);
    expect(find.text('Revocado'), findsOneWidget);
    expect(find.text('Expirado'), findsOneWidget);
    expect(find.text('Institución no disponible'), findsNWidgets(2));
    expect(find.text('Emitido: 02/01/2026'), findsNWidgets(3));
    expect(find.text('Se muestran los 50 más recientes.'), findsOneWidget);
  });

  testWidgets(
    'late results from old user cannot replace current profile or wallet',
    (tester) async {
      final oldProfile = Completer<UserProfile?>();
      final oldWallet = Completer<CertificateWallet>();
      final ids = <String>[];
      profiles.handler = (id) async => id == 'synthetic-user'
          ? oldProfile.future
          : const UserProfile(
              id: 'second',
              fullName: 'Segunda persona',
              role: 'holder',
            );
      certificates.handler = (id) async {
        ids.add(id);
        return id == 'synthetic-user'
            ? oldWallet.future
            : CertificateWallet(certificates: [], total: 0);
      };
      await start(tester);
      auth.emit(
        AuthSession(
          userId: 'second',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      await tester.pumpAndSettle();
      oldProfile.complete(profiles.profile);
      oldWallet.complete(
        CertificateWallet(
          certificates: [sample(title: 'Privado anterior')],
          total: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hola, Segunda persona'), findsOneWidget);
      expect(find.textContaining('Ana del perfil'), findsNothing);
      await tap(tester, 'Certificados');
      expect(find.text('Privado anterior'), findsNothing);
      expect(find.text('Aún no tienes certificados'), findsOneWidget);
      expect(ids, ['synthetic-user', 'second']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('logout discards pending results and old wallet navigation', (
    tester,
  ) async {
    final pending = Completer<CertificateWallet>();
    certificates.handler = (_) => pending.future;
    await start(tester);
    await tester.tap(find.text('Certificados'));
    await tester.pump();
    await tester.ensureVisible(find.text('Cerrar sesión'));
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    pending.complete(
      CertificateWallet(
        certificates: [sample(title: 'Privado anterior')],
        total: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Comenzar'), findsOneWidget);
    expect(find.text('Privado anterior'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Comenzar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'same user token refresh preserves wallet tab without rereading',
    (tester) async {
      var reads = 0;
      certificates.handler = (_) async {
        reads++;
        return certificates.wallet;
      };
      await start(tester);
      await tap(tester, 'Certificados');
      auth.emit(testSession());
      await tester.pumpAndSettle();
      expect(find.text('Mis certificados'), findsOneWidget);
      expect(reads, 1);
    },
  );

  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(320, 568),
  ]) {
    testWidgets('home wallet and profile fit $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      certificates.wallet = CertificateWallet(
        certificates: [
          sample(
            title: 'Un título largo para comprobar ajuste de texto en pantallas pequeñas',
          ),
        ],
        total: 1,
      );
      await start(tester);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Certificados');
      expect(tester.takeException(), isNull);
      await tap(tester, 'Perfil');
      expect(tester.takeException(), isNull);
    });
  }
}
