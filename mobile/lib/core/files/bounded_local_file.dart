import 'dart:typed_data';

class LocalFileReadException implements Exception {
  const LocalFileReadException(this.tooLarge);
  final bool tooLarge;
}

Future<Uint8List> readBoundedLocalFile(
  Stream<Uint8List> stream,
  int limit, {
  bool Function()? cancelled,
}) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (cancelled?.call() ?? false) return Uint8List(0);
    if (bytes.length + chunk.length > limit) {
      throw const LocalFileReadException(true);
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}
