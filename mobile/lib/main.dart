import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'features/auth/data/supabase_auth_repository.dart';
import 'features/profile/data/supabase_profile_repository.dart';
import 'features/certificates/data/supabase_certificate_repository.dart';

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
