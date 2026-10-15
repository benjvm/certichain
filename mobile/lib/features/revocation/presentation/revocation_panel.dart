import 'package:flutter/material.dart';

import '../domain/revocation_repository.dart';
import 'revocation_controller.dart';

class RevocationPanel extends StatefulWidget {
  const RevocationPanel({
    required this.scope,
    required this.repository,
    required this.keys,
    required this.onSessionExpired,
    this.sessionChanges,
    this.onRevoked,
    super.key,
  });
  final RevocationScope scope;
  final RevocationRepository repository;
  final RevocationKeyStore keys;
  final VoidCallback onSessionExpired;
  final Listenable? sessionChanges;
  final VoidCallback? onRevoked;
  @override
  State<RevocationPanel> createState() => _RevocationPanelState();
}

class _RevocationPanelState extends State<RevocationPanel> {
  late RevocationController controller;
  final reason = TextEditingController();
  bool confirming = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _create();
    widget.sessionChanges?.addListener(_session);
  }

  void _create() {
    controller = RevocationController(
      widget.scope,
      widget.repository,
      widget.keys,
    );
  }

  void _session() {
    generation++;
    reason.clear();
    controller.invalidate();
  }

  @override
  void didUpdateWidget(RevocationPanel old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope || old.repository != widget.repository) {
      generation++;
      reason.clear();
      controller.dispose();
      _create();
    }
    if (old.sessionChanges != widget.sessionChanges) {
      old.sessionChanges?.removeListener(_session);
      widget.sessionChanges?.addListener(_session);
    }
  }

  Future<void> _request() async {
    if (controller.busy || confirming || reason.text.trim().isEmpty) return;
    final revision = generation;
    confirming = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revocación irreversible'),
        content: const Text(
          'Se revoca inmediatamente en CertiChain. Blockchain puede tardar o quedar bloqueada. El PDF y las copias exportadas se conservan. El motivo es privado para owner/admin actuales de la emisora verificada o suspendida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar revocación'),
          ),
        ],
      ),
    );
    confirming = false;
    if (!mounted || revision != generation || accepted != true) return;
    await controller.request(reason.text);
    if (mounted && controller.decision?.revoked == true) {
      reason.clear();
      widget.onRevoked?.call();
    }
    _auth();
  }

  void _auth() {
    if (mounted && controller.error == 'unauthenticated') {
      widget.onSessionExpired();
    }
  }

  @override
  void dispose() {
    generation++;
    widget.sessionChanges?.removeListener(_session);
    controller.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Revocación institucional',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        if (controller.decision case final d?) ...[
          if (d.revoked) ...[
            const Text('Revocado en CertiChain'),
            Text('Fecha SQL: ${d.revokedAt!.toUtc().toIso8601String()}'),
            if (d.reason != null)
              Text('Motivo privado: ${d.reason}')
            else
              const Text('Revocación histórica sin motivo registrado.'),
            if (d.synchronization.isEmpty)
              const Text(
                'Blockchain: no aplicable; no hay emisión firmada que revocar.',
              ),
            for (final sync in d.synchronization) ...[
              Text(
                'Sincronización blockchain: ${switch (sync.status) {
                  RevocationSyncStatus.requested => 'pendiente',
                  RevocationSyncStatus.prepared => 'preparada',
                  RevocationSyncStatus.submitted => 'pendiente de inclusión',
                  RevocationSyncStatus.included => 'incluida',
                  RevocationSyncStatus.confirmed => 'confirmada',
                  RevocationSyncStatus.reorged => 'reorganización',
                  RevocationSyncStatus.blocked => 'bloqueada',
                  RevocationSyncStatus.failed => 'fallida',
                  RevocationSyncStatus.divergence => 'discrepancia incompatible',
                }}. Es progreso persistido; actualiza la evidencia pública para comprobar la cadena.',
              ),
              if ([
                RevocationSyncStatus.blocked,
                RevocationSyncStatus.failed,
              ].contains(sync.status))
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () async {
                          await controller.reauthorize(sync.operationId);
                          _auth();
                        },
                  child: const Text('Reautorizar explícitamente'),
                ),
            ],
          ] else
            const Text('El certificado sigue activo en CertiChain.'),
        ],
        if (controller.decision?.revoked != true) ...[
          TextField(
            controller: reason,
            enabled: !controller.busy && !controller.frozen,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo privado obligatorio',
            ),
          ),
          TextButton(
            onPressed: controller.busy ? null : _request,
            child: Text(
              controller.frozen
                  ? 'Reintentar la misma solicitud'
                  : 'Revocar certificado',
            ),
          ),
        ],
        TextButton(
          onPressed: controller.busy
              ? null
              : () async {
                  await controller.refresh();
                  if (mounted && controller.decision?.revoked == true) {
                    widget.onRevoked?.call();
                  }
                  _auth();
                },
          child: const Text('Consultar revocación / recuperar respuesta'),
        ),
        if (controller.busy)
          const Text('Enviando; espera antes de reintentar.'),
        if (controller.error != null)
          Text(
            'No se pudo completar la consulta (${controller.error}). Consulta el estado o reintenta la misma solicitud; no se ha confirmado el resultado.',
          ),
      ],
    ),
  );
}
