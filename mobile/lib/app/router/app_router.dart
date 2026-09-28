import 'package:flutter/material.dart';

import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/certificates/domain/certificate_repository.dart';
import '../../features/certificates/presentation/certificate_detail_screen.dart';

enum AuthenticatedSection { home, wallet, profile }

abstract final class AppRouter {
  static const String initialRoute = '/';
  static const String loginRoute = '/login';
  static const String registerRoute = '/register';
  static const String certificateDetailRoute = '/certificates/detail';

  static Route<void> certificateDetail({
    required String userId,
    required String certificateId,
    required CertificateRepository repository,
  }) => MaterialPageRoute<void>(
    settings: RouteSettings(
      name: certificateDetailRoute,
      arguments: certificateId,
    ),
    builder: (_) => CertificateDetailScreen(
      userId: userId,
      certificateId: certificateId,
      repository: repository,
    ),
  );

  static Route<void> onGenerateRoute(
    RouteSettings settings,
    AuthRepository repository,
  ) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => switch (settings.name) {
        loginRoute => LoginScreen(repository: repository),
        registerRoute => RegisterScreen(repository: repository),
        _ => const WelcomeScreen(),
      },
    );
  }
}
