import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile/features/issuance/data/platform_pdf_picker.dart';
import 'package:mobile/features/certificates/data/pdf_saver_native.dart';

// Local adapter probe only. This entrypoint is never imported by the product.
// The runner pushes this synthetic byte vector and checks the saved file itself.
final expected = Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52, 10, 7]);
void main() => runApp(const MaterialApp(home: NativeProbe()));

class NativeProbe extends StatefulWidget {
  const NativeProbe({super.key});
  @override
  State<NativeProbe> createState() => _NativeProbeState();
}

class _NativeProbeState extends State<NativeProbe> {
  String status = 'Cancel PDF selection';
  bool cancelled = false, busy = false;
  Future<void> probe() async {
    setState(() => busy = true);
    try {
      final selected = await PlatformPdfPicker().pick();
      if (!cancelled) {
        if (selected != null) throw StateError('Expected cancellation');
        setState(() {
          cancelled = true;
          status = 'Select synthetic PDF';
        });
      } else {
        if (selected == null ||
            selected.bytes.join(',') != expected.join(',')) {
          throw StateError('Unexpected selected bytes');
        }
        if (!await savePdf(Uint8List.fromList(selected.bytes))) {
          throw StateError('Saving cancelled');
        }
        setState(() => status = 'PASS native PDF dialogs');
      }
    } catch (_) {
      setState(() => status = 'FAIL native PDF dialogs');
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ElevatedButton(
          onPressed:
              busy || status.startsWith('PASS') || status.startsWith('FAIL')
              ? null
              : probe,
          child: Text(status),
        ),
      ),
    ),
  );
}
