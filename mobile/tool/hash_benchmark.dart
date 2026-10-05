import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mobile/features/verification/data/sha256_pdf_hasher.dart';

/// Synthetic local benchmark; never records a digest or document contents.
Future<void> main() async {
  final samples = <int>[];
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
  try {
    for (var run = 0; run < 3; run++) {
      final bytes = Uint8List(8 * 1024 * 1024);
      final watch = Stopwatch()..start();
      await Sha256PdfHasher().hash(bytes);
      samples.add(watch.elapsedMilliseconds);
    }
  } finally {
    timer.cancel();
  }
  stdout.writeln(
    jsonEncode({
      'runtime': 'Dart VM',
      'bytes': 8 * 1024 * 1024,
      'hash_ms': samples,
      'event_loop_ticks': ticks,
    }),
  );
}
