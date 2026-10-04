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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = AppConfig.fromEnvironment(allowLocalHttp: kDebugMode);
    final supabase = await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    runApp(
      CertiChainApp(
        authRepository: SupabaseAuthRepository(supabase.client),
        profileRepository: SupabaseProfileRepository(supabase.client),
        certificateRepository: SupabaseCertificateRepository(supabase.client),
        institutionRepository: SupabaseInstitutionRepository(supabase.client),
        issuanceRepository: SupabaseIssuanceRepository(
          supabase.client,
          apiUrl: config.supabaseUrl,
          publicKey: config.supabasePublishableKey,
        ),
        pdfPicker: PlatformPdfPicker(),
        pendingStore: PendingAttemptPreferences(),
        documents: SupabaseCertificateDocumentRepository(
          supabase.client,
          apiUrl: config.supabaseUrl,
          publicKey: config.supabasePublishableKey,
        ),
      ),
    );
  } catch (error) {
    // Never print SDK payloads or configuration values during failed startup.
    final message = error is FormatException
        ? 'Configuración de Auth no válida. Revisa SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY.'
        : 'No se pudo iniciar la autenticación. Reinicia la aplicación.';
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(child: Center(child: Text(message))),
        ),
      ),
    );
  }
}
