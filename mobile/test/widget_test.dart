import 'fake_wallet_repositories.dart';
import 'fake_auth_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/features/auth/presentation/login_screen.dart';
import 'package:mobile/features/onboarding/presentation/welcome_screen.dart';

void main() {
  testWidgets('welcome screen shows the first onboarding page', (tester) async {
    await tester.pumpWidget(
      CertiChainApp(
        profileRepository: FakeProfileRepository(),
        certificateRepository: FakeCertificateRepository(),
        authRepository: FakeAuthRepository(),
      ),
    );
    expect(find.text('CertiChain'), findsOneWidget);
    expect(
      find.text('Certificados digitales,\nverificables y seguros'),
      findsOneWidget,
    );
    expect(find.text('Comenzar'), findsOneWidget);
    expect(find.bySemanticsLabel('Página 1 de 3'), findsOneWidget);
    await tester.tap(find.text('Comenzar'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('welcome screen fits a small portrait with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: WelcomeScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Comenzar'), findsOneWidget);
  });
}
