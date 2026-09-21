import 'package:flutter/material.dart';

import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/auth/presentation/login_screen.dart';

abstract final class AppRouter {
  static const String initialRoute = '/';
  static const String loginRoute = '/login';

  static Route<void> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => settings.name == loginRoute
          ? const LoginScreen()
          : const WelcomeScreen(),
    );
  }
}
