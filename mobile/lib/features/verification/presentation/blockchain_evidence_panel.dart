import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../domain/blockchain_verification.dart';

class BlockchainEvidencePanel extends StatelessWidget {
  const BlockchainEvidencePanel({
    required this.evidence,
    this.previous = false,
    super.key,
  });
  final BlockchainEvidence evidence;
  final bool previous;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Blockchain',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const Text('Evidencia de emisión'),
          if (previous)
            const Text('Evidencia anterior; pertenece a otra consulta.'),
          Text(switch (evidence.state) {
            BlockchainState.offChainOnly =>
              'Solo registro CertiChain: sin anclaje.',
            BlockchainState.pending => 'Anclaje pendiente.',
            BlockchainState.included =>
              'Transacción incluida; confirmación pendiente.',
            BlockchainState.confirmed => 'Anclaje confirmado.',
            BlockchainState.reorged =>
              'Evidencia invalidada por reorganización.',
            BlockchainState.unavailable =>
              'No se pudo comprobar blockchain actualmente.',
            BlockchainState.divergence => 'Discrepancia entre el registro y la evidencia. Requiere revisión.',
          }),
          Text(switch (evidence.finality) {
            BlockchainFinality.unknown => 'Finalidad desconocida.',
            BlockchainFinality.notApplicable =>
              'Finalidad no aplicable: red local Anvil.',
            BlockchainFinality.finalized => 'Bloque finalizado según el RPC.',
          }),
          Text('Comprobación: ${evidence.checkedAt.toUtc().toIso8601String()}'),
          Text(switch (evidence.source) {
            EvidenceSource.registry => 'Origen: registro CertiChain.',
            EvidenceSource.backendRpc => 'Origen: observación del backend RPC.',
            EvidenceSource.persistedReceipt =>
              'Origen: receipt persistido; observación anterior.',
            EvidenceSource.unavailable =>
              'Origen: comprobación actual no disponible.',
          }),
          if (evidence.chainId != null) Text('Red: ${evidence.chainId}'),
          if (evidence.registeredAt != null)
            Text(
              'Registrado en EVM: ${evidence.registeredAt!.toUtc().toIso8601String()}',
            ),
          if (evidence.confirmations != null)
            Text('Confirmaciones: ${evidence.confirmations}'),
          if (evidence.revoked != null)
            Text(
              evidence.revoked!
                  ? 'Estado EVM: revocado.'
                  : 'Estado EVM: no revocado.',
            ),
          if (evidence.contractAddress != null) ...[
            const Text('Contrato'),
            SelectableText(evidence.contractAddress!),
          ],
          if (evidence.transactionHash != null) ...[
            const Text('Transacción'),
            SelectableText(evidence.transactionHash!),
          ],
          if (evidence.blockNumber != null)
            Text('Bloque: ${evidence.blockNumber}'),
          if (evidence.certificateKey != null)
            ExpansionTile(
              title: const Text('Identificadores de evidencia'),
              children: [
                const Text('Clave del certificado'),
                SelectableText(evidence.certificateKey!),
                const Text('Emisor opaco'),
                SelectableText(evidence.issuerId!),
                const Text('Compromiso documental'),
                SelectableText(evidence.commitment!),
              ],
            ),
          if (evidence.explorer case final link?) ...[
            const Text('Contraste adicional en explorador'),
            SelectableText(link.toString()),
          ],
          if (evidence.chainId == '31337')
            const Text('Anvil no tiene explorador público.'),
          if (evidence.previous case final prior?)
            BlockchainEvidencePanel(evidence: prior, previous: true),
        ],
      ),
    ),
  );
}
