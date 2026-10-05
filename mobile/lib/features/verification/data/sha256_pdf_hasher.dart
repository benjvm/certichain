import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/hash_comparison.dart';

class Sha256PdfHasher implements PdfHasher {
  @override
  Future<String> hash(Uint8List bytes, {bool Function()? isCancelled}) async {
    validateComparisonBytes(bytes.length);
    final output = _DigestSink();
    final sink = sha256.startChunkedConversion(output);
    // Bounded work per event turn also on Web, where compute has no isolate.
    for (var start = 0; start < bytes.length; start += 65536) {
      if (isCancelled?.call() ?? false) throw const PdfHashCancelled();
      final end = start + 65536 < bytes.length ? start + 65536 : bytes.length;
      sink.add(Uint8List.sublistView(bytes, start, end));
      await Future<void>.delayed(Duration.zero);
    }
    if (isCancelled?.call() ?? false) throw const PdfHashCancelled();
    sink.close();
    return output.value!.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
