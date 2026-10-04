import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/data/supabase_auth_repository.dart';
import 'package:mobile/features/profile/data/supabase_profile_repository.dart';
import 'package:mobile/features/certificates/data/supabase_certificate_repository.dart';
import 'package:mobile/features/certificates/presentation/certificate_card.dart';
import 'package:mobile/features/certificates/presentation/certificate_detail_screen.dart';
import 'package:mobile/features/verification/data/http_verification_repository.dart';
import 'package:mobile/features/verification/data/supabase_credential_repository.dart';
import 'package:mobile/features/verification/domain/verification_link.dart';
import 'package:mobile/features/verification/presentation/credential_share.dart';
import 'package:mobile/features/verification/presentation/verification_screen.dart';

/// Isolated test entrypoint. CertiChainApp and production adapters, real HTTP.
/// Host drives browser URL/history/reload through CDP, never RouteSettings.
class PublicTransport extends http.BaseClient {
  final delegate = http.Client();
  int queries = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    queries++;
    if (request.headers.keys.any(
      (k) => ['authorization', 'apikey', 'cookie'].contains(k.toLowerCase()),
    )) {
      throw StateError('Public request contains credentials');
    }
    return delegate.send(request);
  }

  @override
  void close() => delegate.close();
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LiveWidgetController(binding);
  final transport = PublicTransport();
  void attr(String name, String value) =>
      web.document.documentElement!.setAttribute(name, value);
  bool text(String value) => find.text(value).evaluate().isNotEmpty;
  Future<void> wait(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) throw StateError('UI deadline');
      await controller.pump(const Duration(milliseconds: 25));
    }
  }

  Future<void> tap(Finder finder) async {
    await wait(() => finder.evaluate().length == 1);
    await wait(() {
      final route = ModalRoute.of(controller.element(finder));
      return route == null ||
          (route.animation?.isCompleted == true &&
              route.secondaryAnimation?.isDismissed == true);
    });
    await controller.ensureVisible(finder);
    await controller.pump();
    await controller.tap(finder);
    await controller.pump();
  }

  Future<void> click(String label) async {
    final button = find.byWidgetPredicate(
      (w) => w is AppButton && w.label == label,
    );
    final tooltip = find.byTooltip(label);
    await tap(
      button.evaluate().isNotEmpty
          ? button
          : tooltip.evaluate().isNotEmpty
          ? tooltip
          : find.text(label),
    );
  }

  Future<void> enter(String label, String value) async {
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tap(field);
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    controller
        .state<EditableTextState>(editable)
        .updateEditingValue(TextEditingValue(text: value));
    await controller.pump();
  }

  try {
    if (web.window.location.hostname != '127.0.0.1') {
      throw StateError('Local harness only');
    }
    final fixture = jsonDecode(
      (await http.get(Uri.parse('${web.window.location.origin}/fixture'))).body,
    ) as Map<String, dynamic>;
    final api = fixture['apiUrl'] as String;
    if (!RegExp(r'^http://127\.0\.0\.1:(54321|55321)$').hasMatch(api)) {
      throw StateError('Local API required');
    }
    final verification = HttpVerificationRepository(
      apiUrl: api,
      client: transport,
    );
    final link = VerificationLink(
      web.window.location.origin,
      allowLocalHttp: true,
    );
    // Mount before SDK/Auth restore. Later runApp updates the same app State.
    runApp(CertiChainApp(verification: verification, verificationLink: link));
    await controller.pump();
    final sdk = await Supabase.initialize(
      url: api,
      publishableKey: fixture['publicKey'] as String,
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    final client = sdk.client;
    final auth = SupabaseAuthRepository(client);
    final app = CertiChainApp(
      authRepository: auth,
      profileRepository: SupabaseProfileRepository(client),
      certificateRepository: SupabaseCertificateRepository(client),
      verification: verification,
      credentials: SupabaseCredentialRepository(client),
      verificationLink: link,
    );
    runApp(app);
    await controller.pump();
    attr('data-8b-ready', '1');
    var last = '';
    while (true) {
      final command = web.document.documentElement!.getAttribute(
        'data-8b-command',
      );
      if (command != null && command != last) {
        last = command;
        final data = jsonDecode(command) as Map<String, dynamic>;
        final id = data['id'];
        try {
          final action = data['action'];
          if (action == 'click') {
            await click(data['label'] as String);
          } else if (action == 'enter') {
            await enter(data['label'] as String, data['value'] as String);
          } else if (action == 'login') {
            final user = fixture[data['user']] as Map<String, dynamic>;
            await auth.signIn(
              email: user['email'] as String,
              password: user['password'] as String,
            );
            await controller.pump();
          } else if (action == 'logout') {
            await auth.signOut();
            await controller.pump();
          } else if (action == 'renew') {
            await client.auth.refreshSession();
            await controller.pump();
          } else if (action == 'open') {
            await tap(
              find.byWidgetPredicate(
                (w) =>
                    w is CertificateCard &&
                    w.certificate.id == data['certificate'],
              ),
            );
          } else if (action == 'probeOwn') {
            final ownCode = await SupabaseCredentialRepository(client)
                .readOwnCode(
                  client.auth.currentUser!.id,
                  data['certificate'] as String,
                );
            attr('data-8b-own-code', jsonEncode(ownCode));
          } else if (action == 'rebuild') {
            runApp(app);
            await controller.pump();
          } else if (action == 'qr') {
            final qr = find.byType(VerificationQr);
            await controller.ensureVisible(qr);
            await controller.pump();
            final boundary = find.descendant(
              of: qr,
              matching: find.byType(RepaintBoundary),
            );
            final image =
                await (controller.element(boundary).findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            attr('data-8b-qr', base64Encode(bytes!.buffer.asUint8List()));
            image.dispose();
          }
          attr('data-8b-result', jsonEncode({'id': id, 'ok': true}));
        } catch (_) {
          attr('data-8b-result', jsonEncode({'id': id, 'ok': false}));
        }
      }
      final statuses = <String>[
        'Registro encontrado y vigente',
        'Certificado revocado',
        'Certificado caducado',
        'Emisor sin aprobación vigente',
        'No encontramos un registro verificable con este código',
        'Enlace copiado',
        'Este certificado no dispone de enlace verificable.',
        'La comprobación está temporalmente no disponible.',
      ];
      attr(
        'data-8b-state',
        jsonEncode({
          'queries': transport.queries,
          'session': client.auth.currentUser?.id,
          'public': find.byType(VerificationScreen).evaluate().isNotEmpty,
          'detail': find.byType(CertificateDetailScreen).evaluate().isNotEmpty,
          'qr': find.byType(VerificationQr).evaluate().isNotEmpty,
          'texts': statuses.where(text).toList(),
          'code':
              find.byType(TextField).evaluate().isNotEmpty &&
                  find.byType(VerificationScreen).evaluate().isNotEmpty
              ? controller
                    .widget<TextField>(find.byType(TextField))
                    .controller
                    ?.text
              : null,
        }),
      );
      await controller.pump(const Duration(milliseconds: 25));
    }
  } catch (_) {
    attr('data-8b-ready', 'FAIL');
  }
}
