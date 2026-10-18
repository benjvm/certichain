import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../domain/revocation_reason.dart';
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
    this.certificateTitle,
    super.key,
  });
  final RevocationScope scope;
  final RevocationRepository repository;
  final RevocationKeyStore keys;
  final VoidCallback onSessionExpired;
  final Listenable? sessionChanges;
  final VoidCallback? onRevoked;
  final String? certificateTitle;
  @override
  State<RevocationPanel> createState() => _RevocationPanelState();
}

class _RevocationPanelState extends State<RevocationPanel> {
  late RevocationController controller;
  final reason = TextEditingController();
  bool confirming = false;
  String? inputError;
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
    inputError = null;
    controller.invalidate();
  }

  @override
  void didUpdateWidget(RevocationPanel old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope || old.repository != widget.repository) {
      generation++;
      reason.clear();
      inputError = null;
      controller.dispose();
      _create();
    }
    if (old.sessionChanges != widget.sessionChanges) {
      old.sessionChanges?.removeListener(_session);
      widget.sessionChanges?.addListener(_session);
    }
  }

  Future<void> _request() async {
    if (controller.busy || confirming || controller.accessDenied) return;
    final validation = revocationReasonError(reason.text);
    if (validation != null) {
      setState(() => inputError = validation);
      return;
    }
    final submittedReason = normalizeRevocationReason(reason.text);
    final revision = generation;
    confirming = true;
    final accepted = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Revocación irreversible'),
        scrollable: true,
        content: Text(
          '${widget.certificateTitle ?? 'Certificado'}\n${widget.scope.certificateId}\n\nSe revoca inmediatamente en CertiChain. La decisión es irreversible. Blockchain puede tardar o quedar bloqueada. El PDF y las copias exportadas se conservan. El motivo es privado para owner/admin actuales de la emisora verificada o suspendida.',
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
    await controller.request(submittedReason);
    if (!mounted || revision != generation) return;
    if (controller.decision?.revoked == true) {
      reason.clear();
      widget.onRevoked?.call();
    }
    _auth();
  }

  Future<void> _reauthorize(String operationId) async {
    if (controller.busy || confirming || controller.accessDenied) return;
    final revision = generation;
    confirming = true;
    final accepted = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Reautorizar sincronización'),
        scrollable: true,
        content: const Text(
          'Autoriza al backend a continuar la sincronización blockchain tras revisar el bloqueo. No revoca de nuevo ni cambia la decisión original. El backend debe reconciliar los intentos anteriores y comprobar los permisos actuales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar reautorización'),
          ),
        ],
      ),
    );
    confirming = false;
    if (!mounted || revision != generation || accepted != true) return;
    await controller.reauthorize(operationId);
    if (!mounted || revision != generation) return;
    _auth();
  }

  void _auth() {
    if (controller.accessDenied) reason.clear();
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
        Text(
          widget.certificateTitle ??
              'Certificado ${widget.scope.certificateId}',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (controller.decision case final d?) ...[
          if (d.revoked) ...[
            const Text('Revocado en CertiChain'),
            Text(
              'Fecha de revocación SQL (UTC): ${d.revokedAt!.toUtc().toIso8601String()}',
            ),
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
                      : () => _reauthorize(sync.operationId),
                  child: const Text('Reautorizar explícitamente'),
                ),
            ],
          ] else
            const Text('El certificado sigue activo en CertiChain.'),
        ],
        if (!controller.accessDenied &&
            controller.decision?.revoked != true) ...[
          TextField(
            controller: reason,
            enabled: !controller.busy && !controller.frozen,
            maxLines: 3,
            onChanged: (_) => setState(() => inputError = null),
            decoration: InputDecoration(
              labelText: 'Motivo privado obligatorio',
              errorText: inputError,
              errorMaxLines: 4,
              counterText:
                  '${normalizeRevocationReason(reason.text).runes.length}/500 puntos Unicode',
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
        if (!controller.accessDenied)
          TextButton(
            onPressed: controller.busy
                ? null
                : () async {
                    final revision = generation;
                    await controller.refresh();
                    if (!mounted || revision != generation) return;
                    if (controller.decision?.revoked == true) {
                      reason.clear();
                      widget.onRevoked?.call();
                    }
                    _auth();
                  },
            child: const Text('Consultar revocación / recuperar respuesta'),
          ),
        if (controller.busy)
          const Text('Enviando; espera antes de reintentar.'),
        if (controller.error != null)
          Semantics(
            liveRegion: true,
            child: Text(switch (controller.error) {
              'unauthenticated' || 'stale_session' =>
                'La sesión ha cambiado. Inicia sesión de nuevo para continuar.',
              'authorization_denied' || 'revocation_unavailable' => 'La revocación no está disponible o ya no tienes permiso. Se han retirado los datos privados y las acciones.',
              'invalid_input' => 'Revisa el motivo privado: debe contener entre 1 y 500 puntos Unicode y texto admitido.',
              'idempotency_conflict' => 'Esta clave corresponde a otro contenido. Consulta el progreso para recuperar la decisión original; no se ha sobrescrito.',
              'busy' => 'El backend está reconciliando la operación o aún no permite reautorizar. Consulta el progreso y revisa el bloqueo antes de volver a intentarlo.',
              'rate_limited' =>
                'Hay demasiadas consultas. Espera antes de consultar de nuevo.',
              'receipt_failure' => 'No se puede recuperar la clave local. Consulta el progreso para comprobar si la decisión ya existe antes de continuar.',
              _ =>
                controller.uncertain
                    ? 'La respuesta se ha perdido o no es comprobable. La revocación puede haberse aplicado. Consulta el progreso o reintenta la misma solicitud con su clave original.'
                    : 'No se pudo comprobar el progreso. Reintenta la consulta; el estado SQL anterior no cambia.',
            }),
          ),
      ],
    ),
  );
}
