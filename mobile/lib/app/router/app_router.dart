import 'package:flutter/material.dart';

import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/certificates/domain/certificate_repository.dart';
import '../../features/certificates/presentation/certificate_detail_screen.dart';
import '../../features/certificates/domain/certificate_document_repository.dart';
import '../../features/verification/domain/verification_repository.dart';
import '../../features/verification/domain/verification_link.dart';
import '../../features/issuance/domain/anchoring_repository.dart';
import '../../features/verification/presentation/public_query_cooldown.dart';

enum AuthenticatedSection { home, wallet, profile }

abstract final class AppRouter {
  static const String initialRoute = '/';
  static const String loginRoute = '/login';
  static const String registerRoute = '/register';
  static const String certificateDetailRoute = '/certificates/detail';
  static const String institutionalWorkspaceRoute = '/institutions';
  static const String issuanceRoute = '/institutions/issue';

  static Route<void> certificateDetail({
    required String userId,
    required String certificateId,
    required CertificateRepository repository,
    CertificateDocumentRepository? documents,
    VoidCallback? onSessionExpired,
    CredentialRepository? credentials,
    VerificationLink? verificationLink,
    Listenable? sessionChanges,
    OpeningRepository? openings,
    OpeningTransfer? openingTransfer,
    VerificationRepository? verification,
    PublicQueryCooldown? publicCooldown,
  }) => MaterialPageRoute<void>(
    settings: RouteSettings(
      name: certificateDetailRoute,
      arguments: certificateId,
    ),
    builder: (_) => CertificateDetailScreen(
      userId: userId,
      certificateId: certificateId,
      repository: repository,
      documents: documents,
      onSessionExpired: onSessionExpired,
      credentials: credentials,
      verificationLink: verificationLink,
      sessionChanges: sessionChanges,
      openings: openings,
      openingTransfer: openingTransfer,
      verification: verification,
      publicCooldown: publicCooldown,
    ),
  );

  static Route<void> onGenerateRoute(
    RouteSettings settings,
    AuthRepository repository, {
    VoidCallback? onVerify,
  }) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => switch (settings.name) {
        loginRoute => LoginScreen(repository: repository),
        registerRoute => RegisterScreen(repository: repository),
        _ => WelcomeScreen(onVerify: onVerify),
      },
    );
  }
}
