import 'dart:typed_data';

import 'verification_repository.dart';

const comparisonPdfLimit = 8388608;

enum FileIntegrity { match, integrityMismatch, unavailable }

enum LocalPdfFailure { empty, tooLarge, unreadable }

class LocalPdfException implements Exception {
  const LocalPdfException(this.failure);
  final LocalPdfFailure failure;
}

class HashComparison {
  const HashComparison(this.verification, this.integrity);
  final VerificationResult verification;
  final FileIntegrity integrity;
}

abstract interface class HashComparisonRepository {
  Future<HashComparison> compare(String code, String documentSha256);
}

abstract interface class ComparisonPdfPicker {
  Future<Uint8List?> pick();
  void cancel();
}

abstract interface class PdfHasher {
  Future<String> hash(Uint8List bytes, {bool Function()? isCancelled});
}

class PdfHashCancelled implements Exception {
  const PdfHashCancelled();
}

void validateComparisonBytes(int length) {
  if (length == 0) throw const LocalPdfException(LocalPdfFailure.empty);
  if (length > comparisonPdfLimit) {
    throw const LocalPdfException(LocalPdfFailure.tooLarge);
  }
}
