import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/domain/auth_repository.dart';
import 'package:mobile/features/auth/presentation/auth_controller.dart';
import 'package:mobile/features/auth/presentation/auth_messages.dart';
import 'package:mobile/features/auth/presentation/widgets/registration_role_selector.dart';

import 'fake_auth_repository.dart';

Future<void> click(WidgetTester tester, String label) async {
  final target = find.text(label).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> openLogin(WidgetTester tester, FakeAuthRepository repo) async {
  await tester.pumpWidget(CertiChainApp(authRepository: repo));
  await click(tester, 'Comenzar');
}

Future<void> credentials(WidgetTester tester, FakeAuthRepository repo) async {
  await openLogin(tester, repo);
  await click(tester, 'Crear cuenta');
  await click(tester, 'Institución');
  await tester.enterText(find.byType(TextFormField).first, '  Ana García  ');
  await tester.enterText(
    find.byType(TextFormField).last,
    '  ana@example.com  ',
  );
  await click(tester, 'Continuar');
}

Future<void> passwords(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'password123');
  await tester.enterText(find.byType(TextFormField).last, 'password123');
}

void main() {
  testWidgets('restored session, events, stream errors and listener disposal', (
    tester,
  ) async {
    final repo = FakeAuthRepository(currentSession: testSession());
    await tester.pumpWidget(CertiChainApp(authRepository: repo));
    expect(find.text('Sesión iniciada'), findsOneWidget);
    repo.emit(null);
    await tester.pumpAndSettle();
    expect(find.text('Comenzar'), findsOneWidget);
    repo.emit(testSession());
    await tester.pumpAndSettle();
    expect(find.text('Sesión iniciada'), findsOneWidget);
    repo.events.addError(AuthFailure.network);
    await tester.pumpAndSettle();
    expect(find.text(authMessage(AuthFailure.network)), findsOneWidget);
    expect(find.text('ana@example.com'), findsNothing);
    repo.emit(testSession());
    await tester.pumpAndSettle();
    expect(find.text('Sesión iniciada'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(repo.events.hasListener, isFalse);
    await repo.events.close();
    expect(tester.takeException(), isNull);
  });

  test(
    'expired restored session initializes until a refreshed session arrives',
    () async {
      final repo = FakeAuthRepository(
        currentSession: AuthSession(userId: 'test', expiresAt: DateTime(2000)),
      );
      final controller = AuthController(repo);
      expect(controller.status, AuthStatus.initializing);
      repo.emit(testSession());
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, AuthStatus.authenticated);
      controller.dispose();
      await repo.events.close();
    },
  );

  testWidgets('back preserves step one including account preference', (
    tester,
  ) async {
    await credentials(tester, FakeAuthRepository());
    expect(find.text('Protege tu cuenta'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver al paso anterior'));
    await tester.pumpAndSettle();
    expect(find.text('  Ana García  '), findsOneWidget);
    expect(find.text('  ana@example.com  '), findsOneWidget);
    expect(
      tester
          .widget<RegistrationRoleSelector>(
            find.byType(RegistrationRoleSelector),
          )
          .value,
      RegistrationAccountType.institution,
    );
  });

  testWidgets('credentials validation, visibility and focus flow', (
    tester,
  ) async {
    await credentials(tester, FakeAuthRepository());
    await click(tester, 'Crear cuenta');
    expect(find.text('Introduce tu contraseña'), findsOneWidget);
    expect(find.text('Confirma tu contraseña'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'short');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(find.byType(TextFormField).last, 'different');
    await click(tester, 'Crear cuenta');
    expect(find.text('Usa al menos 8 caracteres'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.tap(find.byTooltip('Mostrar confirmación'));
    await tester.pump();
    for (final field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(field.obscureText, isFalse);
    }
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.tap(find.byTooltip('Ocultar confirmación'));
    await tester.pump();
    for (final field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(field.obscureText, isTrue);
    }
  });

  testWidgets(
    'signup trims input, blocks duplicates and back, enters session',
    (tester) async {
      final repo = FakeAuthRepository()..request = Completer<void>();
      await credentials(tester, repo);
      await passwords(tester);
      final button = find.byType(AppButton);
      await tester.ensureVisible(button);
      final before = tester.getSize(button);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<AppButton>(button).isLoading, isTrue);
      expect(tester.getSize(button), before);
      // Keyboard submit invokes the same guarded callback during a request.
      tester.widget<EditableText>(find.byType(EditableText).last).onSubmitted!(
        '',
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repo.signupCalls, 1);
      expect(repo.name, 'Ana García');
      expect(repo.email, 'ana@example.com');
      expect(find.text('Protege tu cuenta'), findsOneWidget);
      repo.request!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sesión iniciada'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Sesión iniciada'), findsOneWidget);
    },
  );

  testWidgets(
    'confirmation pending masks email and returns to existing Login',
    (tester) async {
      final repo = FakeAuthRepository()..confirmationRequired = true;
      await credentials(tester, repo);
      await passwords(tester);
      await click(tester, 'Crear cuenta');
      expect(find.text('Revisa tu correo'), findsOneWidget);
      expect(find.text('Correo: a•••@example.com'), findsOneWidget);
      expect(repo.currentSession, isNull);
      expect(find.text('Sesión iniciada'), findsNothing);
      await click(tester, 'Volver a Iniciar sesión');
      expect(find.text('Iniciar sesión'), findsNWidgets(2));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Comenzar'), findsOneWidget);
    },
  );

  testWidgets('signup safe failure preserves credentials', (tester) async {
    final repo = FakeAuthRepository()
      ..failure = AuthFailure.profileProvisioning;
    await credentials(tester, repo);
    await passwords(tester);
    await click(tester, 'Crear cuenta');
    expect(
      find.text(authMessage(AuthFailure.profileProvisioning)),
      findsOneWidget,
    );
    expect(find.text('Protege tu cuenta'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'password123',
    );
  });

  testWidgets(
    'login blocks duplicate requests, navigates and logout resets stack',
    (tester) async {
      final repo = FakeAuthRepository()..request = Completer<void>();
      await openLogin(tester, repo);
      await tester.enterText(
        find.byType(TextFormField).first,
        ' ana@example.com ',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(
        tester.widget<AppButton>(find.byType(AppButton)).isLoading,
        isTrue,
      );
      tester.widget<EditableText>(find.byType(EditableText).last).onSubmitted!(
        '',
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repo.loginCalls, 1);
      expect(repo.email, 'ana@example.com');
      repo.request!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sesión iniciada'), findsOneWidget);
      repo.request = null;
      await click(tester, 'Cerrar sesión');
      expect(repo.logoutCalls, 1);
      expect(find.text('Comenzar'), findsOneWidget);
      expect(find.text('ana@example.com'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Comenzar'), findsOneWidget);
    },
  );

  for (final failure in [AuthFailure.invalidCredentials, AuthFailure.network]) {
    testWidgets('login handles $failure and retains inputs', (tester) async {
      final repo = FakeAuthRepository()..failure = failure;
      await openLogin(tester, repo);
      await tester.enterText(
        find.byType(TextFormField).first,
        'ana@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await click(tester, 'Iniciar sesión');
      expect(find.text(authMessage(failure)), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .controller
            .text,
        'password123',
      );
      expect(find.text('ana@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed logout stays authenticated with safe error', (
    tester,
  ) async {
    final repo = FakeAuthRepository(currentSession: testSession())
      ..failure = AuthFailure.network;
    await tester.pumpWidget(CertiChainApp(authRepository: repo));
    await click(tester, 'Cerrar sesión');
    expect(repo.logoutCalls, 1);
    expect(find.text('Sesión iniciada'), findsOneWidget);
    expect(find.text(authMessage(AuthFailure.network)), findsOneWidget);
  });

  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(320, 568),
  ]) {
    testWidgets('credentials fit keyboard and enlarged text at $size', (
      tester,
    ) async {
      await credentials(tester, FakeAuthRepository());
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      await click(tester, 'Crear cuenta');
      await tester.ensureVisible(find.byType(AppButton));
      expect(find.text('Crear cuenta').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
