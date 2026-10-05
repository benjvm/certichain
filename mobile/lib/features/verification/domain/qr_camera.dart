enum QrCameraFailure { permissionDenied, unavailable, busy, failed }

class QrCameraException implements Exception {
  const QrCameraException(this.failure);
  final QrCameraFailure failure;
}

abstract interface class QrCamera {
  Stream<String> get detections;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}
