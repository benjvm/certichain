import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class OpeningFile {
  void Function()? _cancel;
  void cancel() => _cancel?.call();
  Future<String?> pick() async {
    cancel();
    final result = Completer<String?>();
    final input = web.HTMLInputElement()
      ..id = 'certichain-opening-input'
      ..type = 'file'
      ..accept = '.json,application/json'
      ..multiple = false
      ..style.display = 'none';
    final change = ((web.Event _) {
      unawaited(() async {
        try {
          final files = input.files;
          if (files == null || files.length == 0) {
            if (!result.isCompleted) result.complete(null);
            return;
          }
          if (files.length != 1) throw const FormatException();
          final file = files.item(0)!;
          if (file.size <= 0 || file.size > 2048) throw const FormatException();
          final bytes =
              (await file
                      .slice(0, 2049)
                      .arrayBuffer()
                      .toDart
                      .timeout(const Duration(seconds: 15)))
                  .toDart
                  .asUint8List();
          if (bytes.length > 2048) throw const FormatException();
          if (!result.isCompleted) result.complete(utf8.decode(bytes));
        } catch (e, s) {
          if (!result.isCompleted) result.completeError(e, s);
        }
      }());
    }).toJS;
    void finish() {
      if (!result.isCompleted) result.complete(null);
    }

    final cancelled = ((web.Event _) => finish()).toJS;
    _cancel = finish;
    input.addEventListener('change', change);
    input.addEventListener('cancel', cancelled);
    web.document.body!.append(input);
    try {
      input.click();
      return await result.future;
    } finally {
      if (identical(_cancel, finish)) _cancel = null;
      input.removeEventListener('change', change);
      input.removeEventListener('cancel', cancelled);
      input.remove();
    }
  }
}

Future<bool> saveOpening(String json) async {
  final blob = web.Blob(
    [Uint8List.fromList(utf8.encode(json)).toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = 'apertura.json'
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  unawaited(
    Future<void>.delayed(
      const Duration(seconds: 1),
      () => web.URL.revokeObjectURL(url),
    ),
  );
  return true;
}
