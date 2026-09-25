import 'fake_wallet_repositories.dart';
import 'fake_auth_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/app/theme/app_theme.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/presentation/login_screen.dart';
import 'package:mobile/features/auth/presentation/register_screen.dart';
import 'package:mobile/features/auth/presentation/registration_credentials.dart';
import 'package:mobile/features/auth/presentation/widgets/registration_role_selector.dart';
import 'package:mobile/features/onboarding/presentation/welcome_screen.dart';

void main() {
  Future<void> open(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: RegisterScreen(repository: FakeAuthRepository()),
    ),
  );

  testWidgets('welcome login register and back preserve the existing stack', (
    tester,
  ) async {
    await tester.pumpWidget(
      CertiChainApp(
        profileRepository: FakeProfileRepository(),
        certificateRepository: FakeCertificateRepository(),
        authRepository: FakeAuthRepository(),
      ),
    );
    await tester.tap(find.text('Comenzar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'student@example.com',
    );
    await tester.ensureVisible(find.text('Crear cuenta'));
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('student@example.com'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets(
    'specified fields validate locally and submission stays on registration',
    (tester) async {
      await open(tester);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Verificador'), findsNothing);
      expect(find.text('Administrador'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '   ');
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(find.text('Introduce tu nombre completo'), findsOneWidget);
      expect(find.text('Introduce tu email'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, 'bad@');
      await tester.pump();
      expect(find.text('Introduce un email válido'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Ana García');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        ' ana@example.com ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Introduce tu nombre completo'), findsNothing);
      expect(find.text('Introduce un email válido'), findsNothing);
      expect(find.byType(RegistrationCredentials), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .focusNode
            .hasFocus,
        isFalse,
      );
      await tester.tap(find.byType(TextFormField).first);
      await tester.pump();
      await tester.tap(find.text('CertiChain'));
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isFalse,
      );
    },
  );

  testWidgets('account preference changes mutually exclusive semantic state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await open(tester);
    expect(
      tester
          .widget<RegistrationRoleSelector>(
            find.byType(RegistrationRoleSelector),
          )
          .value,
      RegistrationAccountType.student,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Estudiante')),
      matchesSemantics(
        label: 'Estudiante',
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.text('Institución'));
    await tester.pump();
    expect(
      tester
          .widget<RegistrationRoleSelector>(
            find.byType(RegistrationRoleSelector),
          )
          .value,
      RegistrationAccountType.institution,
    );
    expect(
      find.text('La institución requiere aprobación para emitir certificados.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Estudiante'));
    await tester.pump();
    expect(
      tester
          .widget<RegistrationRoleSelector>(
            find.byType(RegistrationRoleSelector),
          )
          .value,
      RegistrationAccountType.student,
    );
    semantics.dispose();
  });

  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(320, 568),
  ]) {
    testWidgets('registration fits $size with large text and keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);
      await tester.ensureVisible(find.text('Institución'));
      await tester.tap(find.text('Institución'));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.ensureVisible(find.byType(AppButton));
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      await tester.ensureVisible(find.byType(AppButton));
      expect(find.text('Continuar').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
