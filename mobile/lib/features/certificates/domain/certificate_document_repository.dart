abstract interface class CertificateDocumentRepository {
  Future<bool> isAvailable(String userId, String certificateId);

  /// Obtains fresh authorization and a fresh URL for every download.
  Future<bool> download(String userId, String certificateId);
}

class DocumentException implements Exception {
  const DocumentException(this.code);
  final String code;
  String get message => switch (code) {
    'unauthenticated' => 'La sesión ha caducado. Vuelve a iniciar sesión.',
    'document_unavailable' => 'El PDF no está disponible o no tienes acceso.',
    _ => 'No pudimos descargar el PDF. Reintenta.',
  };
}
