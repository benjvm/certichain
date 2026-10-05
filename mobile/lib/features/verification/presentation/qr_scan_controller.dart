import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/qr_camera.dart';
import '../domain/verification_link.dart';

enum QrScanPhase { preparing, reading, found, paused, error }

class QrScanController extends ChangeNotifier {
  QrScanController(this.camera, this.link) {
    _subscription = camera.detections.listen(
      _detect,
      onError: (Object _) {
        if (_disposed || phase != QrScanPhase.reading) return;
        failure = QrCameraFailure.failed;
        phase = QrScanPhase.error;
        unawaited(pause());
        notifyListeners();
      },
    );
  }
  final QrCamera camera;
  final VerificationLink link;
  late final StreamSubscription<String> _subscription;
  QrScanPhase phase = QrScanPhase.preparing;
  QrCameraFailure? failure;
  String? code;
  bool unknown = false, _disposed = false, _starting = false;
  int _generation = 0;
  Future<void>? _startFuture;
  Future<void> start() async {
    if (_disposed ||
        _starting ||
        phase == QrScanPhase.reading ||
        code != null) {
      return;
    }
    _starting = true;
    final generation = ++_generation;
    phase = QrScanPhase.preparing;
    failure = null;
    unknown = false;
    notifyListeners();
    try {
      _startFuture = camera.start();
      await _startFuture;
      if (_disposed || generation != _generation) {
        await camera.stop();
        return;
      }
      phase = QrScanPhase.reading;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      failure = error is QrCameraException
          ? error.failure
          : QrCameraFailure.failed;
      phase = QrScanPhase.error;
    } finally {
      _starting = false;
      if (!_disposed && generation == _generation) notifyListeners();
    }
  }

  void _detect(String value) {
    if (_disposed || phase != QrScanPhase.reading || code != null) return;
    final parsed = link.codeFromQr(value);
    if (parsed == null) {
      if (!unknown) {
        unknown = true;
        notifyListeners();
      }
      return;
    }
    code = parsed;
    unknown = false;
    phase = QrScanPhase.found;
    _generation++;
    unawaited(
      camera.stop().catchError((Object _) {
        // Detection is already latched; disposal still releases the session.
      }),
    );
    notifyListeners();
  }

  Future<void> pause() async {
    _generation++;
    if (_disposed) return;
    if (code == null && phase != QrScanPhase.error) phase = QrScanPhase.paused;
    notifyListeners();
    // Permission/start can resolve after pause. Stop again after that result.
    try {
      await camera.stop();
    } catch (_) {
      /* start() handles camera failures */
    }
    try {
      await _startFuture;
    } catch (_) {
      /* already mapped by start */
    }
    if (!_disposed) {
      try {
        await camera.stop();
      } catch (_) {}
    }
  }

  Future<void> _release() async {
    await _subscription.cancel();
    try {
      await _startFuture;
    } catch (_) {}
    try {
      await camera.stop();
    } catch (_) {}
    try {
      await camera.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    code = null;
    unawaited(_release());
    super.dispose();
  }
}
