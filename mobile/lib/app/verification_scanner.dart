import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../features/verification/data/mobile_scanner_camera.dart';
import '../features/verification/presentation/qr_scanner_panel.dart';

ScannerSession createScannerSession() {
  final camera = MobileScannerCamera();
  return ScannerSession(
    camera,
    MobileScanner(
      controller: camera.controller,
      // Errors are mapped by start(); never show infrastructure exception text.
      errorBuilder: (_, _) => const SizedBox.shrink(),
    ),
  );
}
