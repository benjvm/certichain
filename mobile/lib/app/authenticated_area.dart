import '../features/revocation/domain/revocation_repository.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_controller.dart';
import '../features/certificates/domain/certificate_repository.dart';
import '../features/certificates/presentation/wallet_content.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/profile/presentation/profile_content.dart';
import '../core/widgets/app_button.dart';
import '../core/widgets/app_top_bar.dart';
import '../core/widgets/app_bottom_navigation.dart';
import 'router/app_router.dart';
import 'theme/app_spacing.dart';
import 'theme/app_radius.dart';
import 'theme/app_colors.dart';
import 'theme/app_icons.dart';
import 'theme/app_sizes.dart';
import 'theme/app_typography.dart';
import '../features/institutions/domain/institution_repository.dart';
import '../features/institutions/presentation/institution_workspace.dart';
import '../features/issuance/domain/issuance_repository.dart';
import '../features/certificates/domain/certificate_document_repository.dart';
import '../features/verification/domain/verification_repository.dart';
import '../features/verification/domain/verification_link.dart';
import '../features/issuance/domain/anchoring_repository.dart';
import '../features/verification/presentation/public_query_cooldown.dart';

/// Owned by the session-keyed navigator. Never retained across identities.
class AuthenticatedArea extends StatefulWidget {
  const AuthenticatedArea({
    required this.controller,
    required this.userId,
    required this.profiles,
    required this.certificates,
    this.institutions,
    this.issuance,
    this.picker,
    this.pendingStore,
    this.documents,
    this.credentials,
    this.verificationLink,
    this.onVerify,
    this.anchoring,
    this.revocations,
    this.revocationKeys,
    this.anchorStore,
    this.openings,
    this.openingTransfer,
    this.verification,
    this.publicCooldown,
    super.key,
  });
  final AuthController controller;
  final RevocationRepository? revocations;
  final RevocationKeyStore? revocationKeys;
  final AnchoringRepository? anchoring;
  final AnchorReceiptStore? anchorStore;
  final OpeningRepository? openings;
  final OpeningTransfer? openingTransfer;
  final VerificationRepository? verification;
  final PublicQueryCooldown? publicCooldown;
  final String userId;
  final ProfileRepository profiles;
  final CertificateRepository certificates;
  final InstitutionRepository? institutions;
  final IssuanceRepository? issuance;
  final PdfPicker? picker;
  final PendingAttemptStore? pendingStore;
  final CertificateDocumentRepository? documents;
  final CredentialRepository? credentials;
  final VerificationLink? verificationLink;
  final VoidCallback? onVerify;

  @override
  State<AuthenticatedArea> createState() => _AuthenticatedAreaState();
}

