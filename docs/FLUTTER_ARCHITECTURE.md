# Arquitectura Flutter

La aplicación móvil usa una organización **feature-first** inspirada en Clean
Architecture. El objetivo es mantener límites claros sin introducir
abstracciones hasta que exista un caso de uso que las necesite.

## Estructura general

- `app/` contiene la configuración global de Flutter: widget raíz, navegación y
  tema visual. No contiene reglas de negocio.
- `core/` contiene código reutilizable por varias features, como constantes,
  errores, utilidades, servicios comunes y widgets compartidos. No debe incluir
  comportamiento específico de una feature.
- `features/` agrupa cada capacidad del producto de forma independiente. Las
  features iniciales son `auth`, `certificates`, `issuance`, `institutions`, `verification`
  y `profile`.

## Capas de una feature

Cada feature se divide solo cuando lo necesita en:

- `domain/`: entidades, contratos de repositorio y casos de uso. Es Dart puro y
  no depende de Flutter, Supabase, formatos JSON ni librerías blockchain.
- `data/`: fuentes de datos, DTO/modelos, mapeos e implementaciones de los
  contratos definidos por el dominio. Aquí se integrarán posteriormente
  Supabase, APIs o almacenamiento local.
- `presentation/`: páginas, widgets y providers/controladores de estado. Puede
  depender del dominio, pero no consulta directamente infraestructura ni
  contiene reglas de negocio.

La dirección de dependencias es `presentation -> domain <- data`. Las
operaciones privilegiadas y el uso de secretos permanecen en backend.

## Añadir una nueva feature

Una nueva capacidad se crea bajo `mobile/lib/features/<feature>/`. Deben
añadirse únicamente las carpetas y capas que requiera su primer caso de uso,
manteniendo sus conceptos de dominio independientes de Flutter e
infraestructura. Si la decisión altera límites estructurales o responsabilidades
existentes, debe actualizarse la documentación arquitectónica y valorarse un
ADR.

## Auth — Phase 4B

`main` es la raíz de composición: valida `AppConfig`, inicializa Supabase e
inyecta `SupabaseAuthRepository` en `CertiChainApp`. `AuthRepository` y sus tipos
son Dart puro. Las pantallas reciben el contrato por constructor; el router
propaga esa dependencia. `AuthController` (ChangeNotifier del SDK Flutter)
observa una única suscripción y coordina sesión/logout. El widget raíz sustituye
el navegador al cambiar el estado de autenticación o la identidad. La UI no
consulta Supabase directamente. No se añaden service locators ni gestores externos.
Los tests inyectan un repositorio falso. Detalles en [AUTHENTICATION.md](AUTHENTICATION.md).

## Perfil y certificados — Fase 4C

`main` inyecta también `ProfileRepository` y `CertificateRepository` con sus
adaptadores Supabase. `features/profile` y `features/certificates` separan
entidades/contratos Dart, traducción de filas en data y widgets de lectura en
presentation. La vigencia pertenece al dominio `Certificate.validityAt`.
`app/AuthenticatedArea` compone ambas features, coordina futuros, reintentos,
temporizadores y destinos `AuthenticatedSection`. El navegador ligado a la sesión
destruye los datos visibles al cambiar la identidad. No hay dependencias nuevas
ni cambio de decisión arquitectónica que requiera ADR.

Los futuros se comparten entre inicio, wallet y perfil dentro de esa área;
FutureBuilder oculta datos anteriores durante una nueva lectura e ignora
completados de solicitudes sustituidas. Detalles en [STUDENT_WALLET.md](STUDENT_WALLET.md).

## Fundamentos visuales y detalle — Fase 4D

Los tokens permanecen en `app/theme/`: colores, tipografía, espaciado, radios,
tamaños e iconografía. Inter 4.1 se incorpora como asset local con su licencia,
sin dependencias Dart nuevas ni descargas de fuentes durante la ejecución.
`core/widgets` aporta `AppTopBar`, `AppBottomNavigation`, `AppButton` y estados
de lectura. `CertificateCard`, `StatusBadge`, `CertificatePreview` y
`CertificateDetailScreen` pertenecen a la presentación de certificados.

`AppRouter.certificateDetail` crea `/certificates/detail` con un ID como argumento,
el titular de la sesión y el contrato inyectado. Es una ruta interna, sin deep
links. La pantalla consulta `CertificateRepository.readCertificate(userId, id)`;
el adaptador reutiliza el mapeo existente y añade filtros de ID y titular. No
hay consultas de infraestructura desde la presentación.

