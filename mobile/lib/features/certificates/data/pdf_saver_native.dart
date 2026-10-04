import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> savePdf(Uint8List bytes) async =>
    await FilePicker.saveFile(
      dialogTitle: 'Guardar PDF del certificado',
      fileName: 'certificado.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes,
      mimeType: 'application/pdf',
    ) !=
    null;
