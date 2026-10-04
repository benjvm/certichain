import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/certificates/domain/certificate_repository.dart';
import 'authenticated_area.dart';
import '../features/institutions/domain/institution_repository.dart';
import '../features/issuance/domain/issuance_repository.dart';
import '../features/certificates/domain/certificate_document_repository.dart';

class CertiChainApp extends StatefulWidget {
  const CertiChainApp({
    required this.authRepository,
    required this.profileRepository,
    required this.certificateRepository,
    this.institutionRepository,
    this.issuanceRepository,
    this.pdfPicker,
    this.pendingStore,
    this.documents,
    super.key,
  });
  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final CertificateRepository certificateRepository;
  final InstitutionRepository? institutionRepository;
  final IssuanceRepository? issuanceRepository;
  final PdfPicker? pdfPicker;
  final PendingAttemptStore? pendingStore;
  final CertificateDocumentRepository? documents;

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
          AuthStatus.authenticated => AuthenticatedArea(
            controller: _auth,
            userId: _auth.session!.userId,
            profiles: widget.profileRepository,
            certificates: widget.certificateRepository,
            institutions: widget.institutionRepository,
            issuance: widget.issuanceRepository,
            picker: widget.pdfPicker,
            pendingStore: widget.pendingStore,
            documents: widget.documents,
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
