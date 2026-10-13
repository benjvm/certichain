import 'dart:io';

const cameraSkipReason =
    'Omitidas por instrucción del usuario; no hay cámara física disponible';
final Object? cameraSkip = Platform.environment['CERTICHAIN_TEST_CAMERA'] == '1'
    ? null
    : cameraSkipReason;

bool get cameraWidgetSkip {
  if (cameraSkip != null) stderr.writeln('SKIP/NOT_RUN: $cameraSkipReason');
  return cameraSkip != null;
}
