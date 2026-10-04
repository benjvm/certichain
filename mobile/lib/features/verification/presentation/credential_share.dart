import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../domain/verification_link.dart';
import '../domain/verification_repository.dart';

/// Inline share panel belongs to the private route; logout destroys it together
/// with that navigator. No detached dialog or persistent private state.
class CredentialShare extends StatefulWidget {
  const CredentialShare({
    required this.repository,
    required this.holderId,
    required this.certificateId,
    required this.link,
    required this.sessionChanges,
    super.key,
  });
  final CredentialRepository repository;
  final String holderId, certificateId;
  final VerificationLink? link;
  final Listenable sessionChanges;
  @override
  State<CredentialShare> createState() => _CredentialShareState();
}

class _CredentialShareState extends State<CredentialShare> {
  Future<String?>? _code;
  bool _visible = false, _copied = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.sessionChanges.addListener(_clear);
  }

  void _clear() {
    if (mounted) {
      setState(() {
        _generation++;
        _visible = false;
        _code = null;
        _copied = false;
      });
    }
  }

  @override
  void didUpdateWidget(CredentialShare oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionChanges != widget.sessionChanges) {
      oldWidget.sessionChanges.removeListener(_clear);
      widget.sessionChanges.addListener(_clear);
    }
    if (oldWidget.holderId != widget.holderId ||
        oldWidget.certificateId != widget.certificateId) {
      _clear();
    }
  }

  void _read() => setState(() {
    _visible = true;
    _copied = false;
    _code = widget.repository.readOwnCode(
      widget.holderId,
      widget.certificateId,
    );
  });
  @override
  void dispose() {
    widget.sessionChanges.removeListener(_clear);
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.link == null) {
      return const Text(
        'Compartir no está disponible: falta una dirección Web pública válida. Puedes consultar un código en Verificar certificado.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Mostrar QR y enlace',
          onPressed: _read,
          style: AppButtonStyle.outline,
        ),
        if (_visible)
          FutureBuilder<String?>(
            future: _code,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('Obteniendo código para compartir…'),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const Text(
                      'No pudimos obtener el código. Reintenta con una sesión vigente.',
                    ),
                    TextButton(
                      onPressed: _read,
                      child: const Text('Reintentar'),
                    ),
                  ],
                );
              }
              final code = snapshot.data;
              if (code == null) {
                return const Text(
                  'Este certificado no dispone de enlace verificable.',
                );
              }
              final url = widget.link!.forCode(code);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Center(child: VerificationQr(url: url)),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Código del certificado'),
                  SelectableText(code),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Enlace de verificación'),
                  SelectableText(url),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Copiar enlace',
                    onPressed: () async {
                      final generation = _generation;
                      try {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (mounted && generation == _generation) {
                          setState(() => _copied = true);
                        }
                      } catch (_) {
                        if (mounted && generation == _generation) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No pudimos copiar. Selecciona el enlace para copiarlo.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  if (_copied)
                    Semantics(liveRegion: true, child: Text('Enlace copiado')),
                  TextButton(
                    onPressed: _clear,
                    child: const Text('Ocultar QR y enlace'),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class VerificationQr extends StatelessWidget {
  const VerificationQr({required this.url, super.key});
  final String url;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'QR del enlace de verificación',
    image: true,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: RepaintBoundary(
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: VerificationQrPainter(url)),
        ),
      ),
    ),
  );
}

/// Generation/error correction belongs to package:qr. Canvas only paints its
/// modules, with a four-module quiet zone and black/white contrast.
class VerificationQrPainter extends CustomPainter {
  VerificationQrPainter(this.url)
    : matrix = QrImage(
        QrCode(
          payload: QrPayload.fromString(url),
          errorCorrectLevel: QrErrorCorrectLevel.medium,
        ),
      );
  final String url;
  final QrImage matrix;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final unit = size.shortestSide / (matrix.moduleCount + 8);
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var row = 0; row < matrix.moduleCount; row++) {
      for (var col = 0; col < matrix.moduleCount; col++) {
        if (matrix.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH((col + 4) * unit, (row + 4) * unit, unit, unit),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(VerificationQrPainter oldDelegate) =>
      oldDelegate.url != url;
}