class _AuthenticatedAreaState extends State<AuthenticatedArea>
    with WidgetsBindingObserver {
  late Future<UserProfile?> _profile;
  late Future<CertificateWallet> _wallet;
  AuthenticatedSection _section = AuthenticatedSection.home;
  Timer? _expiry;
  int _request = 0;
  bool _openingDetail = false;
  Future<List<InstitutionMembership>>? _members;
  Timer? _membershipTimer;
  void _readMemberships() {
    _members = widget.institutions?.readMemberships(widget.userId);
    if (_members != null) {
      unawaited(
        _members!.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readProfile();
    _readWallet();
    _readMemberships();
    widget.controller.addListener(_sessionChanged);
    _membershipTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(_readMemberships);
    });
  }

  void _readProfile() {
    _profile = widget.profiles.readProfile(widget.userId);
    // Attach an error handler even while the profile tab is not visible.
    unawaited(
      _profile.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  void _readWallet() {
    _expiry?.cancel();
    final request = ++_request;
    _wallet = widget.certificates.readWallet(widget.userId);
    unawaited(
      _wallet.then<void>((wallet) {
        if (!mounted || request != _request) return;
        _scheduleExpiry(wallet);
      }, onError: (Object _, StackTrace _) {}),
    );
  }

  void _scheduleExpiry(CertificateWallet wallet) {
    final now = DateTime.now();
    final expirations =
        wallet.certificates
            .where(
              (c) =>
                  c.status == CertificateStatus.active &&
                  c.expiresAt != null &&
                  c.expiresAt!.isAfter(now),
            )
            .map((c) => c.expiresAt!)
            .toList()
          ..sort();
    if (expirations.isEmpty) return;
    _expiry = Timer(expirations.first.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleExpiry(wallet);
    });
  }

  @override
  void didUpdateWidget(AuthenticatedArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.profiles != widget.profiles ||
        oldWidget.certificates != widget.certificates) {
      _section = AuthenticatedSection.home;
      _readProfile();
      _readWallet();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() => setState(() {
    _readProfile();
    _readWallet();
    _readMemberships();
  });
  void _sessionChanged() {
    if (mounted) setState(_readMemberships);
  }

  Future<void> _openInstitution() async {
    if (_openingDetail ||
        widget.institutions == null ||
        widget.issuance == null ||
        widget.picker == null ||
        widget.pendingStore == null) {
      return;
    }
    _openingDetail = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(
          name: AppRouter.institutionalWorkspaceRoute,
        ),
        builder: (_) => InstitutionWorkspace(
          userId: widget.userId,
          repository: widget.institutions!,
          issuance: widget.issuance!,
          picker: widget.picker!,
          store: widget.pendingStore!,
          documents: widget.documents,
          anchoring: widget.anchoring,
          revocations: widget.revocations,
          revocationKeys: widget.revocationKeys,
          anchorStore: widget.anchorStore,
          openings: widget.openings,
          openingTransfer: widget.openingTransfer,
          onSessionExpired: widget.controller.requireSignIn,
          sessionChanges: widget.controller,
        ),
      ),
    );
    _openingDetail = false;
    if (mounted) _refresh();
  }

  void _open(AuthenticatedSection section) =>
      setState(() => _section = section);

  Future<void> _openCertificate(String id) async {
    if (_openingDetail) return;
    _openingDetail = true;
    await Navigator.of(context).push<void>(
      AppRouter.certificateDetail(
        userId: widget.userId,
        certificateId: id,
        repository: widget.certificates,
        credentials: widget.credentials,
        verificationLink: widget.verificationLink,
        sessionChanges: widget.controller,
        documents: widget.documents,
        openings: widget.openings,
        openingTransfer: widget.openingTransfer,
        verification: widget.verification,
        publicCooldown: widget.publicCooldown,
        onSessionExpired: widget.controller.requireSignIn,
      ),
    );
    _openingDetail = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    _membershipTimer?.cancel();
    widget.controller.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = _section == AuthenticatedSection.home;
    return PopScope(
      canPop: home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _open(AuthenticatedSection.home);
      },
      child: Scaffold(
        appBar: AppTopBar(
          onBack: home ? null : () => _open(AuthenticatedSection.home),
          textScale: MediaQuery.textScalerOf(context).scale(1),
          title: switch (_section) {
            AuthenticatedSection.home => null,
            AuthenticatedSection.wallet => 'Mis certificados',
            AuthenticatedSection.profile => 'Mi perfil',
          },
          onRefresh: _refresh,
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.contentWidth,
              ),
              child: SingleChildScrollView(
                key: ValueKey(_section),
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  _section == AuthenticatedSection.profile
                      ? AppSpacing.xlarge
                      : AppSpacing.xxl,
                  AppSpacing.screenHorizontal,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_section != AuthenticatedSection.wallet) ...[
                      ProfileContent(
                        future: _profile,
                        greeting: home,
                        onRetry: () => setState(_readProfile),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                    if (_members != null)
                      FutureBuilder<List<InstitutionMembership>>(
                        future: _members,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const SizedBox.shrink();
                          }
                          if (snapshot.hasError) {
                            return TextButton(
                              onPressed: () => setState(_readMemberships),
                              child: const Text(
                                'Reintentar lectura de membresías',
                              ),
                            );
                          }
                          if (snapshot.data!.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return AppButton(
                            label: 'Espacio institucional',
                            onPressed: _openInstitution,
                            style: AppButtonStyle.outline,
                          );
                        },
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    if (widget.onVerify != null)
                      AppButton(
                        label: 'Verificar certificado',
                        onPressed: widget.onVerify,
                        style: AppButtonStyle.outline,
                      ),
                    if (_section != AuthenticatedSection.profile)
                      WalletContent(
                        future: _wallet,
                        onRetry: () => setState(_readWallet),
                        now: DateTime.now(),
                        recent: home,
                        homeActions: home ? _quickActions(context) : null,
                        onOpenWallet: () => _open(AuthenticatedSection.wallet),
                        onOpenCertificate: _openCertificate,
                      ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (widget.controller.message case final message?)
                      Semantics(liveRegion: true, child: Text(message)),
                    AppButton(
                      label: 'Cerrar sesión',
                      isLoading: widget.controller.signingOut,
                      onPressed: widget.controller.signOut,
                      style: AppButtonStyle.ghost,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: AppBottomNavigation(
          selectedIndex: _section.index,
          onSelected: (index) => _open(AuthenticatedSection.values[index]),
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Accesos rápidos', style: AppTypography.sectionTitle),
      const SizedBox(height: AppSpacing.md),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: AppSpacing.quickActionGap,
          runSpacing: AppSpacing.md,
          children: [
            for (final action in [
              (
                'Mis certificados',
                AppIcons.certificate,
                () => _open(AuthenticatedSection.wallet),
              ),
              ('Añadir certificado', AppIcons.add, null),
              ('Escanear QR', AppIcons.scan, null),
              (
                'Mi perfil',
                AppIcons.profile,
                () => _open(AuthenticatedSection.profile),
              ),
            ])
              SizedBox(
                width:
                    MediaQuery.textScalerOf(context).scale(1) >=
                        AppSizes.singleColumnTextScale
                    ? constraints.maxWidth
                    : (constraints.maxWidth - AppSpacing.quickActionGap) / 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppRadius.quickAction,
                      ),
                    ),
                    side: const BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.background,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    foregroundColor: AppColors.inkBlue,
                    disabledForegroundColor: AppColors.textSecondary,
                    minimumSize: const Size(0, AppSizes.quickAction),
                  ),
                  onPressed: action.$3,
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          action.$2,
                          color: action.$3 == null
                              ? AppColors.textSecondary
                              : AppColors.brandPrimary,
                          size: AppSizes.iconLarge,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(action.$1, style: AppTypography.caption),
                        if (action.$3 == null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'No disponible',
                            style: AppTypography.caption,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xxl),
    ],
  );
}
