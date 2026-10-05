import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../domain/hash_comparison.dart';

class PlatformComparisonPdfPicker implements ComparisonPdfPicker {
  void Function()? _cancel;
  @override
  void cancel() => _cancel?.call();
  @override
  Future<Uint8List?> pick() async {
    cancel();
    final result = Completer<Uint8List?>();
    final input = web.HTMLInputElement()
      ..id = 'certichain-comparison-pdf-input'
      ..type = 'file'
      ..accept = '.pdf,application/pdf'
      ..multiple = false
      ..style.display = 'none';
    var reading = false;
    void finish(Uint8List? bytes) {
      if (!result.isCompleted) result.complete(bytes);
    }

    final cancelSelection = ((web.Event _) {
      if (!reading) finish(null);
    }).toJS;
    final change = ((web.Event _) {
      if (reading || result.isCompleted) return;
      reading = true;
      unawaited(() async {
        try {
          final files = input.files;
          if (files == null || files.length == 0) {
            finish(null);
            return;
          }
          if (files.length != 1) {
            throw const LocalPdfException(LocalPdfFailure.unreadable);
          }
          final file = files.item(0)!;
          validateComparisonBytes(file.size);
          // Check metadata first, then bounded read even if metadata changes.
          final bytes =
              (await file.slice(0, comparisonPdfLimit + 1).arrayBuffer().toDart)
                  .toDart
                  .asUint8List();
          validateComparisonBytes(bytes.length);
          finish(bytes);
        } catch (error, stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        }
      }());
    }).toJS;
    input.addEventListener('change', change);
    input.addEventListener('cancel', cancelSelection);
    web.document.body!.append(input);
    void cancelCurrent() => finish(null);
    _cancel = cancelCurrent;
    try {
      input.click();
      return await result.future;
    } finally {
      if (identical(_cancel, cancelCurrent)) _cancel = null;
      input.removeEventListener('change', change);
      input.removeEventListener('cancel', cancelSelection);
      input.remove();
    }
  }
}
