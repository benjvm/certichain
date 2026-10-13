import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_button.dart';
import '../../issuance/domain/anchoring_repository.dart';
import '../../verification/domain/blockchain_verification.dart';

class OpeningAction extends StatefulWidget {
  const OpeningAction({
    required this.userId,
    required this.certificateId,
    required this.repository,
    required this.transfer,
    required this.onSessionExpired,
    this.sessionChanges,
    super.key,
  });
  final String userId, certificateId;
  final OpeningRepository repository;
  final OpeningTransfer transfer;
  final VoidCallback onSessionExpired;
  final Listenable? sessionChanges;
  @override
  State<OpeningAction> createState() => _OpeningActionState();
}

class _OpeningActionState extends State<OpeningAction> {
  CertificateOpening? _opening;
  bool _busy = false;
  String? _message;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.sessionChanges?.addListener(_reset);
  }

  void _reset() {
    _generation++;
    widget.repository.cancelOpening(widget.userId, widget.certificateId);
    if (mounted) {
      setState(() {
        _opening = null;
        _busy = false;
        _message = null;
      });
    }
  }

  @override
  void didUpdateWidget(OpeningAction old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId ||
        old.certificateId != widget.certificateId ||
        old.repository != widget.repository) {
      old.repository.cancelOpening(old.userId, old.certificateId);
      _generation++;
      _opening = null;
      _busy = false;
      _message = null;
    }
    if (old.sessionChanges != widget.sessionChanges) {
      old.sessionChanges?.removeListener(_reset);
      widget.sessionChanges?.addListener(_reset);
    }
  }

  Future<void> _obtain() async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _opening = null;
      _message = null;
    });
    try {
      final opening = await widget.repository.obtain(
        widget.userId,
        widget.certificateId,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _opening = opening);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      if (e is AnchoringException && e.code == 'unauthenticated') {
        widget.onSessionExpired();
      }
      setState(
        () => _message =
            e is AnchoringException && e.code == 'opening_unavailable'
            ? 'Apertura no disponible o sin acceso.'
            : 'No pudimos obtener la apertura. Reintenta manualmente.',
      );
    }
    if (mounted && generation == _generation) setState(() => _busy = false);
  }

  Future<void> _share(bool export) async {
    final opening = _opening;
    if (opening == null || _busy) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final done = export
          ? await widget.transfer.export(opening)
          : await Clipboard.setData(
              ClipboardData(text: widget.transfer.serialize(opening)),
            ).then((_) => true);
      if (mounted && generation == _generation) {
        setState(
          () => _message = done
              ? (export ? 'Apertura exportada.' : 'Apertura copiada.')
              : 'Exportación cancelada.',
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message = 'No se pudo copiar o exportar la apertura.');
      }
    }
    if (mounted && generation == _generation) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _generation++;
    widget.sessionChanges?.removeListener(_reset);
    widget.repository.cancelOpening(widget.userId, widget.certificateId);
    _opening = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Apertura privada',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const Text(
        'La apertura revela el hash del documento y un salt privado. Al compartirla, otra persona puede comprobar su PDF contra el compromiso. Copiar o exportar requiere tu acción. Las copias realizadas fuera de la app quedan bajo tu control y no se borran al salir.',
      ),
      AppButton(
        label: 'Obtener apertura',
        isLoading: _busy,
        onPressed: _busy ? null : _obtain,
        style: AppButtonStyle.outline,
      ),
      if (_opening != null) ...[
        const Text('Apertura obtenida. No se incorpora al QR ni al enlace.'),
        TextButton(
          onPressed: _busy ? null : () => _share(false),
          child: const Text('Copiar apertura'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _share(true),
          child: const Text('Exportar apertura JSON'),
        ),
        TextButton(onPressed: _reset, child: const Text('Descartar apertura')),
      ],
      if (_message != null) Semantics(liveRegion: true, child: Text(_message!)),
    ],
  );
}
