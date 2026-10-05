import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/qr_camera.dart';

class MobileScannerCamera implements QrCamera {
  MobileScannerCamera({MobileScannerController? controller})
    : controller =
          controller ??
          MobileScannerController(
            autoStart: false,
            formats: const [BarcodeFormat.qrCode],
            returnImage: false,
          ) {
    if (kIsWeb) {
      // An explicit reader keeps native support/CDN fallback changes from
      // introducing runtime network dependencies. The pure JS UMD is local.
      MobileScannerPlatform.instance.setWebBarcodeReader(
        WebBarcodeReader.zxingJs,
      );
      MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
        'decoder/zxing-0.23.0.min.js',
      );
    }
    _subscription = this.controller.barcodes.listen(
      (capture) {
        if (_disposed) return;
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && !_detections.isClosed) _detections.add(raw);
        }
      },
      onError: (Object _) {
        if (!_disposed && !_detections.isClosed) {
          _detections.addError(const QrCameraException(QrCameraFailure.failed));
        }
      },
    );
  }
  final MobileScannerController controller;
  final _detections = StreamController<String>.broadcast();
  late final StreamSubscription<BarcodeCapture> _subscription;
  bool _disposed = false;
  @override
  Stream<String> get detections => _detections.stream;
  @override
  Future<void> start() async {
    try {
      await controller.start();
      // The plugin stores platform start failures in its value rather than
      // rethrowing them. Read that error before declaring the camera ready.
      final error = controller.value.error;
      if (error != null) {
        // Web allocates its decoder before getUserMedia. Controller.stop()
        // skips a failed start (isRunning=false), so release the partial reader
        // explicitly before retrying this sole public scanner session.
        if (kIsWeb) await MobileScannerPlatform.instance.stop();
        throw error;
      }
    } on MobileScannerException catch (error) {
      throw QrCameraException(switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          QrCameraFailure.permissionDenied,
        MobileScannerErrorCode.unsupported => QrCameraFailure.unavailable,
        _ => QrCameraFailure.busy,
      });
    } catch (_) {
      throw const QrCameraException(QrCameraFailure.failed);
    }
  }

  @override
  Future<void> stop() async {
    if (!_disposed) await controller.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    try {
      await controller.dispose();
    } finally {
      await _detections.close();
    }
  }
}
