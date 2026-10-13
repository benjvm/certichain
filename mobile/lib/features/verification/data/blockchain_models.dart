import 'dart:convert';

import '../../../core/files/strict_json.dart';
import '../domain/blockchain_verification.dart';
import '../domain/verification_repository.dart';
import 'http_verification_repository.dart';

bool bytesHex(Object? value, int size) =>
    value is String &&
    value.length == 2 + size * 2 &&
    RegExp(r'^0x[0-9a-f]+$').hasMatch(value);
bool decimalString(Object? value) =>
    value is String &&
    value.length <= 20 &&
    RegExp(r'^(0|[1-9]\d*)$').hasMatch(value);
const evidenceKeys = {'state', 'finality', 'checked_at', 'source'};
const observationKeys = {
  'chain_id',
  'contract_address',
  'protocol_version',
  'certificate_key',
  'issuer_id',
  'commitment',
  'revoked',
  'transaction_hash',
  'block_number',
  'block_hash',
  'confirmations',
};
BlockchainEvidence decodeEvidence(
  Object? value,
  String code, {
  bool previous = false,
}) {
  if (value is! Map<String, Object?>) throw const FormatException('Evidence');
  final full = value.containsKey('commitment');
  closedObject(value, {
    ...evidenceKeys,
    if (full) ...observationKeys,
    if (value.containsKey('registered_at')) 'registered_at',
    if (!previous && value.containsKey('last_evidence')) 'last_evidence',
  });
  final state = switch (value['state']) {
    'off_chain_only' => BlockchainState.offChainOnly,
    'pending' => BlockchainState.pending,
    'included' => BlockchainState.included,
    'confirmed' => BlockchainState.confirmed,
    'reorged' => BlockchainState.reorged,
    'unavailable' => BlockchainState.unavailable,
    'divergence' => BlockchainState.divergence,
    _ => throw const FormatException('State'),
  };
  final finality = switch (value['finality']) {
    'unknown' => BlockchainFinality.unknown,
    'not_applicable' => BlockchainFinality.notApplicable,
    'finalized' => BlockchainFinality.finalized,
    _ => throw const FormatException('Finality'),
  };
  final source = switch (value['source']) {
    'certichain_registry' => EvidenceSource.registry,
    'backend_rpc' => EvidenceSource.backendRpc,
    'persisted_receipt' => EvidenceSource.persistedReceipt,
    'unavailable' => EvidenceSource.unavailable,
    _ => throw const FormatException('Source'),
  };
  if (previous != (source == EvidenceSource.persistedReceipt) ||
      (previous &&
          (!full ||
              ![
                BlockchainState.included,
                BlockchainState.confirmed,
                BlockchainState.reorged,
              ].contains(state) ||
              value.containsKey('registered_at'))) ||
      (!previous &&
          [
            BlockchainState.included,
            BlockchainState.confirmed,
          ].contains(state) &&
          source != EvidenceSource.backendRpc) ||
      (!previous &&
          full &&
          (source != EvidenceSource.backendRpc ||
              !value.containsKey('registered_at') ||
              ![
                BlockchainState.included,
                BlockchainState.confirmed,
                BlockchainState.divergence,
              ].contains(state))) ||
      (state == BlockchainState.offChainOnly &&
          value.containsKey('last_evidence')) ||
      (state == BlockchainState.offChainOnly &&
          (full || source != EvidenceSource.registry)) ||
      (source == EvidenceSource.registry &&
          state != BlockchainState.offChainOnly) ||
      ([BlockchainState.included, BlockchainState.confirmed].contains(state) &&
          !full) ||
      (!full && finality != BlockchainFinality.unknown) ||
      (value.containsKey('registered_at') && !full)) {
    throw const FormatException('Evidence combination');
  }
  if (full) {
    if (!['31337', '11155111'].contains(value['chain_id']) ||
        !bytesHex(value['contract_address'], 20) ||
        value['protocol_version'] is! int ||
        value['protocol_version'] != 1 ||
        [
          'certificate_key',
          'issuer_id',
          'commitment',
          'transaction_hash',
          'block_hash',
        ].any((k) => !bytesHex(value[k], 32)) ||
        value['certificate_key'] != certificateKey(code) ||
        value['revoked'] is! bool ||
        !decimalString(value['block_number']) ||
        !decimalString(value['confirmations']) ||
        (finality == BlockchainFinality.notApplicable &&
            value['chain_id'] != '31337') ||
        (finality == BlockchainFinality.finalized &&
            (value['chain_id'] != '11155111' ||
                state != BlockchainState.confirmed))) {
      throw const FormatException('Observation');
    }
    if (!previous) {
      final confirmations = BigInt.parse(value['confirmations']! as String);
      final required = value['chain_id'] == '31337'
          ? BigInt.one
          : BigInt.from(12);
      if (confirmations < BigInt.one ||
          (state == BlockchainState.confirmed && confirmations < required) ||
          (state == BlockchainState.included && confirmations >= required) ||
          (state == BlockchainState.confirmed &&
              value['chain_id'] == '31337' &&
              finality != BlockchainFinality.notApplicable)) {
        throw const FormatException('Confirmation policy');
      }
      if (value['last_evidence'] case final Map<String, Object?> prior) {
        for (final field in [
          'chain_id',
          'contract_address',
          'protocol_version',
          'certificate_key',
          'issuer_id',
          'commitment',
        ]) {
          if (prior[field] != value[field]) {
            throw const FormatException('Previous observation identity');
          }
        }
      }
    }
  }
  return BlockchainEvidence(
    state: state,
    finality: finality,
    checkedAt: HttpVerificationRepository.decodeDate(value['checked_at']),
    source: source,
    chainId: value['chain_id'] as String?,
    contractAddress: value['contract_address'] as String?,
    protocolVersion: value['protocol_version'] as int?,
    certificateKey: value['certificate_key'] as String?,
    issuerId: value['issuer_id'] as String?,
    commitment: value['commitment'] as String?,
    revoked: value['revoked'] as bool?,
    transactionHash: value['transaction_hash'] as String?,
    blockNumber: value['block_number'] as String?,
    blockHash: value['block_hash'] as String?,
    confirmations: value['confirmations'] as String?,
    registeredAt: value['registered_at'] == null
        ? null
        : HttpVerificationRepository.decodeDate(value['registered_at']),
    previous: value['last_evidence'] == null
        ? null
        : decodeEvidence(value['last_evidence'], code, previous: true),
  );
}