El detalle posee su futuro, reintento, observador de reanudación y temporizador
de expiración. Las lecturas sustituidas se ignoran; no se presenta `snapshot.data`
mientras una nueva lectura está pendiente. La sustitución del navegador por
identidad/estado Auth también destruye el detalle. El regreso conserva el destino
y el desplazamiento del origen; renovar el token del mismo usuario conserva la ruta.

No se alteran límites de capas, backend, RLS ni decisiones estructurales; no
se necesita un ADR nuevo. Véase [FLUTTER_UI_FOUNDATIONS.md](FLUTTER_UI_FOUNDATIONS.md).

## Instituciones, emisión y PDF — Fase 7C

`main` compone InstitutionRepository, IssuanceRepository, PdfPicker,
PendingAttemptStore y CertificateDocumentRepository. Sus implementaciones
Supabase/HTTP, preferencias y archivos están en data; dominio sigue siendo Dart
puro y no importa Supabase, Flutter, PostgREST ni Web3. No se añade gestor de estado.
Análisis activa strict-casts, strict-inference y strict-raw-types.

InstitutionRepository lee membresías propias y certificados emitidos con filtro
explícito de institución, orden estable, count y límite visible de 50. No se
consulta ningún perfil ajeno. AuthenticatedArea añade un acceso condicional sin
alterar wallet/perfil personales. Las rutas centralizadas /institutions y
/institutions/issue llevan identidad e institución, nunca capacidades PDF.
Los widgets actualizan membresías en reanudación, sesión y temporizador; el
backend revalida privilegios en toda emisión y acceso al documento.

IssuanceData normaliza metadatos y fecha; SelectedPdf conserva bytes inmutables;
IssuanceRequest produce la huella v1 compatible con backend. IssuanceController
coordina estado, recibo antes de HTTP, single-flight y reintentos exactos. La UI
usa contratos sin construir Storage URLs ni INSERT de certificados. El
adaptador multipart emplea el JWT real y mensajes públicos traducidos. 401
llama al flujo Auth existente y cambia el navegador por identidad.

CertificateDocumentRepository ofrece disponibilidad/descarga, sin URL en el
dominio. El adaptador autoriza de nuevo cada descarga, acepta únicamente la
capacidad relativa del API configurado, TTL ≤60, bytes PDF limitados y verifica
identidad después de la red. El guardado usa import condicional: Web Blob y
anchor sin navegación; plataformas nativas FilePicker.saveFile. La disponibilidad
no se infiere de columnas técnicas ni de un dibujo. El detalle permanece solo
del titular; el listado institucional no lo reutiliza.

### Dependencias fijadas y mantenimiento

Versiones exactas en pubspec y lock, actualizaciones deliberadas con estas pruebas:

