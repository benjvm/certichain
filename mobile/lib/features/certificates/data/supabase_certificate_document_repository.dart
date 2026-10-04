import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/certificate_document_repository.dart';
import '../../issuance/domain/issuance_repository.dart';
import 'pdf_saver.dart';

class SupabaseCertificateDocumentRepository
    implements CertificateDocumentRepository {
  SupabaseCertificateDocumentRepository(
    this.client, {
    required this.apiUrl,
    required this.publicKey,
    http.Client? transport,
    Future<bool> Function(Uint8List)? saver,
  }) : transport = transport ?? http.Client(),
       saver = saver ?? savePdf;
  final SupabaseClient client;
  final String apiUrl;
  final String publicKey;
  final http.Client transport;
  final Future<bool> Function(Uint8List) saver;
  void _session(String userId) {
    final session = client.auth.currentSession;
    if (session == null || session.user.id != userId || session.isExpired) {
      throw const DocumentException('unauthenticated');
    }
  }

  Future<Uri?> _authorize(String userId, String certificateId) async {
    _session(userId);
    final response = await transport
        .post(
          Uri.parse('$apiUrl/functions/v1/certificate-pdf'),
          headers: {
            'apikey': publicKey,
            'Authorization':
                'Bearer ${client.auth.currentSession!.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'certificate_id': certificateId}),
        )
        .timeout(const Duration(seconds: 30));
    _session(userId);
    if (response.statusCode == 401) {
      throw const DocumentException('unauthenticated');
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw const DocumentException('temporary_failure');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final path = data['signed_url'] as String;
    final ttl = data['expires_in'] as int;
    if (ttl < 1 ||
        ttl > 60 ||
        !path.startsWith('/storage/v1/object/sign/certificates/') ||
        path.startsWith('//')) {
      throw const DocumentException('temporary_failure');
    }
    return Uri.parse(apiUrl).resolve(path);
  }

  @override
  Future<bool> isAvailable(String userId, String certificateId) async {
    try {
      return await _authorize(userId, certificateId) != null;
    } on DocumentException {
      rethrow;
    } catch (_) {
      throw const DocumentException('temporary_failure');
    }
  }

  @override
  Future<bool> download(String userId, String certificateId) async {
    try {
      final url = await _authorize(userId, certificateId);
      if (url == null) throw const DocumentException('document_unavailable');
      // A capability URL: no Authorization header or session token forwarded.
      final response = await transport
          .send(http.Request('GET', url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 ||
          response.headers['content-type']?.split(';').first !=
              'application/pdf') {
        throw const DocumentException('document_unavailable');
      }
      final bytes = BytesBuilder();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        if (bytes.length + chunk.length > maxPdfBytes) {
          throw const DocumentException('document_unavailable');
        }
        bytes.add(chunk);
      }
      _session(userId);
      if (bytes.isEmpty) throw const DocumentException('document_unavailable');
      return await saver(bytes.takeBytes());
    } on DocumentException {
      rethrow;
    } catch (_) {
      throw const DocumentException('temporary_failure');
    }
  }
}
