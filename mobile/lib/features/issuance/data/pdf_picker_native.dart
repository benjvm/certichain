import 'package:file_picker/file_picker.dart';

import '../domain/issuance_repository.dart';
import '../../../core/files/bounded_local_file.dart';
import '../../../core/files/picker_temporary_file.dart';

class PlatformPdfPicker implements PdfPicker {
  int _generation = 0;
  @override
  void cancel() {
    _generation++;
  }

  @override
  Future<SelectedPdf?> pick() async {
    final generation = ++_generation;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return null;
    try {
      if (generation != _generation) return null;
      final length = file.lengthSync() ?? await file.length();
      if (length == null) throw const IssuanceException('invalid_pdf');
      if (length > maxPdfBytes) {
        throw const IssuanceException('payload_too_large');
      }
      final bytes = await readBoundedLocalFile(
        file.readAsByteStream(),
        maxPdfBytes,
        cancelled: () => generation != _generation,
      );
      if (generation != _generation) return null;
      return SelectedPdf(name: file.name, bytes: bytes);
    } on LocalFileReadException {
      throw const IssuanceException('payload_too_large');
    } finally {
      await removePickerTemporaryFile(file.path);
    }
  }
}
