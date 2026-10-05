import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'features/auth/data/supabase_auth_repository.dart';
import 'features/profile/data/supabase_profile_repository.dart';
import 'features/certificates/data/supabase_certificate_repository.dart';
import 'features/institutions/data/supabase_institution_repository.dart';
import 'features/issuance/data/supabase_issuance_repository.dart';
import 'features/issuance/data/platform_pdf_picker.dart';
import 'features/issuance/data/pending_attempt_preferences.dart';
import 'features/certificates/data/supabase_certificate_document_repository.dart';
import 'features/verification/data/http_verification_repository.dart';
import 'features/verification/data/platform_comparison_pdf_picker.dart';
import 'features/verification/data/sha256_pdf_hasher.dart';
import 'app/verification_scanner.dart';
import 'features/verification/data/supabase_credential_repository.dart';
import 'features/verification/domain/verification_link.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CertiChainBootstrap());
}

/// Mount public navigation before any private SDK initialization/restoration.
class CertiChainBootstrap extends StatefulWidget {
  const CertiChainBootstrap({super.key});
  @override
  State<CertiChainBootstrap> createState() => _CertiChainBootstrapState();
}

class _CertiChainBootstrapState extends State<CertiChainBootstrap> {
  HttpVerificationRepository? _verification;
  VerificationLink? _link;
  SupabaseAuthRepository? _auth;
  SupabaseProfileRepository? _profiles;
  SupabaseCertificateRepository? _certificates;
  SupabaseInstitutionRepository? _institutions;
  SupabaseIssuanceRepository? _issuance;
  SupabaseCertificateDocumentRepository? _documents;
  SupabaseCredentialRepository? _credentials;
  final _picker = PlatformPdfPicker();
  final _comparisonPicker = PlatformComparisonPdfPicker();
  final _pdfHasher = Sha256PdfHasher();
  final _store = PendingAttemptPreferences();
  String? _message;
  @override
  void initState() {
    super.initState();
    const api = String.fromEnvironment('SUPABASE_URL');
    try {
      AppConfig.validateBackendUrl(api, allowLocalHttp: kDebugMode);
      _verification = HttpVerificationRepository(apiUrl: api);
    } on FormatException {
      _message = 'Configuración del servicio no válida.';
    }
    _link = VerificationLink.tryCreate(
      const String.fromEnvironment('PUBLIC_VERIFICATION_BASE_URL'),
      allowLocalHttp: kDebugMode,
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final config = AppConfig.fromEnvironment(allowLocalHttp: kDebugMode);
      final sdk = await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
        debug: false,
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      );
      if (!mounted) return;
      final client = sdk.client;
      setState(() {
        _auth = SupabaseAuthRepository(client);
        _profiles = SupabaseProfileRepository(client);
        _certificates = SupabaseCertificateRepository(client);
        _institutions = SupabaseInstitutionRepository(client);
        _issuance = SupabaseIssuanceRepository(
          client,
          apiUrl: config.supabaseUrl,
          publicKey: config.supabasePublishableKey,
        );
        _documents = SupabaseCertificateDocumentRepository(
          client,
          apiUrl: config.supabaseUrl,
          publicKey: config.supabasePublishableKey,
        );
        _credentials = SupabaseCredentialRepository(client);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'No se pudo iniciar el acceso privado. La verificación pública sigue disponible si el servicio está configurado.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => CertiChainApp(
    authRepository: _auth,
    profileRepository: _profiles,
    certificateRepository: _certificates,
    institutionRepository: _institutions,
    issuanceRepository: _issuance,
    pdfPicker: _picker,
    pendingStore: _store,
    documents: _documents,
    verification: _verification,
    comparison: _verification,
    comparisonPicker: _comparisonPicker,
    pdfHasher: _pdfHasher,
    scannerFactory: createScannerSession,
    credentials: _credentials,
    verificationLink: _link,
    startupMessage: _message,
  );
}
