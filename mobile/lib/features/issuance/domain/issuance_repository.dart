import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

const maxPdfBytes = 8388608;
bool isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);
String newAttemptKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class SelectedPdf {
  SelectedPdf({required this.name, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (!name.toLowerCase().endsWith('.pdf') || this.bytes.isEmpty) {
      throw const IssuanceException('invalid_pdf');
    }
    if (this.bytes.length > maxPdfBytes) {
      throw const IssuanceException('payload_too_large');
    }
  }
  final String name;
  final List<int> bytes;
}

/// Normalized once; reused verbatim even if the date has since expired.
class IssuanceData {
  IssuanceData({
    required String holderId,
    required String title,
    String? description,
    DateTime? expiresAt,
    DateTime? now,
    bool reconstructing = false,
  }) : holderId = holderId.trim().toLowerCase(),
       title = unicode.nfc(title.trim()),
       description = description == null || description.trim().isEmpty
           ? null
           : unicode.nfc(description.trim()),
       expiresAt = expiresAt == null ? null : normalizedExpiration(expiresAt) {
    if (!isUuid(this.holderId) ||
        titleError(this.title) != null ||
        descriptionError(this.description) != null) {
      throw const IssuanceException('invalid_input');
    }
    final clock = now ?? DateTime.now();
    if (!reconstructing &&
        expiresAt != null &&
        (!expiresAt.isAfter(clock) ||
            expiresAt.isAfter(
              DateTime.utc(
                clock.year + 10,
                clock.month,
                clock.day,
                clock.hour,
                clock.minute,
                clock.second,
              ),
            ))) {
      throw const IssuanceException('invalid_input');
    }
  }
  final String holderId;
  final String title;
  final String? description;
  final String? expiresAt;
  static String normalizedExpiration(DateTime date) {
    final iso = date.toUtc().toIso8601String();
    final parts = iso.substring(0, iso.length - 1).split('.');
    return '${parts.first}.${parts.length == 1 ? '000000' : parts.last.padRight(6, '0')}Z';
  }

  static bool _controls(String value) =>
      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value);
  static String? titleError(String value) {
    final normalized = unicode.nfc(value.trim());
    return normalized.isEmpty ||
            normalized.runes.length > 200 ||
            _controls(normalized)
        ? 'Introduce un título de 1 a 200 caracteres, sin controles.'
        : null;
  }

  static String? descriptionError(String? value) =>
      value != null &&
          (unicode.nfc(value.trim()).runes.length > 4000 ||
              _controls(value.trim()))
      ? 'La descripción admite hasta 4000 caracteres, sin controles.'
      : null;
}

class IssuanceRequest {
  const IssuanceRequest({
    required this.institutionId,
    required this.actorId,
    required this.key,
    required this.data,
    required this.pdf,
  });
  final String institutionId;
  final String actorId;
  final String key;
  final IssuanceData data;
  final SelectedPdf pdf;

  /// Same length-prefixed v1 identity as backend, without retaining metadata.
  String get digest {
    final builder = BytesBuilder()
      ..add(utf8.encode('certichain-issuance-v1'))
      ..addByte(0);
    for (final value in [
      institutionId,
      actorId,
      data.holderId,
      data.title,
      data.description,
      data.expiresAt,
      sha256.convert(pdf.bytes).toString(),
    ]) {
      final encoded = value == null ? null : utf8.encode(value);
      builder.add(
        (ByteData(
          4,
        )..setUint32(0, encoded?.length ?? 0xffffffff)).buffer.asUint8List(),
      );
      if (encoded != null) builder.add(encoded);
    }
    return sha256.convert(builder.takeBytes()).toString();
  }
}

class PendingAttempt {
  const PendingAttempt({
    required this.key,
    required this.digest,
    required this.createdAt,
  });
  final String key;
  final String digest;
  final DateTime createdAt;
}

abstract interface class PendingAttemptStore {
  Future<PendingAttempt?> read(String userId, String institutionId);
  Future<void> save(
    String userId,
    String institutionId,
    PendingAttempt attempt,
  );
  Future<void> clear(String userId, String institutionId);
}

abstract interface class PdfPicker {
  Future<SelectedPdf?> pick();
  void cancel();
}

abstract interface class IssuanceRepository {
  Future<String> issue(IssuanceRequest request);
}

class IssuanceException implements Exception {
  const IssuanceException(this.code, {this.retryAfter = 120});
  final String code;
  final int retryAfter;
  bool get recoverable => [
    'operation_in_progress',
    'temporary_failure',
    'response_lost',
  ].contains(code);
  String get message => switch (code) {
    'unauthenticated' => 'La sesión ha caducado. Vuelve a iniciar sesión.',
    'forbidden' =>
      'Ya no tienes permiso para emitir. Actualiza tus membresías.',
    'invalid_input' => 'Revisa los datos y confirma el ID con el titular. El servidor no pudo aceptar la solicitud.',
    'invalid_pdf' => 'Selecciona un PDF válido .pdf. El servidor comprueba su contenido; algunos formatos PDF no son compatibles con el MVP.',
    'payload_too_large' =>
      'El PDF debe ocupar como máximo 8 MiB (8 388 608 bytes).',
    'idempotency_conflict' => 'La clave corresponde a otra solicitud. Revisa la operación con administración antes de iniciar una emisión nueva.',
    'operation_in_progress' =>
      'La operación sigue en curso. Espera $retryAfter segundos antes de reintentar con los mismos datos.',
    'attempt_failed' => 'El intento está cerrado o pendiente de limpieza. Contacta con administración para conciliarlo antes de iniciar una emisión nueva.',
    'stored_object_invalid' => 'El documento almacenado no pudo validarse. Contacta con administración para revisar la operación.',
    'reconstruction_mismatch' => 'Los datos o el PDF no coinciden con el intento pendiente. Reconstruye exactamente la solicitud original. Una emisión nueva podría duplicar un certificado ya emitido.',
    'receipt_failure' => 'No pudimos guardar el recibo de recuperación. No se ha enviado la emisión; reintenta.',
    'temporary_failure' || 'response_lost' => 'No pudimos confirmar el resultado. Reintenta con la misma clave, datos y PDF; la emisión podría haberse completado.',
    _ => 'No pudimos completar la operación. Revisa el resultado con administración.',
  };
}
