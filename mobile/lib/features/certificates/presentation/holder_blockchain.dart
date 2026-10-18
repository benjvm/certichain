import 'package:flutter/material.dart';

import '../../verification/domain/verification_repository.dart';
import '../../verification/presentation/blockchain_evidence_panel.dart';
import '../../verification/presentation/public_query_cooldown.dart';
import '../../verification/presentation/public_revocation_panel.dart';

/// Holder reads the allowed public projection. Never anchor-progress.
class HolderBlockchain extends StatefulWidget {
  const HolderBlockchain({
    required this.userId,
    required this.certificateId,
    required this.credentials,
    required this.verification,
    required this.cooldown,
    this.sessionChanges,
    super.key,
  });
  final String userId, certificateId;
  final CredentialRepository credentials;
  final VerificationRepository verification;
  final PublicQueryCooldown cooldown;
  final Listenable? sessionChanges;
  @override
  State<HolderBlockchain> createState() => _HolderBlockchainState();
}

class _HolderBlockchainState extends State<HolderBlockchain> {
  VerificationResult? _result;
  String? _error;
  bool _busy = false, _previous = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.sessionChanges?.addListener(_reset);
    widget.cooldown.addListener(_cooldown);
  }

  void _cooldown() {
    if (mounted) setState(() {});
  }

  void _reset() {
    _generation++;
    if (widget.verification case final CancellablePublicQueries transport) {
      transport.cancelPending();
    }
    if (mounted) {
      setState(() {
        _result = null;
        _error = null;
        _busy = false;
      });
    }
  }

  Future<void> _read() async {
    if (_busy || widget.cooldown.waitSeconds > 0) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _previous = _result != null;
      _error = null;
    });
    try {
      final code = await widget.credentials.readOwnCode(
        widget.userId,
        widget.certificateId,
      );
      if (!mounted || generation != _generation) return;
      if (code == null) {
        setState(() => _error = 'Sin publicación compartible.');
      } else {
        final r = await widget.verification.verify(code);
        if (!mounted || generation != _generation) return;
        setState(() {
          _result = r;
          _previous = false;
        });
      }
    } catch (e) {
      if (e is VerificationException &&
          e.failure == VerificationFailure.rateLimited) {
        widget.cooldown.block(e.retryAfter ?? const Duration(seconds: 60));
      }
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Evidencia no disponible. Reintenta manualmente.',
        );
      }
    }
    if (mounted && generation == _generation) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _generation++;
    if (widget.verification case final CancellablePublicQueries transport) {
      transport.cancelPending();
    }
    widget.sessionChanges?.removeListener(_reset);
    widget.cooldown.removeListener(_cooldown);
    _result = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextButton(
        onPressed: _busy || widget.cooldown.waitSeconds > 0 ? null : _read,
        child: Text(
          _busy ? 'Consultando evidencia…' : 'Consultar evidencia blockchain',
        ),
      ),
      if (widget.cooldown.waitSeconds > 0)
        Text('Espera ${widget.cooldown.waitSeconds} segundos.'),
      if (_error != null) Text(_error!),
      if (_result case final result?) ...[
        Text(
          'Registro CertiChain: ${switch (result.status) {
            VerificationStatus.valid => 'vigente',
            VerificationStatus.revoked => 'revocado',
            VerificationStatus.expired => 'caducado',
            VerificationStatus.issuerUnavailable => 'emisor sin aprobación vigente',
            VerificationStatus.notFound => 'no encontrado',
          }}.',
        ),
        if (result.record case final record?)
          Text(
            '${_previous ? 'Consulta anterior' : 'Comprobado'}: ${record.checkedAt.toUtc().toIso8601String()} · registro CertiChain.',
          ),
      ],
      if (_result?.blockchain case final evidence?)
        BlockchainEvidencePanel(evidence: evidence, previous: _previous),
      if (_result?.revocation case final revocation?) ...[
        if (_previous) const Text('Revocación: consulta anterior.'),
        PublicRevocationPanel(revocation: revocation, previous: _previous),
      ],
      if (_result?.status == VerificationStatus.notFound)
        const Text('No hay registro público elegible.'),
    ],
  );
}
