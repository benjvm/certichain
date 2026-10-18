import 'package:unorm_dart/unorm_dart.dart' as unicode;

/// ADR-0018: NFC, newline folding and ASCII-only trim, counted as code points.
String normalizeRevocationReason(String input) => unicode
    .nfc(input.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
    .replaceAll(RegExp(r'^[ \t\n]+|[ \t\n]+$'), '');

String? revocationReasonError(String input) {
  final value = normalizeRevocationReason(input);
  if (value.isEmpty) return 'Introduce un motivo privado.';
  if (value.runes.length > 500) {
    return 'El motivo admite hasta 500 puntos Unicode.';
  }
  if (value.runes.any(
    (r) =>
        (r < 32 && r != 9 && r != 10) ||
        r == 127 ||
        (r >= 0xd800 && r <= 0xdfff),
  )) {
    return 'El motivo contiene caracteres no admitidos. Usa texto, tabulaciones o saltos de línea.';
  }
  return null;
}
