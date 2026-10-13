import 'package:flutter/foundation.dart';

import '../domain/blockchain_verification.dart';
import '../domain/hash_comparison.dart';

class OpeningCheckController extends ChangeNotifier {
  OpeningCheckController(this.input, this.picker, this.hasher);
  final OpeningInput input;
  final ComparisonPdfPicker picker;
  final PdfHasher hasher;
  bool busy = false, _disposed = false;
  OpeningCheck? result;
  LocalPdfFailure? pdfFailure;
  int _generation = 0;
  String? imported;
  void reset() {
    _generation++;
    input.cancel();
    picker.cancel();
    imported = null;
    result = null;
    pdfFailure = null;
    busy = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> import() async {
    reset();
    final generation = _generation;
    busy = true;
    notifyListeners();
    try {
      final source = await input.pickJson();
      if (_disposed || generation != _generation) return;
      if (source != null) {
        input.parse(source);
        imported = source;
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        result = const OpeningCheck(OpeningValidity.invalidOpening);
      }
    }
    if (!_disposed && generation == _generation) {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> check(
    String json,
    String code,
    BlockchainEvidence? evidence,
  ) async {
    if (busy || _disposed) return;
    reset();
    final generation = _generation;
    busy = true;
    notifyListeners();
    bool current() => !_disposed && generation == _generation;
    CertificateOpening opening;
    try {
      opening = input.parse(json);
    } catch (_) {
      if (current()) {
        result = const OpeningCheck(OpeningValidity.invalidOpening);
        busy = false;
        notifyListeners();
      }
      return;
    }
    try {
      if (opening.code != code) {
        result = const OpeningCheck(OpeningValidity.invalidOpening);
      } else {
        var bytes = await picker.pick();
        if (!current()) return;
        if (bytes != null) {
          validateComparisonBytes(bytes.length);
          final hash = await hasher.hash(bytes, isCancelled: () => !current());
          bytes = null;
          if (!current()) return;
          result = checkOpening(opening, code, hash, evidence);
        }
      }
    } on LocalPdfException catch (e) {
      if (current()) pdfFailure = e.failure;
    } catch (_) {
      if (current()) {
        pdfFailure = LocalPdfFailure.unreadable;
      }
    }
    if (current()) {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    super.dispose();
  }
}
