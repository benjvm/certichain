@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:mobile/features/issuance/data/platform_pdf_picker.dart';
import 'package:mobile/features/certificates/data/pdf_saver_web.dart';

void main() {
  test(
    'Chrome picker selects one real PDF and reads its exact bytes',
    () async {
      final future = PlatformPdfPicker().pick();
      final input =
          web.document.querySelector('#certichain-pdf-input')!
              as web.HTMLInputElement;
      expect(input.multiple, false);
      expect(input.accept, '.pdf');
      final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 49]);
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
      expect(selected!.name, 'selected.pdf');
      expect(selected.bytes, bytes);
    },
  );
  test('Chrome download uses a transient blob, filename and exact bytes; no signed URL in navigation', () async {
    String? url, filename;
    final listener = ((web.Event event) {
      final target = event.target;
      if (target != null && target.isA<web.HTMLAnchorElement>()) {
        final anchor = target as web.HTMLAnchorElement;
        url = anchor.href;
        filename = anchor.download;
        event.preventDefault();
      }
    }).toJS;
    web.document.addEventListener('click', listener);
    try {
      final location = web.window.location.href;
      final bytes = Uint8List.fromList([37, 80, 68, 70, 1, 2, 3]);
      expect(await savePdf(bytes), true);
      expect(url, startsWith('blob:'));
      expect(filename, 'certificado.pdf');
      expect(web.window.location.href, location);
      final response = await web.window.fetch(url!.toJS).toDart;
      final buffer = await response.arrayBuffer().toDart;
      expect(buffer.toDart.asUint8List(), bytes);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      var revoked = false;
      try {
        await web.window.fetch(url!.toJS).toDart;
      } catch (_) {
        revoked = true;
      }
      expect(revoked, true);
    } finally {
      web.document.removeEventListener('click', listener);
    }
  });
}
