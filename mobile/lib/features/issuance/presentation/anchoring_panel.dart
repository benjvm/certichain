import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/app_button.dart';
import '../domain/anchoring_repository.dart';
import 'anchoring_controller.dart';

class AnchoringPanel extends StatefulWidget {
  const AnchoringPanel({
    required this.scope,
    required this.repository,
    required this.store,
    required this.onSessionExpired,
    this.sessionChanges,
    this.canRequest = true,
    super.key,
  });
  final AnchorScope scope;
  final bool canRequest;
  final AnchoringRepository repository;
  final AnchorReceiptStore store;
  final VoidCallback onSessionExpired;
  final Listenable? sessionChanges;
  @override
  State<AnchoringPanel> createState() => _AnchoringPanelState();
}

class _AnchoringPanelState extends State<AnchoringPanel> {
  late AnchoringController _controller;
  bool _confirming = false;
  int _confirmationRevision = 0;
  @override
  void initState() {
    super.initState();
    _create();
    widget.sessionChanges?.addListener(_session);
  }

  void _create() {
    _controller = AnchoringController(
      widget.scope,
      widget.repository,
      widget.store,
    );
    unawaited(_controller.load());
  }

  void _session() {
    _confirmationRevision++;
    _controller.invalidate();
    unawaited(_controller.load());
  }

  @override
  void didUpdateWidget(AnchoringPanel old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope || old.repository != widget.repository) {
      _confirmationRevision++;
      _controller.dispose();
      _create();
    }
    if (old.sessionChanges != widget.sessionChanges) {
      old.sessionChanges?.removeListener(_session);
      widget.sessionChanges?.addListener(_session);
    }
  }

  Future<void> _request() async {
    if (_confirming || !_controller.canAct || !widget.canRequest) return;
    _confirming = true;
    final scope = widget.scope;
    final revision = _confirmationRevision;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitar anclaje'),
        content: const Text(
          'Se anclará el certificado ya publicado. El backend procesa la solicitud mediante un worker externo; puede permanecer pendiente. No se vuelve a emitir ni se envía otro PDF.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar solicitud'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (!mounted ||
        scope != widget.scope ||
        revision != _confirmationRevision ||
        confirmed != true) {
      return;
    }
    await _controller.request();
    _authError();
  }

  void _authError() {
    if (mounted && _controller.error?.code == 'unauthenticated') {
      widget.onSessionExpired();
    }
  }

  @override
  void dispose() {
    widget.sessionChanges?.removeListener(_session);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Anclaje institucional',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        if (_controller.receipt?.operation case final op?) ...[
          SelectableText('Operación: ${op.id}'),
          Text(switch (op.status) {
            AnchorStatus.requested => 'Solicitud pendiente del worker.',
            AnchorStatus.prepared => 'Transacción preparada por el backend.',
            AnchorStatus.submitted =>
              'Transacción enviada; inclusión pendiente.',
            AnchorStatus.included => 'Incluida; confirmación pendiente.',
            AnchorStatus.confirmed => 'Confirmación persistida. Consulta la evidencia pública para contrastarla.',
            AnchorStatus.reorged =>
              'Reorganización detectada; evidencia anterior invalidada.',
            AnchorStatus.blocked =>
              'Anclaje bloqueado. Requiere reautorización o revisión.',
            AnchorStatus.failed =>
              'Anclaje fallido. Requiere reautorización explícita.',
            AnchorStatus.divergence =>
              'Discrepancia; requiere revisión del operador.',
          }),
          AppButton(
            label: 'Actualizar estado',
            isLoading: _controller.busy,
            onPressed: _controller.canAct
                ? () async {
                    await _controller.progress();
                    _authError();
                  }
                : null,
            style: AppButtonStyle.outline,
          ),
          if (op.canReauthorize)
            TextButton(
              onPressed: _controller.canAct
                  ? () async {
                      await _controller.reauthorize();
                      _authError();
                    }
                  : null,
              child: const Text('Reautorizar anclaje'),
            ),
        ] else
          AppButton(
            label: _controller.receipt == null
                ? 'Solicitar anclaje'
                : 'Recuperar misma solicitud',
            isLoading: _controller.busy,
            onPressed: _controller.canAct && widget.canRequest
                ? _request
                : null,
            style: AppButtonStyle.outline,
          ),
        if (!_controller.ready && _controller.error == null)
          const Text('Cargando recibo de esta cuenta e institución…'),
        if (_controller.error case final error?)
          Semantics(
            liveRegion: true,
            child: Text(switch (error.code) {
              'unauthenticated' => 'Tu sesión ha caducado.',
              'stale_session' =>
                'La sesión ha cambiado. Actualiza antes de continuar.',
              'authorization_denied' =>
                'No tienes autorización actual en la emisora.',
              'publication_unavailable' =>
                'No hay una publicación elegible para anclar.',
              'idempotency_conflict' =>
                'La clave corresponde a otra solicitud. Requiere revisión.',
              'busy' =>
                'La operación está ocupada. Actualiza manualmente más tarde.',
              'rate_limited' => 'Espera antes de volver a consultar.',
              'receipt_failure' => 'No se pudo conservar el recibo; la solicitud no se enviará sin él.',
              'network' || 'timeout' =>
                'Respuesta no recibida. Recupera la misma solicitud y clave.',
              'temporary_failure' => 'Servicio no disponible. Recupera la misma solicitud más tarde.',
              _ => 'No se pudo completar la solicitud.',
            }),
          ),
        if (!_controller.ready && _controller.error != null)
          TextButton(
            onPressed: _controller.load,
            child: const Text('Releer recibo'),
          ),
        const Text(
          'Actualizar es una acción manual. Sin worker activo, la solicitud permanece pendiente.',
        ),
        if (!widget.canRequest)
          const Text(
            'No se puede solicitar un anclaje nuevo en este estado. Las operaciones existentes siguen consultables.',
          ),
      ],
    ),
  );
}
