import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/qr_camera.dart';
import '../domain/verification_link.dart';
import 'qr_scan_controller.dart';

class ScannerSession {
  const ScannerSession(this.camera, this.preview);
  final QrCamera camera;
  final Widget preview;
}

class QrScannerPanel extends StatefulWidget {
  const QrScannerPanel({
    required this.link,
    required this.createSession,
    required this.onCode,
    required this.onClose,
    super.key,
  });
  final VerificationLink link;
  final ScannerSession Function() createSession;
  final ValueChanged<String> onCode;
  final VoidCallback onClose;
  @override
  State<QrScannerPanel> createState() => _QrScannerPanelState();
}

class _QrScannerPanelState extends State<QrScannerPanel>
    with WidgetsBindingObserver {
  late final ScannerSession _session;
  late final QrScanController _controller;
  bool _confirmed = false;
  @override
  void initState() {
    super.initState();
    _session = widget.createSession();
    _controller = QrScanController(_session.camera, widget.link);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.start());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A permission dialog temporarily takes focus without backgrounding the
    // application. Invalidating its pending start hides the denial outcome.
    // hidden/paused still cancel a start that completes after real backgrounding.
    if (state == AppLifecycleState.inactive &&
        _controller.phase == QrScanPhase.preparing) {
      return;
    }
    if (state != AppLifecycleState.resumed) unawaited(_controller.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Los fotogramas se procesan en este dispositivo y no se guardan.',
            ),
            if (_controller.code == null)
              SizedBox(height: 240, child: _session.preview),
            Semantics(
              liveRegion: true,
              child: Text(switch (_controller.phase) {
                QrScanPhase.preparing =>
                  'Preparando cámara y solicitando permiso…',
                QrScanPhase.reading =>
                  'Leyendo QR. Acerca el código a la cámara.',
                QrScanPhase.found => 'Código identificado',
                QrScanPhase.paused =>
                  'Cámara detenida. Actívala de nuevo para continuar.',
                QrScanPhase.error => switch (_controller.failure) {
                  QrCameraFailure.permissionDenied => 'Permiso de cámara denegado. Puedes introducir el código manualmente.',
                  QrCameraFailure.unavailable =>
                    'No hay una cámara disponible o compatible.',
                  QrCameraFailure.busy => 'No pudimos usar la cámara. Puede estar ocupada por otra aplicación.',
                  _ => 'No pudimos iniciar la cámara. Puedes introducir el código manualmente.',
                },
              }),
            ),
            if (_controller.unknown)
              const Text(
                'QR desconocido. Usa un enlace de CertiChain o un código UUID.',
              ),
            if (_controller.code case final code?) ...[
              SelectableText(code),
              FilledButton(
                onPressed: _confirmed
                    ? null
                    : () {
                        if (_confirmed) return;
                        _confirmed = true;
                        widget.onCode(code);
                      },
                child: const Text('Verificar código identificado'),
              ),
            ],
            if (_controller.phase == QrScanPhase.paused ||
                _controller.phase == QrScanPhase.error)
              TextButton(
                onPressed: _controller.start,
                child: const Text('Activar cámara'),
              ),
            TextButton(
              onPressed: widget.onClose,
              child: const Text('Cancelar escáner · Introducir código'),
            ),
          ],
        ),
      ),
    ),
  );
}
