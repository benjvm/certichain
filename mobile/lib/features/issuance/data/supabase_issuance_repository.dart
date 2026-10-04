import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/issuance_repository.dart';

class SupabaseIssuanceRepository implements IssuanceRepository {
  SupabaseIssuanceRepository(
    this.client, {
    required this.apiUrl,
    required this.publicKey,
    http.Client? transport,
  }) : transport = transport ?? http.Client();
  final SupabaseClient client;
  final String apiUrl;
  final String publicKey;
  final http.Client transport;
  @override
  Future<String> issue(IssuanceRequest request) async {
    final session = client.auth.currentSession;
    if (session == null ||
        session.user.id != request.actorId ||
        session.isExpired) {
      throw const IssuanceException('unauthenticated');
    }
    final form =
        http.MultipartRequest(
            'POST',
            Uri.parse('$apiUrl/functions/v1/issue-certificate'),
          )
          ..headers.addAll({
            'apikey': publicKey,
            'Authorization': 'Bearer ${session.accessToken}',
          })
          ..fields.addAll({
            'institution_id': request.institutionId,
            'holder_id': request.data.holderId,
            'idempotency_key': request.key,
            'title': request.data.title,
          })
          ..files.add(
            http.MultipartFile.fromBytes(
              'pdf',
              request.pdf.bytes,
              filename: request.pdf.name,
              contentType: MediaType('application', 'pdf'),
            ),
          );
    if (request.data.description != null) {
      form.fields['description'] = request.data.description!;
    }
    if (request.data.expiresAt != null) {
      form.fields['expires_at'] = request.data.expiresAt!;
    }
    try {
      final response = await http.Response.fromStream(
        await transport.send(form).timeout(const Duration(seconds: 90)),
      ).timeout(const Duration(seconds: 20));
      if (client.auth.currentSession?.user.id != request.actorId) {
        throw const IssuanceException('unauthenticated');
      }
      if (response.statusCode == 401) {
        throw const IssuanceException('unauthenticated');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if ([200, 201].contains(response.statusCode) &&
          data['status'] == 'completed' &&
          data['certificate_id'] is String &&
          isUuid(data['certificate_id'] as String)) {
        return data['certificate_id'] as String;
      }
      const errors = [
        'unauthenticated',
        'forbidden',
        'invalid_input',
        'invalid_pdf',
        'payload_too_large',
        'idempotency_conflict',
        'operation_in_progress',
        'attempt_failed',
        'temporary_failure',
        'stored_object_invalid',
      ];
      final code = data['error'];
      final retry = int.tryParse(response.headers['retry-after'] ?? '') ?? 120;
      throw IssuanceException(
        errors.contains(code) ? code as String : 'response_lost',
        retryAfter: retry.clamp(1, 86400),
      );
    } on IssuanceException {
      rethrow;
    } catch (_) {
      throw const IssuanceException('response_lost');
    }
  }
}