La API federada y correcciones se verificaron en el
[changelog del mantenedor de file_picker](https://pub.dev/packages/file_picker/changelog).

| Paquete | Necesidad y alternativa estándar |
|---|---|
| file_picker 13.1.0 | Un PDF por selector Android/iOS y guardado nativo con bytes. Flutter no trae selector de archivos común; canales propios por plataforma duplicarían código y mantenimiento. Versión con correcciones posteriores a 10.x, API pública y paquetes nativos federados fijados por lock; no se importan APIs internas. Web usa HTMLInputElement estándar para selección y evita incidencias DOM observadas del plugin. |
| unorm_dart 0.3.2 | NFC idéntico al backend para idempotencia. Dart no ofrece NFC estándar; conservar texto sin normalizar rompería el contrato. Revisar tablas Unicode/vectores al actualizar. |
| http 1.6.0 / http_parser 4.1.2 | Multipart, control de errores/Retry-After, transportes inyectables Web/nativo. Ya transitivos del SDK; se declaran directos. dart:io no funciona en Web; el invocador genérico SDK no ofrece este control de respuesta. |
| crypto 3.0.7 | SHA-256 estándar y huella v1 Dart puro, ya transitivo. No hay SHA-256 en dart:core; evitar implementación criptográfica propia. |
| shared_preferences 2.5.5 | Recibo mínimo, aislado/acotado; ya transitivo. No es cifrado ni guarda PDF/JWT/datos personales. Memoria sola impediría recuperación tras reinicio. |
| web 1.1.1 | Interoperabilidad DOM/Blob estándar, ya transitiva. dart:html está obsoleto; no se añade un visor o downloader externo. |

file_picker puede usar caché temporal del sistema al seleccionar archivos nativos;
la app no copia el PDF a preferencias. La recuperación requiere reselección del
original. Los harness Web utilizan los mismos adaptadores de producción y APIs DOM estándar. Revisar seguridad/compatibilidad y probar Chrome,
Android/iOS al cambiar versiones; límites y decisión estructural en
[ADR-0010](adr/0010-institutional-client-and-document-capabilities.md).

## Verificación y compartición — 8B

features/verification separa dominio Dart puro (resultado, registro, fallos,
VerificationRepository, CredentialRepository, normalización y VerificationLink),
data (HttpVerificationRepository y SupabaseCredentialRepository) y presentation
(VerificationController, VerificationScreen y CredentialShare/VerificationQr).
main compone el HTTP público antes de inicializar Auth y actualiza dependencias
privadas del mismo CertiChainApp. No cambia framework: ChangeNotifier,
StatefulWidget/FutureBuilder como los recorridos existentes.

MaterialApp.router/RouterDelegate/RouteInformationParser estándar controlan dos
rutas públicas Web con hash e historial. El Navigator privado queda anidado,
ligado a estado/identidad; el Router delega atrás al Navigator privado cuando
corresponde. Auth cambia ese navegador, nunca el público. El cambio estructural
se documenta en [ADR-0012](adr/0012-public-web-navigation-and-credential-sharing.md).

Transporte público independiente del SDK: body cerrado, petición abortable de
15 segundos y respuesta real máxima 8192 bytes. Errores públicos no invalidan Auth.
Generaciones protegen ediciones, respuestas fuera de orden y dispose. Fechas
UTC, estado del servidor y sin preferencias de consultas.

El código se obtiene con SELECT propio de cuatro campos, filtros id/holder_id
y barrera usuario/token/caducidad. El vínculo 7B diferencia legados; no se consulta
su tabla técnica. QR en panel del detalle ligado a la sesión. Base Web separada,
validada y URL hash centralizada; falta de base no bloquea el formulario público.

Nueva dependencia: **qr 4.0.0** exacta, generador Dart mantenido; el painter solo
representa su matriz/margen de cuatro módulos. Flutter no incluye codificador QR;
mantener uno propio sería innecesario. Sin cámara/escáner. tool/package.json/lock
fijan jsqr 1.4.0/pngjs 7.0.0 para decodificación independiente, fuera del binario.
Actualizar exige comprobar decodificación, margen, contraste y Web. Fuentes y
alternativas en ADR-0012.


## Escáner y comparación local — 8C

Dominio Dart puro añade QrCamera, ComparisonPdfPicker, PdfHasher y
HashComparisonRepository/HashComparison/FileIntegrity. Data implementa
MobileScannerCamera, gateways PDF condicionales, Sha256PdfHasher y el segundo
método del transporte HTTP independiente. Presentation coordina QrScanController,
QrScannerPanel, generaciones código/archivo de VerificationController y cooldown
compartido por PublicRouter. La raíz inyecta dependencias; no hay queries UI ni
importaciones Flutter/Supabase/Web3 en dominio. El lector bounded_local_file
comparte capacidad nativa de bytes, sin compartir modelos/reglas de emisión.

Hash por bloques de 64 KiB cede al event loop y se cancela al invalidar generación.
Gateway consulta tamaño antes de materializar y lee como máximo 8 MiB (+1 para
detectar exceso Web). Bytes descartados al hashear; digest solo flujo activo y
reintento manual, sin preferencias. Estado e integridad separados; comparaciones
renuevan checked_at y no reclasifican por reloj cliente. Retry-After compartido
persiste al abandonar/reabrir pantalla. Cámara empieza por botón y se detiene
al identificar/cerrar/navegar/segundo plano; liberación contempla permiso tardío.

HTTP Web usa fetch credentials:omit (también sin cookies de mismo origen),
redirect:error/no-referrer, AbortController y lectura streaming limitada a 8 KiB.
No comparte transporte ni cabeceras con Auth. Contrato v1 intacto y nuevo DTO
cerrado anidado; comparación envía solo código/hash, sin upload.

Nueva dependencia exacta mobile_scanner 7.4.2 (Android/iOS/Web); licencia/SDK,
alternativa, mantenimiento y permisos en
[ADR-0013](adr/0013-public-candidate-hash-and-qr-scanning.md). Decoder Web explícito
ZXing JS 0.23.0 UMD servido local desde web/decoder, generado por tool/prepare_decoder.mjs
con npm lockfile y manifest SHA-256. No CDN ni gallery ni imágenes retornadas.
Android CAMERA opcional; iOS texto de cámara; Web HTTPS/loopback y getUserMedia.
Actualizar exige repetir E2E con cámara emulada y revisión en dispositivos reales.
