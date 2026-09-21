import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/temporary_authenticated_screen.dart';

class CertiChainApp extends StatefulWidget {
  const CertiChainApp({required this.authRepository, super.key});
  final AuthRepository authRepository;

  @override
  State<CertiChainApp> createState() => _CertiChainAppState();
}

class _CertiChainAppState extends State<CertiChainApp> {
  late AuthController _auth;

  @override
  void initState() {
    super.initState();
    _auth = AuthController(widget.authRepository);
  }

  @override
  void didUpdateWidget(CertiChainApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authRepository != widget.authRepository) {
      _auth.dispose();
      _auth = AuthController(widget.authRepository);
    }
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) => MaterialApp(
        // Replacing the navigator discards every route and form from the old session.
        key: ValueKey((_auth.status, _auth.session?.userId)),
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: AppRouter.initialRoute,
        onGenerateRoute: _auth.status == AuthStatus.unauthenticated
            ? (settings) =>
                  AppRouter.onGenerateRoute(settings, widget.authRepository)
            : null,
        home: switch (_auth.status) {
          AuthStatus.unauthenticated => null,
          AuthStatus.authenticated => TemporaryAuthenticatedScreen(
            controller: _auth,
          ),
          AuthStatus.initializing => const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Restaurando sesión',
              ),
            ),
          ),
          AuthStatus.error => Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_auth.message ?? 'No se pudo restaurar la sesión.'),
                    TextButton(
                      onPressed: _auth.inspectSession,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        },
      ),
    );
  }
}
