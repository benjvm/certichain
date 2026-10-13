import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import 'router/app_router.dart';
import 'router/public_router.dart';
import 'theme/app_theme.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/certificates/domain/certificate_repository.dart';
import 'authenticated_area.dart';
import '../features/institutions/domain/institution_repository.dart';
import '../features/issuance/domain/issuance_repository.dart';
import '../features/certificates/domain/certificate_document_repository.dart';
import '../features/verification/domain/verification_repository.dart';
import '../features/verification/domain/verification_link.dart';
import '../features/verification/domain/hash_comparison.dart';
import '../features/verification/presentation/qr_scanner_panel.dart';
import '../features/verification/domain/blockchain_verification.dart';
import '../features/issuance/domain/anchoring_repository.dart';

class CertiChainApp extends StatefulWidget {
  const CertiChainApp({
    this.authRepository,
    this.profileRepository,
    this.certificateRepository,
    this.institutionRepository,
    this.issuanceRepository,
    this.pdfPicker,
    this.pendingStore,
    this.documents,
    this.verification,
    this.holderVerification,
    this.credentials,
    this.verificationLink,
    this.comparison,
    this.comparisonPicker,
    this.pdfHasher,
    this.scannerFactory,
    this.startupMessage,
    this.anchoring,
    this.anchorStore,
    this.openings,
    this.openingTransfer,
    this.openingInput,
    super.key,
  });
  final AuthRepository? authRepository;
  final AnchoringRepository? anchoring;
  final AnchorReceiptStore? anchorStore;
  final OpeningRepository? openings;
  final OpeningTransfer? openingTransfer;
  final OpeningInput? openingInput;
  final ProfileRepository? profileRepository;
  final CertificateRepository? certificateRepository;
  final InstitutionRepository? institutionRepository;
  final IssuanceRepository? issuanceRepository;
  final PdfPicker? pdfPicker;
  final PendingAttemptStore? pendingStore;
  final CertificateDocumentRepository? documents;
  final VerificationRepository? verification;
  final VerificationRepository? holderVerification;
  final CredentialRepository? credentials;
  final VerificationLink? verificationLink;
  final HashComparisonRepository? comparison;
  final ComparisonPdfPicker? comparisonPicker;
  final PdfHasher? pdfHasher;
  final ScannerSession Function()? scannerFactory;
  final String? startupMessage;
  @override
  State<CertiChainApp> createState() => _CertiChainAppState();
}

class _CertiChainAppState extends State<CertiChainApp> {
  AuthController? _auth;
  late final PublicRouter _router;
  GlobalKey<NavigatorState> _privateKey = GlobalKey<NavigatorState>();
  Object? _privateIdentity;
  @override
  void initState() {
    super.initState();
    if (widget.authRepository != null) {
      _auth = AuthController(widget.authRepository!);
    }
    _router = PublicRouter(
      root: _root,
      repository: () => widget.verification,
      comparison: () => widget.comparison,
      picker: () => widget.comparisonPicker,
      hasher: () => widget.pdfHasher,
      link: () => widget.verificationLink,
      scanner: () => widget.scannerFactory,
      openingInput: () => widget.openingInput,
    );
  }

  @override
  void didUpdateWidget(CertiChainApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authRepository != widget.authRepository) {
      _auth?.dispose();
      _auth = widget.authRepository == null
          ? null
          : AuthController(widget.authRepository!);
    }
  }

  @override
  void dispose() {
    _auth?.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: AppConstants.appName,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    routerDelegate: _router,
    routeInformationParser: const PublicRouteParser(),
  );

  Widget _root(BuildContext context) {
    final auth = _auth;
    if (auth == null) {
      return _unavailable(
        widget.startupMessage ?? 'Preparando acceso privado…',
      );
    }
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final identity = (auth.status, auth.session?.userId);
        if (_privateIdentity != identity) {
          _privateIdentity = identity;
          _privateKey = GlobalKey<NavigatorState>();
        }
        _router.privateNavigator = _privateKey;
        return Navigator(
          key: _privateKey,
          onGenerateRoute: (settings) {
            if (auth.status == AuthStatus.unauthenticated) {
              return AppRouter.onGenerateRoute(
                settings,
                widget.authRepository!,
                onVerify: widget.verification == null
                    ? null
                    : _router.showVerification,
              );
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => switch (auth.status) {
                AuthStatus.authenticated => AuthenticatedArea(
                  controller: auth,
                  userId: auth.session!.userId,
                  profiles: widget.profileRepository!,
                  certificates: widget.certificateRepository!,
                  institutions: widget.institutionRepository,
                  issuance: widget.issuanceRepository,
                  picker: widget.pdfPicker,
                  pendingStore: widget.pendingStore,
                  documents: widget.documents,
                  anchoring: widget.anchoring,
                  anchorStore: widget.anchorStore,
                  openings: widget.openings,
                  openingTransfer: widget.openingTransfer,
                  verification:
                      widget.holderVerification ?? widget.verification,
                  publicCooldown: _router.cooldown,
                  credentials: widget.credentials,
                  verificationLink: widget.verificationLink,
                  onVerify: _router.showVerification,
                ),
                AuthStatus.initializing => _unavailable('Restaurando sesión'),
                _ => _unavailable(
                  auth.message ?? 'No se pudo restaurar la sesión.',
                  retry: auth.inspectSession,
                ),
              },
            );
          },
        );
      },
    );
  }

  Widget _unavailable(String message, {VoidCallback? retry}) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            if (retry != null)
              TextButton(onPressed: retry, child: const Text('Reintentar')),
            TextButton(
              onPressed: _router.showVerification,
              child: const Text('Verificar certificado'),
            ),
          ],
        ),
      ),
    ),
  );
}
