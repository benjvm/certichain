import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_controller.dart';
import '../features/certificates/domain/certificate_repository.dart';
import '../features/certificates/presentation/wallet_content.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/profile/presentation/profile_content.dart';
import '../core/widgets/app_button.dart';
import 'router/app_router.dart';
import 'theme/app_spacing.dart';
import 'theme/app_radius.dart';
import 'theme/app_colors.dart';

/// Owned by the session-keyed navigator. Never retained across identities.
class AuthenticatedArea extends StatefulWidget {
  const AuthenticatedArea({
    required this.controller,
    required this.userId,
    required this.profiles,
    required this.certificates,
    super.key,
  });
  final AuthController controller;
  final String userId;
  final ProfileRepository profiles;
  final CertificateRepository certificates;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readProfile();
    _readWallet();
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
  });
  void _open(AuthenticatedSection section) =>
      setState(() => _section = section);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
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
        appBar: AppBar(
          leading: home
              ? null
              : IconButton(
                  tooltip: 'Volver al inicio',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => _open(AuthenticatedSection.home),
                ),
          title: Text(switch (_section) {
            AuthenticatedSection.home => 'Inicio',
            AuthenticatedSection.wallet => 'Mis certificados',
            AuthenticatedSection.profile => 'Mi perfil',
          }),
          actions: [
            IconButton(
              tooltip: 'Actualizar datos',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                key: ValueKey(_section),
                padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
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
                    if (_section != AuthenticatedSection.profile)
                      WalletContent(
                        future: _wallet,
                        onRetry: () => setState(_readWallet),
                        now: DateTime.now(),
                        recent: home,
                        homeActions: home ? _quickActions(context) : null,
                        onOpenWallet: () => _open(AuthenticatedSection.wallet),
                      ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (widget.controller.message case final message?)
                      Semantics(liveRegion: true, child: Text(message)),
                    AppButton(
                      label: 'Cerrar sesión',
                      isLoading: widget.controller.signingOut,
                      onPressed: widget.controller.signOut,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _section.index,
          onDestinationSelected: (index) =>
              _open(AuthenticatedSection.values[index]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.workspace_premium_outlined),
              label: 'Certificados',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Accesos rápidos', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.md),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final action in [
              (
                'Mis certificados',
                Icons.workspace_premium_outlined,
                () => _open(AuthenticatedSection.wallet),
              ),
              (
                'Mi perfil',
                Icons.person_outline_rounded,
                () => _open(AuthenticatedSection.profile),
              ),
              (
                'Escanear QR · No disponible',
                Icons.qr_code_scanner_rounded,
                null,
              ),
              (
                'Añadir certificado · No disponible',
                Icons.add_circle_outline_rounded,
                null,
              ),
            ])
              SizedBox(
                width: (constraints.maxWidth - AppSpacing.md) / 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    side: const BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.brandPrimaryLight,
                  ),
                  onPressed: action.$3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      children: [
                        Icon(action.$2),
                        const SizedBox(height: AppSpacing.sm),
                        Text(action.$1, textAlign: TextAlign.center),
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