VerificationResult decodeV2(Object? input, String code) {
  final v = closedObject(input, {'schema_version', 'registry', 'blockchain'});
  if (v['schema_version'] != '2') throw const FormatException('Version');
  final r = HttpVerificationRepository.decodeResult(v['registry'], code);
  if (r.status == VerificationStatus.notFound) {
    if (v['blockchain'] != null) throw const FormatException('Privacy');
    return r;
  }
  final evidence = decodeEvidence(v['blockchain'], code);
  if (evidence.state == BlockchainState.offChainOnly &&
      evidence.checkedAt != r.record!.checkedAt) {
    throw const FormatException('Date');
  }
  if (evidence.source == EvidenceSource.backendRpc &&
      [
        BlockchainState.included,
        BlockchainState.confirmed,
      ].contains(evidence.state) &&
      evidence.revoked != (r.status == VerificationStatus.revoked)) {
    throw const FormatException('Divergence');
  }
  return VerificationResult(r.status, record: r.record, blockchain: evidence);
}

CertificateOpening decodeOpening(Object? input) {
  final v = closedObject(input, {
    'protocol_version',
    'credential_code',
    'issuer_id',
    'document_sha256',
    'salt',
    'chain_id',
    'contract_address',
  });
  final code = v['credential_code'];
  if (v['protocol_version'] is! int ||
      v['protocol_version'] != 1 ||
      code is! String ||
      code.length != 36 ||
      normalizeCredentialCode(code) != code ||
      [
        'issuer_id',
        'document_sha256',
        'salt',
      ].any((k) => !bytesHex(v[k], 32)) ||
      !['31337', '11155111'].contains(v['chain_id']) ||
      !bytesHex(v['contract_address'], 20)) {
    throw const FormatException('Opening');
  }
  return CertificateOpening(
    protocolVersion: 1,
    code: code,
    issuerId: v['issuer_id']! as String,
    documentSha256: v['document_sha256']! as String,
    salt: v['salt']! as String,
    chainId: v['chain_id']! as String,
    contractAddress: v['contract_address']! as String,
  );
}

CertificateOpening parseOpening(String source) =>
    decodeOpening(decodeStrictJson(source, maxBytes: 2048));
String encodeOpening(CertificateOpening opening) => jsonEncode({
  'protocol_version': opening.protocolVersion,
  'credential_code': opening.code,
  'issuer_id': opening.issuerId,
  'document_sha256': opening.documentSha256,
  'salt': opening.salt,
  'chain_id': opening.chainId,
  'contract_address': opening.contractAddress,
});
