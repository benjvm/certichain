import '../domain/issuance_repository.dart';
import 'pdf_picker_native.dart'
    if (dart.library.js_interop) 'pdf_picker_web.dart'
    as platform;

class PlatformPdfPicker implements PdfPicker {
  @override
  Future<SelectedPdf?> pick() => platform.pickPdf();
}
