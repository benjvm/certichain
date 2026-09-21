import 'package:flutter/material.dart';

import '../../features/onboarding/presentation/welcome_screen.dart';

abstract final class AppRouter {
  static const String initialRoute = '/';

  static Route<void> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const WelcomeScreen(),
    );
  }
}
