import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/hash_comparison.dart';
import '../../../core/files/bounded_local_file.dart';
import '../../../core/files/picker_temporary_file.dart';

class PlatformComparisonPdfPicker implements ComparisonPdfPicker {
  int _generation = 0;
  @override
  void cancel() {
    _generation++;
  }

  @override
  Future<Uint8List?> pick() async {
    final generation = ++_generation;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return null;
    try {
      if (generation != _generation) return null;
      final length = file.lengthSync() ?? await file.length();
      if (length == null) {
        throw const LocalPdfException(LocalPdfFailure.unreadable);
      }
      validateComparisonBytes(length);
      Uint8List selected;
      try {
        selected = await readBoundedLocalFile(
          file.readAsByteStream(),
          comparisonPdfLimit,
          cancelled: () => generation != _generation,
        );
      } on LocalFileReadException {
        throw const LocalPdfException(LocalPdfFailure.tooLarge);
      }
      if (generation != _generation) return null;
      validateComparisonBytes(selected.length);
      return generation == _generation ? selected : null;
    } finally {
      await removePickerTemporaryFile(file.path);
    }
  }
}
