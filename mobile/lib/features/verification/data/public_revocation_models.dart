import '../../../core/files/strict_json.dart';
import '../domain/verification_repository.dart';
import '../domain/public_revocation.dart';
import 'http_verification_repository.dart';
import 'blockchain_models.dart';

VerificationResult decodeV3(Object? input, String code) {
  final v = closedObject(input, {
    'schema_version',
    'registry',
    'blockchain',
    'revocation',
  });
  if (v['schema_version'] != '3') throw const FormatException('Version');
  final r = decodeV2({
    'schema_version': '2',
    'registry': v['registry'],
    'blockchain': v['blockchain'],
  }, code);
  if (r.status == VerificationStatus.notFound) {
    if (v['revocation'] != null) throw const FormatException('Privacy');
    return r;
  }
  final q = closedObject(v['revocation'], {
    'state',
    'revoked_at',
    'checked_at',
    'source',
    'evidence',
    'last_evidence',
  });
  final state = switch (q['state']) {
    'not_requested' => PublicRevocationState.notRequested,
    'not_applicable' => PublicRevocationState.notApplicable,
    'pending' => PublicRevocationState.pending,
    'blocked' => PublicRevocationState.blocked,
    'included' => PublicRevocationState.included,
    'confirmed' => PublicRevocationState.confirmed,
    'reorged' => PublicRevocationState.reorged,
    'unavailable' => PublicRevocationState.unavailable,
    'divergence' => PublicRevocationState.divergence,
    _ => throw const FormatException('Revocation state'),
  };
  if (![
        'backend_rpc',
        'certichain_registry',
        'unavailable',
      ].contains(q['source']) ||
      ((r.status == VerificationStatus.revoked) != (q['revoked_at'] != null)) ||
      ((state == PublicRevocationState.notRequested) !=
          (q['revoked_at'] == null)) ||
      ([
            PublicRevocationState.included,
            PublicRevocationState.confirmed,
          ].contains(state) !=
          (q['evidence'] != null))) {
    throw const FormatException('Revocation combination');
  }
  final checked = HttpVerificationRepository.decodeDate(q['checked_at']);
  PublicRevocationReceipt receipt(Object? value, {bool previous = false}) {
    final x = closedObject(value, {
      'transaction_hash',
      'block_number',
      'block_hash',
      'checked_at',
      if (!previous) ...{'revoked_at', 'confirmations', 'finality'},
    });
    if (!bytesHex(x['transaction_hash'], 32) ||
        !bytesHex(x['block_hash'], 32) ||
        !decimalString(x['block_number']) ||
        (!previous &&
            (!decimalString(x['confirmations']) ||
                ![
                  'unknown',
                  'not_applicable',
                  'finalized',
                ].contains(x['finality'])))) {
      throw const FormatException('Revocation receipt');
    }
    final date = HttpVerificationRepository.decodeDate(x['checked_at']);
    if (date.isAfter(checked)) throw const FormatException('Revocation date');
    if (!previous) {
      final n = BigInt.parse(x['confirmations']! as String),
          required = r.blockchain?.chainId == '11155111'
              ? BigInt.from(12)
              : BigInt.one;
      if (n < BigInt.one ||
          (state == PublicRevocationState.confirmed && n < required) ||
          (state == PublicRevocationState.included && n >= required) ||
          (x['finality'] == 'not_applicable' &&
              r.blockchain?.chainId != '31337') ||
          (x['finality'] == 'finalized' &&
              (r.blockchain?.chainId != '11155111' ||
                  state != PublicRevocationState.confirmed))) {
        throw const FormatException('Confirmation policy');
      }
    }
    return PublicRevocationReceipt(
      hash: x['transaction_hash']! as String,
      blockNumber: x['block_number']! as String,
      blockHash: x['block_hash']! as String,
      checkedAt: date,
      revokedAt: previous
          ? null
          : HttpVerificationRepository.decodeDate(x['revoked_at']),
      confirmations: x['confirmations'] as String?,
      finality: x['finality'] as String?,
    );
  }

  return VerificationResult(
    r.status,
    record: r.record,
    blockchain: r.blockchain,
    revocation: PublicRevocation(
      state: state,
      revokedAt: q['revoked_at'] == null
          ? null
          : HttpVerificationRepository.decodeDate(q['revoked_at']),
      checkedAt: checked,
      source: q['source']! as String,
      evidence: q['evidence'] == null ? null : receipt(q['evidence']),
      previous: q['last_evidence'] == null
          ? null
          : receipt(q['last_evidence'], previous: true),
    ),
  );
}
