import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:mobile/features/issuance/data/platform_pdf_picker.dart';
import 'package:mobile/features/certificates/data/pdf_saver_web.dart';
import 'package:mobile/features/issuance/domain/issuance_repository.dart';

// Test-only entrypoint. Uses production adapters, served exclusively on loopback.
void check(bool condition) {
  if (!condition) throw StateError('Browser PDF check failed');
}

Future<void> main() async {
  try {
    final future = PlatformPdfPicker().pick();
    final input =
        web.document.querySelector('#certichain-pdf-input')!
            as web.HTMLInputElement;
    check(!input.multiple && input.accept == '.pdf');
    final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 49, 1, 2, 3]);
    final transfer = web.DataTransfer();
    transfer.items.add(
      web.File(
        [bytes.toJS].toJS,
        'selected.pdf',
        web.FilePropertyBag(type: 'application/pdf'),
      ),
    );
    input.files = transfer.files;
    input.dispatchEvent(web.Event('change'));
    final selected = await future;
    check(
      selected?.name == 'selected.pdf' &&
          selected!.bytes.join(',') == bytes.join(','),
    );
    check(web.document.querySelector('#certichain-pdf-input') == null);
    final cancelled = PlatformPdfPicker().pick();
    web.document
        .querySelector('#certichain-pdf-input')!
        .dispatchEvent(web.Event('cancel'));
    check(await cancelled == null);
    check(web.document.querySelector('#certichain-pdf-input') == null);
    for (final size in [maxPdfBytes, maxPdfBytes + 1]) {
      final pending = PlatformPdfPicker().pick();
      final selectedInput =
          web.document.querySelector('#certichain-pdf-input')!
              as web.HTMLInputElement;
      final boundaryBytes = Uint8List(size)..[size - 1] = 7;
      final boundaryTransfer = web.DataTransfer();
      boundaryTransfer.items.add(
        web.File(
          [boundaryBytes.toJS].toJS,
          'boundary.pdf',
          web.FilePropertyBag(type: 'application/pdf'),
        ),
      );
      selectedInput.files = boundaryTransfer.files;
      selectedInput.dispatchEvent(web.Event('change'));
      if (size == maxPdfBytes) {
        final boundary = await pending;
        check(
          boundary!.bytes.length == maxPdfBytes && boundary.bytes.last == 7,
        );
      } else {
        var denied = false;
        try {
          await pending;
        } on IssuanceException catch (error) {
          denied = error.code == 'payload_too_large';
        }
        check(denied);
      }
      check(web.document.querySelector('#certichain-pdf-input') == null);
    }
    String? blobUrl;
    final listener = ((web.Event event) {
      final target = event.target;
      if (target != null && target.isA<web.HTMLAnchorElement>()) {
        final anchor = target as web.HTMLAnchorElement;
        check(anchor.download == 'certificado.pdf');
        blobUrl = anchor.href;
        event.preventDefault();
      }
    }).toJS;
    web.document.addEventListener('click', listener);
    final location = web.window.location.href;
    check(await savePdf(bytes));
    check(
      blobUrl?.startsWith('blob:') == true &&
          web.window.location.href == location,
    );
    final response = await web.window.fetch(blobUrl!.toJS).toDart;
    final buffer = await response.arrayBuffer().toDart;
    check(buffer.toDart.asUint8List().join(',') == bytes.join(','));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    var revoked = false;
    try {
      await web.window.fetch(blobUrl!.toJS).toDart;
    } catch (_) {
      revoked = true;
    }
    check(revoked);
    web.document.removeEventListener('click', listener);
    web.document.body!.textContent = 'PASS Chrome: real PDF picker, cancellation, 8 MiB boundary, exact bytes, blob download, no navigation and URL revocation';
  } catch (error, stack) {
    web.document.body!.textContent = 'FAIL Chrome PDF smoke: $error\n$stack';
  }
}
