import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/issuance_repository.dart';

Future<SelectedPdf?> pickPdf() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (file == null) return null;
  final length = file.lengthSync() ?? await file.length();
  if (length == null) throw const IssuanceException('invalid_pdf');
  if (length > maxPdfBytes) throw const IssuanceException('payload_too_large');
  final bytes = BytesBuilder();
  await for (final chunk in file.readAsByteStream()) {
    if (bytes.length + chunk.length > maxPdfBytes) {
      throw const IssuanceException('payload_too_large');
    }
    bytes.add(chunk);
  }
  return SelectedPdf(name: file.name, bytes: bytes.takeBytes());
}
