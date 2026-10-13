import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../core/files/bounded_local_file.dart';
import '../../../core/files/picker_temporary_file.dart';

class OpeningFile {
  int _generation = 0;
  void cancel() {
    _generation++;
  }

  Future<String?> pick() async {
    final generation = ++_generation;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    try {
      if (generation != _generation) return null;
      final size = file.lengthSync() ?? await file.length();
      if (size == null || size <= 0 || size > 2048) {
        throw const FormatException('Invalid opening file');
      }
      final bytes = await readBoundedLocalFile(
        file.readAsByteStream(),
        2048,
        cancelled: () => generation != _generation,
      );
      return generation == _generation ? utf8.decode(bytes) : null;
    } finally {
      await removePickerTemporaryFile(file.path);
    }
  }
}

Future<bool> saveOpening(String json) async =>
    await FilePicker.saveFile(
      dialogTitle: 'Exportar apertura',
      fileName: 'apertura.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
    ) !=
    null;
