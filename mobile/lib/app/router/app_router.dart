import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

abstract final class AppRouter {
  static const String initialRoute = '/';

  static Route<void> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const _AppShell(),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text(AppConstants.appName)));
  }
}
