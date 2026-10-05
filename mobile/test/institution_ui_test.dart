import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/app/theme/app_theme.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/domain/auth_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_repository.dart';
import 'package:mobile/features/certificates/domain/certificate_document_repository.dart';
import 'package:mobile/features/certificates/presentation/certificate_detail_screen.dart';
import 'package:mobile/features/institutions/domain/institution_repository.dart';
import 'package:mobile/features/institutions/presentation/institution_workspace.dart';
import 'package:mobile/features/issuance/domain/issuance_repository.dart';
import 'package:mobile/features/issuance/presentation/issuance_screen.dart';

import 'fake_auth_repository.dart';
import 'fake_wallet_repositories.dart';
import 'issuance_fakes.dart';
import 'certificate_detail_test.dart' show capture;

void main() {
  late FakeInstitutions institutions;
  late FakeIssuance issuance;
  late FakePdfPicker picker;
  late MemoryAttempts store;
  late DateTime clock;
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
    clock = DateTime.now();
    institutions = FakeInstitutions();
    issuance = FakeIssuance();
    picker = FakePdfPicker();
    store = MemoryAttempts();
  });
  Future<void> tap(WidgetTester tester, String text) async {
    await tester.pumpAndSettle();
    final buttons = find.byWidgetPredicate(
      (w) => w is AppButton && w.label == text,
    );
    final finder = buttons.evaluate().isNotEmpty ? buttons : find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> screen(WidgetTester tester, {VoidCallback? expired}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: IssuanceScreen(
          userId: actorId,
          institution: membership(),
          institutions: institutions,
          repository: issuance,
          picker: picker,
          store: store,
          clock: () => clock,
          onSessionExpired: expired ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'leaving issuance cancels its pending selector and ignores late bytes',
    (t) async {
      picker.pending = Completer<SelectedPdf?>();
      await screen(t);
      await t.enterText(find.byKey(const Key('holder-id')), holderId);
      await t.enterText(find.byKey(const Key('issuance-title')), 'Synthetic');
      await tap(t, 'Siguiente');
      await t.ensureVisible(find.text('Seleccionar PDF'));
      await t.tap(find.text('Seleccionar PDF'));
      await t.pump();
      await t.pumpWidget(const SizedBox());
      expect(picker.cancellations, 1);
      picker.pending!.complete(selectedPdf());
      await t.pumpAndSettle();
      expect(issuance.requests, isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  Future<void> toConfirmation(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('holder-id')), holderId);
    await tester.enterText(
      find.byKey(const Key('issuance-title')),
      'Título de pruebas',
    );
    await tap(tester, 'Siguiente');
    await tap(tester, 'Seleccionar PDF');
    await tap(tester, 'Siguiente');
  }

  testWidgets(
    'holder has no institutional entry until real membership; profile copies own id',
    (tester) async {
      final auth = FakeAuthRepository(
        currentSession: AuthSession(
          userId: actorId,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      addTearDown(auth.events.close);
      institutions.members = [];
      await tester.pumpWidget(
        CertiChainApp(
          authRepository: auth,
          profileRepository: FakeProfileRepository(),
          certificateRepository: FakeCertificateRepository(),
          institutionRepository: institutions,
          issuanceRepository: issuance,
          pdfPicker: picker,
          pendingStore: store,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Espacio institucional'), findsNothing);
      await tap(tester, 'Perfil');
      expect(find.text('Copiar mi ID de titular'), findsOneWidget);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<dynamic, dynamic>)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tap(tester, 'Copiar mi ID de titular');
      expect(copied, 'synthetic-user');
      institutions.members = [membership()];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Espacio institucional'), findsOneWidget);
      await tap(tester, 'Espacio institucional');
      expect(find.byType(InstitutionWorkspace), findsOneWidget);
      expect(find.text('issuer · Verificada'), findsOneWidget);
      auth.emit(
        AuthSession(
          userId: actorId,
          expiresAt: DateTime.now().add(const Duration(hours: 2)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InstitutionWorkspace), findsOneWidget);
      auth.emit(
        AuthSession(
          userId: holderId,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InstitutionWorkspace), findsNothing);
    },
  );
  testWidgets(
    'three steps enforce fields/PDF, preview summary and confirmed success',
    (tester) async {
      await screen(tester);
      expect(find.text('Emitir certificado'), findsOneWidget);
      await tap(tester, 'Siguiente');
      expect(
        find.text('Introduce un ID de titular UUID válido.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('holder-id')), holderId);
      await tester.enterText(
        find.byKey(const Key('issuance-title')),
        'Título de pruebas',
      );
      await tap(tester, 'Siguiente');
      await tap(tester, 'Siguiente');
      expect(
        find.text('Selecciona un PDF antes de confirmar.'),
        findsOneWidget,
      );
      expect(issuance.requests, isEmpty);
      await tap(tester, 'Seleccionar PDF');
      expect(find.textContaining('certificado.pdf'), findsOneWidget);
      await tap(tester, 'Siguiente');
      expect(find.text('Revisa antes de emitir'), findsOneWidget);
      await tap(tester, 'Emitir certificado');
      expect(find.text('Certificado emitido'), findsOneWidget);
      expect(find.text(certificateId), findsOneWidget);
      expect(find.byType(CertificateDetailScreen), findsNothing);
      expect(issuance.requests.single.data.holderId, holderId);
    },
  );
  testWidgets('double tap submits once and honest waiting state', (
    tester,
  ) async {
    issuance.pending = Completer<String>();
    await screen(tester);
    await toConfirmation(tester);
    final sendFinder = find.byWidgetPredicate(
      (w) => w is AppButton && w.label == 'Emitir certificado',
    );
    await tester.ensureVisible(sendFinder);
    await tester.tap(sendFinder);
    await tester.pump();
    final buttons = find.byType(AppButton);
    final send = tester
        .widgetList<AppButton>(buttons)
        .where((b) => b.label == 'Emitir certificado')
        .single;
    send.onPressed?.call();
    await tester.pump();
    expect(issuance.requests.length, 1);
    expect(find.textContaining('Esperando la confirmación'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    issuance.pending!.complete(certificateId);
    await tester.pumpAndSettle();
    expect(find.text('Certificado emitido'), findsOneWidget);
  });
  testWidgets('holder UUID paste uses clipboard without a profile query', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': holderId} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await screen(tester);
    await tap(tester, 'Pegar ID del titular');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('holder-id')))
          .controller!
          .text,
      holderId,
    );
    await tester.enterText(
      find.byKey(const Key('issuance-title')),
      'Destino pegado',
    );
    await tap(tester, 'Siguiente');
    expect(find.text('Seleccionar PDF'), findsOneWidget);
  });
  testWidgets('operation in progress explains 120 seconds and preserves key', (
    tester,
  ) async {
    issuance.error = const IssuanceException('operation_in_progress');
    await screen(tester);
    await toConfirmation(tester);
    await tap(tester, 'Emitir certificado');
    expect(find.textContaining('Espera 120 segundos'), findsOneWidget);
    final button = tester
        .widgetList<AppButton>(find.byType(AppButton))
        .where((b) => b.label == 'Reintentar')
        .single;
    expect(button.onPressed, null);
    final key = issuance.requests.single.key;
    issuance.error = null;
    clock = clock.add(const Duration(seconds: 121));
    await tester.pump(const Duration(seconds: 121));
    await tester.pumpAndSettle();
    await tap(tester, 'Reintentar');
    expect(issuance.requests.length, 2);
    expect(issuance.requests.last.key, key);
  });
  for (final state in [
    InstitutionStatus.pending,
    InstitutionStatus.rejected,
    InstitutionStatus.suspended,
  ]) {
    testWidgets('blocked $state has no form', (tester) async {
      institutions.members = [membership(status: state)];
      await screen(tester);
      expect(find.byKey(const Key('holder-id')), findsNothing);
      expect(find.text(membership(status: state).blockReason), findsOneWidget);
    });
  }
  testWidgets('membership loss and suspension while open hide the form', (
    tester,
  ) async {
    await screen(tester);
    institutions.members = [];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('holder-id')), findsNothing);
    expect(find.textContaining('Ya no perteneces'), findsOneWidget);
    institutions.members = [membership(status: InstitutionStatus.suspended)];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.textContaining('está suspendida'), findsOneWidget);
  });
  testWidgets('401 uses existing session exit callback', (tester) async {
    var expired = false;
    issuance.error = const IssuanceException('unauthenticated');
    await screen(tester, expired: () => expired = true);
    await toConfirmation(tester);
    await tap(tester, 'Emitir certificado');
    expect(expired, true);
  });
  testWidgets(
    'multiple institutions never mix issued rows, details or active selection',
    (tester) async {
      institutions.members = [
        membership(name: 'Primera'),
        membership(
          id: certificateId,
          name: 'Segunda',
          role: InstitutionalRole.admin,
        ),
      ];
      institutions.wallets[institutionId] = CertificateWallet(
        certificates: [
          Certificate(
            id: certificateId,
            holderId: holderId,
            institutionId: institutionId,
            title: 'Certificado de Primera',
            issuedAt: DateTime(2026),
            status: CertificateStatus.active,
          ),
        ],
        total: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: InstitutionWorkspace(
            userId: actorId,
            repository: institutions,
            issuance: issuance,
            picker: picker,
            store: store,
            onSessionExpired: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Certificado de Primera'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Segunda').last);
      await tester.pumpAndSettle();
      expect(find.text('Certificado de Primera'), findsNothing);
      expect(institutions.reads.last, certificateId);
      expect(find.byType(CertificateDetailScreen), findsNothing);
      await tap(tester, 'Emitir certificado');
      expect(find.text('Segunda'), findsOneWidget);
    },
  );
  testWidgets(
    'holder document action handles real availability, absence, repeated fresh access',
    (tester) async {
      final certificates = FakeCertificateRepository()
        ..wallet = CertificateWallet(
          certificates: [
            Certificate(
              id: certificateId,
              holderId: actorId,
              institutionId: institutionId,
              title: 'Documento propio',
              issuedAt: DateTime(2026),
              status: CertificateStatus.active,
            ),
          ],
          total: 1,
        );
      final documents = FakeDocuments();
      var expired = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CertificateDetailScreen(
            userId: actorId,
            certificateId: certificateId,
            repository: certificates,
            documents: documents,
            onSessionExpired: () => expired = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Descargar PDF'), findsOneWidget);
      expect(find.text('El PDF todavía no está disponible.'), findsNothing);
      await tap(tester, 'Descargar PDF');
      await tap(tester, 'Descargar PDF');
      expect(documents.downloads, 2);
      documents.available = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('no tiene un PDF disponible'), findsOneWidget);
      documents.error = const DocumentException('unauthenticated');
      await tap(tester, 'Comprobar PDF de nuevo');
      expect(expired, true);
    },
  );
  for (final size in [
    const Size(390, 844),
    const Size(360, 800),
    const Size(320, 568),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('issuance responsive ${size.width} x $scale all steps', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => RepaintBoundary(
              key: const Key('capture'),
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: IssuanceScreen(
              userId: actorId,
              institution: membership(
                name: 'Institución de formación con un nombre extenso',
              ),
              institutions: institutions,
              repository: issuance,
              picker: picker,
              store: store,
              onSessionExpired: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        await capture(tester, 'issuance-data-${size.width}-$scale');
        await toConfirmation(tester);
        expect(tester.takeException(), null);
        await capture(tester, 'issuance-confirm-${size.width}-$scale');
        await tap(tester, 'Emitir certificado');
        expect(tester.takeException(), null);
      });
      testWidgets('issued list and PDF responsive ${size.width} x $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        institutions.members = [
          membership(name: 'Institución con un nombre suficientemente extenso'),
        ];
        institutions.wallets[institutionId] = CertificateWallet(
          certificates: [
            Certificate(
              id: certificateId,
              holderId: holderId,
              institutionId: institutionId,
              title: 'Certificado de formación y especialización profesional con nombre extenso',
              issuedAt: DateTime(2026),
              status: CertificateStatus.active,
            ),
          ],
          total: 1,
        );
        final documents = FakeDocuments();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => RepaintBoundary(
              key: const Key('capture'),
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: InstitutionWorkspace(
              userId: actorId,
              repository: institutions,
              issuance: issuance,
              picker: picker,
              store: store,
              documents: documents,
              onSessionExpired: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        await capture(tester, 'issued-list-${size.width}-$scale');
        await tap(tester, 'Consultar PDF');
        await tap(tester, 'Descargar PDF');
        expect(documents.downloads, 1);
        expect(tester.takeException(), null);
      });
    }
  }
}
