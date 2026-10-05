# CertiChain Flutter

App feature-first con capas presentation/domain/data. SDK fijado en CI:
Flutter 3.47.4 / Dart 3.13.3. Dependencias exactas y lockfiles versionados.

```powershell
flutter pub get --enforce-lockfile
Push-Location tool
npm ci --ignore-scripts
node prepare_decoder.mjs
Pop-Location
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
```

Escanear QR y Comparar mi PDF están en verificación pública con/sin sesión.
Configurar SUPABASE_URL y PUBLIC_VERIFICATION_BASE_URL; Auth privada necesita
SUPABASE_PUBLISHABLE_KEY. Nunca usar service_role en Flutter. HTTPS en producción;
HTTP loopback solo debug. Web cámara requiere getUserMedia/permiso/contexto seguro;
decoder ZXing se sirve local desde web/decoder. Android permiso CAMERA opcional;
iOS NSCameraUsageDescription, sin fotos/micrófono. Archivo local máximo 8 MiB,
SHA-256 exacto, sin subir bytes/nombre/ruta; match no cambia un estado revocado.

[Contrato y aplicación local](../docs/PUBLIC_VERIFICATION.md),
[pruebas y límites de plataformas](../docs/TESTING.md),
[arquitectura](../docs/FLUTTER_ARCHITECTURE.md),
[ADR-0013](../docs/adr/0013-public-candidate-hash-and-qr-scanning.md).
Los fixtures SQL/HTTP requieren stack descartable. No ejecutar un reset sobre
la base habitual ni desplegar para reproducirlos.
