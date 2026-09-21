import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/theme/app_theme.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/presentation/login_screen.dart';

void main() {
  Future<void> openLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );
  }

  testWidgets('local validation and disabled future actions', (tester) async {
    await openLogin(tester);
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(find.text('Introduce tu email'), findsOneWidget);
    expect(find.text('Introduce tu contraseña'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'invalid');
    await tester.pump();
    expect(find.text('Introduce un email válido'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      ' student@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).last, 'x');
    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();
    expect(find.text('Introduce un email válido'), findsNothing);
    expect(find.text('Introduce tu contraseña'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      tester
          .widgetList<TextButton>(find.byType(TextButton))
          .every((button) => button.onPressed == null),
      isTrue,
    );
  });
  testWidgets('visibility, keyboard next/done and outside dismissal', (
    tester,
  ) async {
    await openLogin(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'student@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(fields.last, 'secret');
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .focusNode
          .hasFocus,
      isFalse,
    );
    await tester.tap(fields.first);
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
  });
  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(320, 568),
  ]) {
    testWidgets('keyboard and enlarged text at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openLogin(tester);
      await tester.ensureVisible(find.byType(AppButton));
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      await tester.ensureVisible(find.text('Crear cuenta'));
      expect(tester.takeException(), isNull);
      expect(find.text('Crear cuenta').hitTestable(), findsOneWidget);
    });
  }
}
