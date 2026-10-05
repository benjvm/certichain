import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import 'package:mobile/app/app.dart';
import 'package:mobile/core/widgets/app_button.dart';
import 'package:mobile/features/auth/data/supabase_auth_repository.dart';
import 'package:mobile/features/profile/data/supabase_profile_repository.dart';
import 'package:mobile/features/certificates/data/supabase_certificate_repository.dart';
import 'package:mobile/features/certificates/data/supabase_certificate_document_repository.dart';
import 'package:mobile/features/certificates/presentation/certificate_card.dart';
import 'package:mobile/features/certificates/presentation/certificate_detail_screen.dart';
import 'package:mobile/features/institutions/data/supabase_institution_repository.dart';
import 'package:mobile/features/institutions/presentation/institution_workspace.dart';
import 'package:mobile/features/issuance/data/supabase_issuance_repository.dart';
import 'package:mobile/features/issuance/data/platform_pdf_picker.dart';
import 'package:mobile/features/issuance/data/pending_attempt_preferences.dart';
import 'package:mobile/features/issuance/domain/issuance_repository.dart';
import 'package:mobile/features/issuance/presentation/issuance_screen.dart';

// Separate test entrypoint, never imported by main.dart. Uses the production app,
// SDK, repositories, picker, persistence and saver. No network response is mocked.
// Faults only retain/discard an already received REAL response at a test barrier.
class ObservedTransport extends http.BaseClient {
  final http.Client delegate = http.Client();
  int issues = 0, authorizations = 0;
  String? lastKey, lastCertificate, expiredDocumentToken;
  bool loseIssue = false, holdIssued = false, holdMembers = false;
  Completer<void>? arrived, release, delivered;
  void barrier({bool memberships = false}) {
    holdIssued = !memberships;
    holdMembers = memberships;
    arrived = Completer<void>();
    release = Completer<void>();
    delivered = Completer<void>();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final issue = request.url.path.endsWith('/issue-certificate');
    final document = request.url.path.endsWith('/certificate-pdf');
    if (issue) {
      issues++;
      lastKey = (request as http.MultipartRequest).fields['idempotency_key'];
    }
    if (document) {
      authorizations++;
      if (expiredDocumentToken != null) {
        request.headers['Authorization'] = 'Bearer $expiredDocumentToken';
        expiredDocumentToken = null;
      }
    }
    if (request.url.path.contains('/object/sign/')) {
      verify(
        !request.headers.keys.any((k) => k.toLowerCase() == 'authorization'),
        'No session JWT on capability GET',
      );
    }
    final gated =
        (holdIssued && request.url.path.endsWith('/certificates')) ||
        (holdMembers && request.url.path.endsWith('/institution_members'));
    if (gated) {
      holdIssued = false;
      holdMembers = false;
    }
    final response = await http.Response.fromStream(
      await delegate.send(request),
    );
    if (issue || document) {
      if (response.statusCode != 401) {
        verify(
          response.headers['cache-control'] == 'no-store',
          'Endpoint no-store',
        );
      }
      verify(
        !response.body.contains('service_role'),
        'No service credential in response',
      );
    }
    if (issue && [200, 201].contains(response.statusCode)) {
      lastCertificate =
          (jsonDecode(response.body) as Map<String, dynamic>)['certificate_id']
              as String;
    }
    if (gated) {
      arrived!.complete();
      await release!.future.timeout(const Duration(seconds: 25));
      delivered!.complete();
    }
    if (issue && loseIssue) {
      loseIssue = false;
      throw http.ClientException('Local test discarded the received response');
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() => delegate.close();
}

int assertions = 0;
void verify(bool condition, String label) {
  if (!condition) throw StateError(label);
  assertions++;
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final ui = LiveWidgetController(binding);
  final transport = ObservedTransport();
  Supabase? sdk;
  String stage = 'startup';
  Future<void> wait(bool Function() condition, String label) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) throw StateError('Timeout: $label');
      await ui.pump(const Duration(milliseconds: 25));
    }
  }

  bool text(String value) => find.text(value).evaluate().isNotEmpty;
  Finder button(String label) =>
      find.byWidgetPredicate((w) => w is AppButton && w.label == label);
  Future<void> tapFinder(Finder target) async {
    bool present() {
      try {
        return target.evaluate().length == 1;
      } on StateError {
        return false;
      }
    }

    await wait(present, 'widget exists');
    await wait(() {
      if (!present()) return false;
      final route = ModalRoute.of(ui.element(target));
      return route == null ||
          (route.animation?.isCompleted == true &&
              route.secondaryAnimation?.isDismissed == true);
    }, 'route ready for pointer');
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (true) {
      if (present()) {
        await ui.ensureVisible(target);
        await ui.pump();
        if (target.hitTestable().evaluate().isNotEmpty) break;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'Pointer cannot reach ${target.describeMatch(Plurality.one)}',
        );
      }
      await ui.pump(const Duration(milliseconds: 25));
    }
    await ui.tap(target);
    await ui.pump();
  }

  Future<void> tap(String label) async {
    await wait(
      () =>
          button(label).evaluate().isNotEmpty ||
          find.text(label).evaluate().isNotEmpty,
      'action $label',
    );
    await tapFinder(
      button(label).evaluate().isNotEmpty
          ? button(label)
          : find.text(label).last,
    );
  }

  Future<void> enter(Finder target, String value) async {
    await tapFinder(target);
    final editable = find.descendant(
      of: target,
      matching: find.byType(EditableText),
    );
    ui
        .state<EditableTextState>(editable)
        .updateEditingValue(TextEditingValue(text: value));
    await ui.pump();
    verify(
      ui.widget<EditableText>(editable).controller.text == value,
      'UI text input reached its controller',
    );
  }

  Future<Map<String, dynamic>> checkpoint(
    String name, [
    Map<String, dynamic> body = const {},
  ]) async {
    final response = await http.post(
      Uri.parse('${web.window.location.origin}/checkpoint/$name'),
      body: jsonEncode(body),
    );
    verify(response.statusCode == 200, 'Host checkpoint $name');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  try {
    verify(
      web.window.location.hostname == '127.0.0.1',
      'Test build requires loopback',
    );
    final fixture = jsonDecode(
      (await http.get(Uri.parse('${web.window.location.origin}/fixture'))).body,
    ) as Map<String, dynamic>;
    final apiUrl = fixture['apiUrl'] as String,
        publicKey = fixture['publicKey'] as String;
    verify(
      const [
        'http://127.0.0.1:54321',
        'http://127.0.0.1:55321',
      ].contains(apiUrl),
      'Only CertiChain local API',
    );
    final verified = fixture['verified'] as String;
    final holder = fixture['holder'] as Map<String, dynamic>;
    final owner = fixture['owner'] as Map<String, dynamic>;
    final bytes = base64Decode(fixture['pdf'] as String);
    sdk = await Supabase.initialize(
      url: apiUrl,
      publishableKey: publicKey,
      httpClient: transport,
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    final client = sdk.client;
    final institutions = SupabaseInstitutionRepository(client);
    final certificates = SupabaseCertificateRepository(client);
    final store = PendingAttemptPreferences();
    final documents = SupabaseCertificateDocumentRepository(
      client,
      apiUrl: apiUrl,
      publicKey: publicKey,
      transport: transport,
    );
    runApp(
      CertiChainApp(
        authRepository: SupabaseAuthRepository(client),
        profileRepository: SupabaseProfileRepository(client),
        certificateRepository: certificates,
        institutionRepository: institutions,
        issuanceRepository: SupabaseIssuanceRepository(
          client,
          apiUrl: apiUrl,
          publicKey: publicKey,
          transport: transport,
        ),
        pdfPicker: PlatformPdfPicker(),
        pendingStore: store,
        documents: documents,
      ),
    );
    // A live build attaches its root on the first frame, unlike pumpWidget.
    await ui.pump();
    Future<void> login(Map<String, dynamic> user) async {
      await wait(() => text('Comenzar'), 'welcome after account change');
      await tap('Comenzar');
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await enter(field('Email'), user['email'] as String);
      await enter(field('Contraseña'), user['password'] as String);
      await tap('Iniciar sesión');
      await wait(() => text('Cerrar sesión'), 'real Auth login UI');
      verify(client.auth.currentUser?.id == user['id'], 'SDK current identity');
    }

    Future<void> select(String name) async {
      await tapFinder(find.byType(DropdownButton<String>));
      await tapFinder(find.text(name).last);
      await wait(
        () => !text('Cargando certificados emitidos'),
        'institution list settled',
      );
    }

    Future<void> choose(Uint8List selected) async {
      await wait(
        () => text('Seleccionar PDF') || text('Reemplazar PDF'),
        'document step ready',
      );
      await tap(text('Seleccionar PDF') ? 'Seleccionar PDF' : 'Reemplazar PDF');
      await wait(
        () => web.document.querySelector('#certichain-pdf-input') != null,
        'real DOM picker',
      );
      final input =
          web.document.querySelector('#certichain-pdf-input')!
              as web.HTMLInputElement;
      final transfer = web.DataTransfer();
      transfer.items.add(
        web.File(
          [selected.toJS].toJS,
          'synthetic.pdf',
          web.FilePropertyBag(type: 'application/pdf'),
        ),
      );
      input.files = transfer.files;
      input.dispatchEvent(web.Event('change'));
      await wait(
        () => web.document.querySelector('#certichain-pdf-input') == null,
        'picker read complete',
      );
      await ui.pump();
    }

    Future<void> confirm(
      String holderId,
      Uint8List pdf, {
      String title = '7D UI Certificate',
    }) async {
      await wait(
        () => button('Siguiente').evaluate().isNotEmpty,
        'issuance permission/read receipt',
      );
      await enter(find.byKey(const Key('holder-id')), holderId);
      await enter(find.byKey(const Key('issuance-title')), title);
      await tap('Siguiente');
      await choose(pdf);
      await tap('Siguiente');
      await wait(() => text('Revisa antes de emitir'), 'confirmation');
    }

    Future<void> newAfterDenial() async {
      await tap('Revisé la operación · Iniciar una emisión nueva');
      await tap('Iniciar emisión nueva');
      await wait(
        () => find.byKey(const Key('holder-id')).evaluate().isNotEmpty,
        'explicit new attempt',
      );
    }

    stage = 'institution states';
    await login(owner);
    await wait(() => text('Espacio institucional'), 'real memberships');
    await tap('Espacio institucional');
    await wait(
      () => find.byType(DropdownButton<String>).evaluate().isNotEmpty,
      'institution selector',
    );
    for (final name in ['7D Pending', '7D Suspended']) {
      await select(name);
      verify(
        ui.widget<AppButton>(button('Emitir certificado')).onPressed == null,
        'Invalid institution cannot issue in UI',
      );
    }
    verify(transport.issues == 0, 'Institution blocks did not send');
    await select('7D Verified');
    await tap('Emitir certificado');
    stage = 'UI denials';
    await confirm('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', bytes);
    await tap('Emitir certificado');
    await wait(
      () => find
          .textContaining('Revisa los datos y confirma el ID')
          .evaluate()
          .isNotEmpty,
      'ineligible holder UI',
    );
    await newAfterDenial();
    await confirm(
      holder['id'] as String,
      Uint8List.fromList(utf8.encode('not PDF')),
    );
    await tap('Emitir certificado');
    await wait(
      () =>
          find.textContaining('Selecciona un PDF válido').evaluate().isNotEmpty,
      'real PDF parser denial UI',
    );
    await newAfterDenial();
    await enter(find.byKey(const Key('holder-id')), holder['id'] as String);
    await enter(find.byKey(const Key('issuance-title')), '7D UI Certificate');
    await tap('Siguiente');
    final beforeLarge = transport.issues;
    await choose(Uint8List(maxPdfBytes + 1));
    await wait(
      () => text(const IssuanceException('payload_too_large').message),
      'oversize UI',
    );
    verify(transport.issues == beforeLarge, 'Oversize picker did not send');
    await choose(bytes);
    await tap('Siguiente');
    stage = 'lost response and reconstruction';
    transport.loseIssue = true;
    final beforeIssue = transport.issues;
    // Two pointer taps while membership revalidation is pending, same logical attempt.
    await tap('Emitir certificado');
    if (button('Emitir certificado').evaluate().isNotEmpty) {
      await tap('Emitir certificado');
    }
    await wait(
      () => text(const IssuanceException('response_lost').message),
      'lost real publication response UI',
    );
    verify(
      transport.issues == beforeIssue + 1 && !text('Certificado emitido'),
      'Single flight and honest uncertain UI',
    );
    final receipt = await store.read(owner['id'] as String, verified);
    verify(
      receipt != null && receipt.key == transport.lastKey,
      'Receipt existed before HTTP and survives lost response',
    );
    final persisted = await checkpoint('published', {
      'key': receipt!.key,
      'digest': receipt.digest,
      'certificateId': transport.lastCertificate,
    });
    final certificateId = persisted['certificateId'] as String;
    stage = 'reopen persisted receipt';
    await tapFinder(find.byTooltip('Volver'));
    await wait(
      () => find.byType(IssuanceScreen).evaluate().isEmpty,
      'issuance route closed',
    );
    await tap('Emitir certificado');
    await confirm(
      holder['id'] as String,
      bytes,
      title: 'Changed reconstruction',
    );
    await tap('Emitir certificado');
    await wait(
      () => text(const IssuanceException('reconstruction_mismatch').message),
      'mismatched receipt blocked',
    );
    verify(transport.issues == beforeIssue + 1, 'Mismatch never sent');
    await tap('Anterior');
    await tap('Anterior');
    await enter(find.byKey(const Key('issuance-title')), '7D UI Certificate');
    await tap('Siguiente');
    await tap('Siguiente');
    await tap('Emitir certificado');
    await wait(() => text('Certificado emitido'), 'recovered completed UI');
    verify(
      transport.lastKey == receipt.key &&
          transport.lastCertificate == certificateId,
      'Same key and ID on completed retry',
    );
    verify(
      await store.read(owner['id'] as String, verified) == null,
      'Confirmed receipt cleared',
    );
    await checkpoint('published', {
      'key': receipt.key,
      'digest': receipt.digest,
      'certificateId': certificateId,
    });
    await checkpoint('denials');
    await tap('Ir a Certificados emitidos');
    await wait(() => text('7D UI Certificate'), 'real institutional list');
    stage = 'institution response barrier';
    transport.barrier();
    await tapFinder(find.byTooltip('Actualizar datos'));
    await transport.arrived!.future.timeout(const Duration(seconds: 25));
    await select('7D Pending');
    transport.release!.complete();
    await transport.delivered!.future;
    await ui.pump();
    verify(
      !text('7D UI Certificate') &&
          text('Todavía no hay certificados emitidos'),
      'Old institution response never shown after selection',
    );
    stage = 'identity response barrier';
    transport.barrier();
    final oldRead = institutions.readIssued(verified);
    final rejected = oldRead.then((_) => false, onError: (Object _) => true);
    await transport.arrived!.future;
    final outsider = fixture['outsider'] as Map<String, dynamic>;
    await client.auth.signInWithPassword(
      email: outsider['email'] as String,
      password: outsider['password'] as String,
    );
    transport.release!.complete();
    verify(await rejected, 'Real delayed read discarded after identity change');
    await wait(
      () =>
          text('Cerrar sesión') &&
          find.byType(InstitutionWorkspace).evaluate().isEmpty,
      'new identity removed institution route',
    );
    await wait(
      () => text('Aún no tienes certificados'),
      'outsider empty wallet',
    );
    verify(
      !text('7D UI Certificate') && !text('Espacio institucional'),
      'No former-account content',
    );
    verify(
      await certificates.readCertificate(
                outsider['id'] as String,
                certificateId,
              ) ==
              null &&
          !await documents.isAvailable(outsider['id'] as String, certificateId),
      'Foreign detail and PDF unavailable through real adapters',
    );
    await tap('Cerrar sesión');
    stage = 'renewal response barrier';
    await login(fixture['issuer'] as Map<String, dynamic>);
    await wait(() => text('Espacio institucional'), 'issuer memberships');
    transport.barrier(memberships: true);
    final oldMembers = institutions.readMemberships(
      client.auth.currentUser!.id,
    );
    final rejectedMembers = oldMembers.then(
      (_) => false,
      onError: (Object _) => true,
    );
    await transport.arrived!.future;
    await client.auth.refreshSession();
    transport.release!.complete();
    verify(
      await rejectedMembers,
      'Real delayed membership response discarded after renewal',
    );
    await tap('Espacio institucional');
    await wait(() => text('7D UI Certificate'), 'issuer authorized list');
    await checkpoint('remove-member');
    await tapFinder(find.byTooltip('Actualizar datos'));
    await wait(
      () => text('Sin membresías institucionales'),
      'membership withdrawal UI',
    );
    verify(!text('7D UI Certificate'), 'Membership removal clears issued list');
    await tapFinder(find.byTooltip('Volver'));
    await tap('Cerrar sesión');
    await checkpoint('suspend');
    stage = 'holder wallet and real Blob downloads';
    await login(holder);
    await wait(() => text('7D UI Certificate'), 'correct holder wallet');
    verify(
      find.byType(CertificateCard).evaluate().length == 2,
      'Only new certificate and synthetic legacy in holder wallet',
    );
    await tapFinder(find.text('7D UI Certificate'));
    await wait(
      () =>
          find.byType(CertificateDetailScreen).evaluate().isNotEmpty &&
          text('Descargar PDF'),
      'holder detail',
    );
    var blobs = 0;
    final downloads = <Future<void>>[];
    final location = web.window.location.href;
    final listener = ((web.Event event) {
      final target = event.target;
      if (target == null || !target.isA<web.HTMLAnchorElement>()) return;
      final anchor = target as web.HTMLAnchorElement;
      if (!anchor.href.startsWith('blob:')) return;
      event.preventDefault();
      final url = anchor.href;
      downloads.add(() async {
        final response = await web.window.fetch(url.toJS).toDart;
        final downloaded = (await response.arrayBuffer().toDart).toDart
            .asUint8List();
        verify(
          downloaded.join(',') == bytes.join(','),
          'Real saved Blob preserves exact final bytes',
        );
        blobs++;
      }());
    }).toJS;
    web.document.addEventListener('click', listener);
    try {
      final authorizations = transport.authorizations;
      await tap('Descargar PDF');
      await wait(() => blobs == 1, 'first actual Blob');
      await wait(
        () => text('Descarga enviada. Revisa tus archivos.'),
        'download success UI',
      );
      await tap('Descargar PDF');
      await wait(() => blobs == 2, 'second actual Blob');
      await Future.wait(downloads);
      verify(
        transport.authorizations == authorizations + 2 &&
            web.window.location.href == location,
        'Each download reauthorizes/no URL navigation',
      );
    } finally {
      web.document.removeEventListener('click', listener);
    }
    await tapFinder(find.byTooltip('Volver'));
    await tapFinder(find.text('7D Legacy'));
    await wait(
      () => text('Este certificado no tiene un PDF disponible o accesible.'),
      'legacy detail no PDF',
    );
    await tapFinder(find.byTooltip('Volver'));
    await tapFinder(find.text('7D UI Certificate'));
    await wait(
      () => text('Descargar PDF'),
      'PDF authorized after suspension for holder',
    );
    stage = 'expired JWT on real gateway';
    transport.expiredDocumentToken = fixture['expiredToken'] as String;
    await tap('Descargar PDF');
    await wait(() => text('Comenzar'), 'real 401 discards session/routes');
    verify(
      !text('7D UI Certificate') &&
          find.byType(CertificateDetailScreen).evaluate().isEmpty,
      'Expired session destroys visible data',
    );
    await checkpoint('final');
    web.document.documentElement!.setAttribute(
      'data-7d-result',
      'PASS Flutter Web 7D: $assertions assertions',
    );
  } catch (error) {
    // Never include credentials, responses, capabilities or fixture values in diagnostics.
    web.document.documentElement!.setAttribute(
      'data-7d-result',
      'FAIL Flutter Web 7D at $stage: ${error.runtimeType}${error is StateError || error is FlutterError || error is UnsupportedError ? ': ${error.toString().split('\n').first}' : ''}',
    );
  } finally {
    runApp(const SizedBox.shrink());
    await ui.pump();
    await sdk?.dispose();
    transport.close();
  }
}
