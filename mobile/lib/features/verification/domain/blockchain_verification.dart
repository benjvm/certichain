import 'dart:convert';

import 'package:crypto/crypto.dart';

enum BlockchainState {
  offChainOnly,
  pending,
  included,
  confirmed,
  reorged,
  unavailable,
  divergence,
}

enum BlockchainFinality { unknown, notApplicable, finalized }

enum EvidenceSource { registry, backendRpc, persistedReceipt, unavailable }

/// Server observation. No EVM transport or SDK types in Flutter's domain.
class BlockchainEvidence {
  const BlockchainEvidence({
    required this.state,
    required this.finality,
    required this.checkedAt,
    required this.source,
    this.chainId,
    this.contractAddress,
    this.protocolVersion,
    this.certificateKey,
    this.issuerId,
    this.commitment,
    this.revoked,
    this.transactionHash,
    this.blockNumber,
    this.blockHash,
    this.confirmations,
    this.registeredAt,
    this.previous,
  });
  final BlockchainState state;
  final BlockchainFinality finality;
  final DateTime checkedAt;
  final EvidenceSource source;
  final String? chainId,
      contractAddress,
      certificateKey,
      issuerId,
      commitment,
      transactionHash,
      blockNumber,
      blockHash,
      confirmations;
  final int? protocolVersion;
  final bool? revoked;
  final DateTime? registeredAt;
  final BlockchainEvidence? previous;
  bool get canCheckOpening =>
      source == EvidenceSource.backendRpc &&
      (state == BlockchainState.included ||
          state == BlockchainState.confirmed) &&
      commitment != null;
  Uri? get explorer {
    // Built from fixed hosts and validated hash only, never a URL from a DTO.
    if (chainId != '11155111' ||
        transactionHash == null ||
        !RegExp(r'^0x[0-9a-f]{64}$').hasMatch(transactionHash!)) {
      return null;
    }
    return Uri.https('sepolia.etherscan.io', '/tx/$transactionHash');
  }
}

class CertificateOpening {
  const CertificateOpening({
    required this.protocolVersion,
    required this.code,
    required this.issuerId,
    required this.documentSha256,
    required this.salt,
    required this.chainId,
    required this.contractAddress,
  });
  final int protocolVersion;
  final String code, issuerId, documentSha256, salt, chainId, contractAddress;
}

abstract interface class OpeningInput {
  CertificateOpening parse(String json);
  Future<String?> pickJson();
  void cancel();
}

enum OpeningValidity { match, pdfMismatch, invalidOpening, evidenceUnavailable }

class OpeningCheck {
  const OpeningCheck(
    this.validity, {
    this.evidenceCheckedAt,
    this.evidenceSource,
  });
  final OpeningValidity validity;
  final DateTime? evidenceCheckedAt;
  final EvidenceSource? evidenceSource;
}

List<int> protocolHexBytes(String hex) {
  if (!RegExp(r'^0x(?:[0-9a-f]{2})+$').hasMatch(hex)) {
    throw const FormatException('Invalid protocol value');
  }
  return [
    for (var i = 2; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

String protocolDigest(List<int> bytes) => '0x${sha256.convert(bytes)}';
String certificateKey(String code) {
  if (code.length != 36 ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(code)) {
    throw const FormatException('Invalid code');
  }
  return protocolDigest([
    ...utf8.encode('certichain:certificate-key:v1'),
    0,
    ...protocolHexBytes('0x${code.toLowerCase().replaceAll('-', '')}'),
  ]);
}

String documentCommitment(String key, String issuer, String hash, String salt) {
  for (final value in [key, issuer, hash, salt]) {
    if (value.length != 66) throw const FormatException('Invalid bytes32');
  }
  return protocolDigest([
    ...utf8.encode('certichain:document-commitment:v1'),
    0,
    ...protocolHexBytes(key),
    ...protocolHexBytes(issuer),
    ...protocolHexBytes(hash),
    ...protocolHexBytes(salt),
  ]);
}

/// Only SHA-256 and protocol-v1 encoding. Never uploads PDF/opening/salt.
OpeningCheck checkOpening(
  CertificateOpening opening,
  String code,
  String pdfSha256,
  BlockchainEvidence? evidence,
) {
  final key = certificateKey(code);
  final commitment = documentCommitment(
    key,
    opening.issuerId,
    opening.documentSha256,
    opening.salt,
  );
  if (opening.protocolVersion != 1 ||
      opening.code != code ||
      (evidence?.chainId != null &&
          (opening.chainId != evidence!.chainId ||
              opening.contractAddress != evidence.contractAddress)) ||
      (evidence?.certificateKey != null && key != evidence!.certificateKey) ||
      (evidence?.issuerId != null && opening.issuerId != evidence!.issuerId) ||
      (evidence?.commitment != null && commitment != evidence!.commitment)) {
    return const OpeningCheck(OpeningValidity.invalidOpening);
  }
  if ('0x$pdfSha256' != opening.documentSha256) {
    return const OpeningCheck(OpeningValidity.pdfMismatch);
  }
  if (evidence == null || !evidence.canCheckOpening) {
    return const OpeningCheck(OpeningValidity.evidenceUnavailable);
  }
  return OpeningCheck(
    OpeningValidity.match,
    evidenceCheckedAt: evidence.checkedAt,
    evidenceSource: evidence.source,
  );
}
