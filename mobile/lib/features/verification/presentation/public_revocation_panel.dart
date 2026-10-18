import 'package:flutter/material.dart';

import '../domain/public_revocation.dart';

class PublicRevocationPanel extends StatelessWidget {
  const PublicRevocationPanel({
    required this.revocation,
    this.previous = false,
    super.key,
  });
  final PublicRevocation revocation;
  final bool previous;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Evidencia de revocación',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      if (previous)
        const Text(
          'Evidencia anterior de revocación; no comprobada actualmente. Se conserva la fecha de observación.',
        ),
      if (revocation.revokedAt != null)
        Text(
          'Revocado en CertiChain: ${revocation.revokedAt!.toUtc().toIso8601String()}',
        ),
      Text(switch (revocation.state) {
        PublicRevocationState.notRequested => 'Sin revocación SQL.',
        PublicRevocationState.notApplicable =>
          'Revocación blockchain: no aplicable.',
        PublicRevocationState.pending => 'Revocación blockchain pendiente de sincronización. El registro SQL ya está revocado.',
        PublicRevocationState.blocked =>
          'Revocación blockchain bloqueada. El registro SQL sigue revocado.',
        PublicRevocationState.included =>
          'Revocación EVM incluida; confirmación pendiente.',
        PublicRevocationState.confirmed => 'Revocación EVM confirmada.',
        PublicRevocationState.reorged =>
          'Reorganización de revocación; SQL sigue revocado.',
        PublicRevocationState.unavailable =>
          'Revocación EVM no comprobable actualmente; SQL sigue revocado.',
        PublicRevocationState.divergence => 'Evidencia de revocación incompatible. Requiere revisión; SQL sigue revocado.',
      }),
      Text(
        'Comprobación de revocación (UTC): ${revocation.checkedAt.toUtc().toIso8601String()} · ${switch (revocation.source) {
          'backend_rpc' => 'observación del backend RPC',
          'certichain_registry' => 'registro CertiChain',
          _ => 'comprobación actual no disponible',
        }}',
      ),
      if (revocation.evidence case final e?) ...[
        Text('Revocado en EVM: ${e.revokedAt!.toUtc().toIso8601String()}'),
        const Text('Transacción de revocación'),
        SelectableText(e.hash),
        Text(
          'Bloque ${e.blockNumber} · Confirmaciones ${e.confirmations} · ${switch (e.finality) {
            'not_applicable' => 'Finalidad no aplicable: red local Anvil.',
            'finalized' => 'Bloque finalizado según el RPC.',
            _ => 'Finalidad desconocida.',
          }}',
        ),
      ],
      if (revocation.previous case final p?)
        Text(
          'Evidencia anterior de revocación, no comprobada actualmente: ${p.checkedAt.toUtc().toIso8601String()} · ${p.hash}',
        ),
      if (revocation.revokedAt != null)
        const Text(
          'Un PDF coincidente conserva integridad documental; el certificado está revocado.',
        ),
    ],
  );
}
