import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../domain/issuance_repository.dart';

Future<SelectedPdf?> pickPdf() async {
  final result = Completer<SelectedPdf?>();
  final input = web.HTMLInputElement()
    ..id = 'certichain-pdf-input'
    ..type = 'file'
    ..accept = '.pdf'
    ..multiple = false
    ..style.display = 'none';
  var reading = false;
  final change = ((web.Event _) {
    if (reading) return;
    reading = true;
    unawaited(() async {
      try {
        final files = input.files;
        if (files == null || files.length != 1) {
          throw const IssuanceException('invalid_pdf');
        }
        final file = files.item(0)!;
        if (file.size > maxPdfBytes) {
          throw const IssuanceException('payload_too_large');
        }
        final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
        result.complete(SelectedPdf(name: file.name, bytes: bytes));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    }());
  }).toJS;
  final cancel = ((web.Event _) {
    if (!result.isCompleted && !reading) result.complete(null);
  }).toJS;
  input.addEventListener('change', change);
  input.addEventListener('cancel', cancel);
  web.document.body!.append(input);
  try {
    input.click();
    return await result.future;
  } finally {
    input.removeEventListener('change', change);
    input.removeEventListener('cancel', cancel);
    input.remove();
  }
}
