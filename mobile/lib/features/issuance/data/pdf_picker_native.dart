import 'package:file_picker/file_picker.dart';

import '../domain/issuance_repository.dart';
import '../../../core/files/bounded_local_file.dart';

Future<SelectedPdf?> pickPdf() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (file == null) return null;
  final length = file.lengthSync() ?? await file.length();
  if (length == null) throw const IssuanceException('invalid_pdf');
  if (length > maxPdfBytes) throw const IssuanceException('payload_too_large');
  try {
    final bytes = await readBoundedLocalFile(
      file.readAsByteStream(),
      maxPdfBytes,
    );
    return SelectedPdf(name: file.name, bytes: bytes);
  } on LocalFileReadException {
    throw const IssuanceException('payload_too_large');
  }
}
