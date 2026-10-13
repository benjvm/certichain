import 'package:flutter/material.dart';

import '../../features/verification/domain/verification_repository.dart';
import '../../features/verification/domain/hash_comparison.dart';
import '../../features/verification/domain/blockchain_verification.dart';
import '../../features/verification/domain/verification_link.dart';
import '../../features/verification/presentation/qr_scanner_panel.dart';
import '../../features/verification/presentation/public_query_cooldown.dart';
import '../../features/verification/presentation/verification_screen.dart';

class PublicLocation {
  const PublicLocation(
    this.path, {
    this.public = false,
    this.code,
    this.invalid = false,
  });
  final String path;
  final bool public, invalid;
  final String? code;
  static PublicLocation parse(Uri uri) {
    if (uri.hasQuery || uri.hasFragment || uri.hasAuthority) {
      return const PublicLocation('/verify', public: true, invalid: true);
    }
    if (uri.path == '/verify') {
      return const PublicLocation('/verify', public: true);
    }
    if (uri.path.startsWith('/verify/')) {
      final raw = uri.path.substring(8);
      final code = normalizeCredentialCode(raw);
      if (code != null && raw.length == 36) {
        return PublicLocation('/verify/$code', public: true, code: code);
      }
      return const PublicLocation('/verify', public: true, invalid: true);
    }
    return const PublicLocation('/');
  }
}

class PublicRouteParser extends RouteInformationParser<PublicLocation> {
  const PublicRouteParser();
  @override
  Future<PublicLocation> parseRouteInformation(
    RouteInformation routeInformation,
  ) async => PublicLocation.parse(routeInformation.uri);
  @override
  RouteInformation restoreRouteInformation(PublicLocation configuration) =>
      RouteInformation(uri: Uri.parse(configuration.path));
}

/// Framework Router owns hash URL/history. The private Navigator is session keyed.
class PublicRouter extends RouterDelegate<PublicLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<PublicLocation> {
  PublicRouter({
    required this.root,
    required this.repository,
    this.comparison,
    this.picker,
    this.hasher,
    this.link,
    this.scanner,
    this.openingInput,
  });
  final HashComparisonRepository? Function()? comparison;
  final OpeningInput? Function()? openingInput;
  final ComparisonPdfPicker? Function()? picker;
  final PdfHasher? Function()? hasher;
  final VerificationLink? Function()? link;
  final ScannerSession Function()? Function()? scanner;
  final _cooldown = PublicQueryCooldown();
  PublicQueryCooldown get cooldown => _cooldown;
  @override
  void dispose() {
    _cooldown.dispose();
    super.dispose();
  }

  final WidgetBuilder root;
  final VerificationRepository? Function() repository;
  @override
  final navigatorKey = GlobalKey<NavigatorState>();
  GlobalKey<NavigatorState>? privateNavigator;
  PublicLocation _location = const PublicLocation('/');
  @override
  PublicLocation get currentConfiguration => _location;
  @override
  Future<bool> popRoute() async {
    if (_location.public) {
      home();
      return true;
    }
    return await privateNavigator?.currentState?.maybePop() ?? false;
  }

  void showVerification([String? code]) {
    _location = PublicLocation.parse(
      Uri.parse(code == null ? '/verify' : '/verify/$code'),
    );
    notifyListeners();
  }

  void home() {
    _location = const PublicLocation('/');
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(PublicLocation configuration) async {
    _location = configuration;
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: [
      MaterialPage<void>(
        key: ValueKey(_location.public ? 'public' : 'root'),
        name: _location.path,
        child: _location.public ? _public(context) : Builder(builder: root),
      ),
    ],
    onDidRemovePage: (_) {},
  );
  Widget _public(BuildContext context) {
    if (_location.invalid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verificar certificado')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('El enlace no contiene un código válido.'),
              TextButton(
                onPressed: showVerification,
                child: const Text('Introducir código'),
              ),
            ],
          ),
        ),
      );
    }
    final repo = repository();
    if (repo == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('La comprobación no está configurada.'),
              TextButton(onPressed: home, child: const Text('Volver')),
            ],
          ),
        ),
      );
    }
    return VerificationScreen(
      repository: repo,
      cooldown: _cooldown,
      comparisonRepository: comparison?.call(),
      comparisonPicker: picker?.call(),
      pdfHasher: hasher?.call(),
      openingInput: openingInput?.call(),
      verificationLink: link?.call(),
      scannerFactory: scanner?.call(),
      initialCode: _location.code,
      onHome: home,
      onCode: showVerification,
    );
  }
}
