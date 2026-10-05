# ADR-0013 — Comparación por hash candidato y escáner público

Fecha: 05/10/2026. Estado: aceptada para 8C local. Despliegue pendiente.

## Decisión

Conservar el contrato cerrado v1 de verify-certificate de ADR-0011. Añadir
compare-certificate-hash, POST público con únicamente credential_code UUID y
document_sha256 hexadecimal minúsculo de 64 caracteres. Su respuesta cerrada
contiene schema_version "1", verification (v1 vigente) y file_integrity
(match, integrity_mismatch o unavailable). No publica el hash esperado.

Una única lectura SQL privada obtiene evidencia completed, vínculos, hashes y
ruta coherentes, estado del emisor y estado del certificado. Los dos RPC públicos
usan ese snapshot y SECURITY DEFINER con search_path vacío; solo service_role
puede ejecutarlos. El helper privado no es invocable por roles API. No se cambian
filas, RLS, permisos de tablas ni Storage. Un único instante servidor decide
caducidad/checked_at y conserva revoked > expired > issuer_unavailable > valid.
Ausencia o publicación no elegible produce not_found/unavailable. Fallos técnicos
son 503, nunca ausencia o discrepancia. Ambas funciones consumen el mismo
presupuesto atómico 60 POST/60 s antes de validar la entrada, incluidas inválidas.

El gateway ComparisonPdfPicker es independiente del modelo de emisión. Reutiliza
solo el lector nativo acotado. Rechaza vacío o más de 8.388.608 bytes; consulta
metadatos antes de leer cuando están disponibles. Web usa File/Blob.slice y
selector estándar; nativo file_picker existente y stream acotado. SHA-256 usa
crypto existente en bloques de 64 KiB con cesión al event loop y cancelación por
generación. Se calculan los bytes exactos sin renderizar ni reescribir. Nombre,
ruta y bytes nunca llegan a HTTP ni Storage. Los bytes se sueltan después del
cálculo; el hash candidato solo permanece en memoria para un reintento explícito
durante el flujo activo. Cancelar, editar código, reseleccionar o salir invalida
operaciones y referencias. El selector nativo puede usar caché del sistema.

La comparación renueva verification y checked_at con la respuesta del servidor.
Estado del certificado e integridad del archivo se presentan por separado: un
PDF coincidente puede estar revocado, caducado o tener emisor no disponible.
Volver a guardar un PDF puede cambiar los bytes y producir una discrepancia.
No se comprueba identidad del presentador ni anclaje blockchain.

El escáner se activa por acción explícita, con permiso, preparación, lectura,
pausa, errores y alternativa manual. QrCamera es contrato Dart; el adaptador
mobile_scanner gestiona cámara/decodificador. Los errores de stream del plugin
se traducen a fallos de dominio sin mensajes privados; el stream propio cierra
en finally aunque la liberación del plugin falle. El adaptador libera también el
reader Web preparado parcialmente antes de un permiso denegado, ya que el stop
del controlador omite una sesión que no llegó a isRunning; permite reintentar
en el mismo panel tras cambiar el permiso. Cerrar, navegar o pasar a segundo
plano detiene la cámara; un permiso pendiente se espera para liberar una cámara
que arranque tarde. Tras detección válida se detiene, muestra UUID y requiere
confirmación explícita mediante el controlador existente. Detecciones repetidas
quedan bloqueadas antes de la parada; no hay consultas al detectar QR desconocidos.

Se acepta exactamente el enlace canónico generado por ADR-0012 bajo
PUBLIC_VERIFICATION_BASE_URL, incluida su ruta base, o un UUID directo estricto.
El UUID directo permite usar un código impreso sin navegador. Máximo 2048
caracteres, sin espacios/control/backslash, sin normalizar URLs entrantes ni
decodificar el fragmento: solo prefix canónico de confianza + UUID de 36
caracteres. Se rechazan otras bases/orígenes, userinfo, parámetros, escapes en
UUID, rutas equivalentes pero no canónicas y sufijos. Una ruta base escapada
solo se admite tal cual la produce la configuración de 8B. UUID se normaliza a
minúsculas. Nunca se abre un enlace externo. QR/frames se procesan localmente,
no se guardan capturas.

Retry-After bloquea verificación y comparación en un cooldown compartido por el
Router, incluso al cambiar ruta o llegar un 429 antiguo. Se revalida justo antes
de enviar tras selección/hash. Generaciones de código/archivo impiden respuestas
fuera de orden y callbacks tras dispose. No se hacen reintentos automáticos.
El HTTP público Web usa fetch credentials:omit, redirects:error y no-referrer;
withCredentials:false por sí solo enviaría cookies cuando API y Web comparten
origen. El transporte sigue independiente de Auth, acotado y abortable.

## Dependencias, plataformas y alternativa

**mobile_scanner 7.4.2 exacto** y lockfile: cámara/QR Android (CameraX/ML Kit
bundled), iOS (AVFoundation/Vision) y Web (getUserMedia + ZXing JS explícito).
[Versión y SDK](https://pub.dev/packages/mobile_scanner/versions/7.4.2),
[fuente y mantenimiento](https://github.com/juliansteenbakker/mobile_scanner).
Requiere Dart >=3.7/Flutter >=3.29, compatible con el SDK fijado 3.47.4/3.13.3. Se auditó también el podspec/
Package.swift: iOS mínimo 12.0, inferior al target 15.0 del proyecto; Android
compila con minSdk 24 del proyecto. iOS sigue sin validación Xcode desde Windows.
Flutter no trae cámara/decoder QR estándar: canales propios + CameraX/Vision y
un lector Web duplicarían mantenimiento. Revisar permisos, ciclo de vida y todas
las plataformas antes de actualizar, incluyendo cambios en errores del plugin.

Android declara CAMERA y cámara/autofocus opcionales, sin permiso de archivos general.
iOS añade NSCameraUsageDescription, sin fotos ni micrófono. Web requiere contexto
seguro HTTPS (loopback HTTP permitido por navegadores para desarrollo), navegador
con getUserMedia, permiso y cámara. Una política de permisos/iframe puede impedir
cámara. No se promete funcionamiento desde HTTP de una IP LAN.

**@zxing/library 0.23.0** fija el decoder Web UMD Apache-2.0 en npm lock.
[Distribución del mantenedor](https://github.com/zxing-js/library).
prepare_decoder.mjs copia el UMD sin sourceMappingURL y conserva licencia/manifest
SHA-256 bajo web/decoder. La app fija zxingJs y script local relativo, sin fallback
CDN. El paquete npm declara Node >=24 y npm avisa en Node 22.14; este proyecto
solo copia el UMD precompilado, no ejecuta su API Node. Generación y decodificación
real en navegador se validan con Node 22.14. Revisar ese requisito al actualizar.
ZXing-js es el backend legacy del plugin y consume más CPU que su opción WASM.
Se elige el UMD para QR, por sus assets autocontenidos y la integración local
comprobada; reevaluar rendimiento en dispositivos y la alternativa WASM en 8D.
La alternativa BarcodeDetector nativa Web no es uniforme entre navegadores.

## Evidencia y consecuencias

Pruebas y comandos en TESTING.md y PUBLIC_VERIFICATION.md. Chrome Web usa cámara
emulada Y4M de un QR realmente pintado por Flutter, getUserMedia/decoder reales,
selector DOM real y Auth/Edge/PostgreSQL/Storage locales. Android APK compilado;
iOS y cámaras físicas pendientes. El smoke CDP corre en Windows y Ubuntu 24.04;
los recorridos Flutter/backend completos se ejecutaron en Windows. GitHub Actions
nuevo no ejecutado/observado. 8D continúa pendiente.

La carrera histórica de 8B no se atribuye con certeza a un error sin detalles.
El harness ahora espera nuevo loader/contexto/DOM antes de marcadores Flutter,
reporta excepciones sanitizadas sin texto de aplicación, distingue transición de
error real, detecta lanzamiento/salida Chrome y limpia sockets/grupo de procesos/
perfil con deadlines. La reproducción controlada verifica contextos obsoletos,
DOM no disponible y excepciones reales; Linux detectó además un borrado de perfil
antes de terminar hijos Chrome, corregido con parada de grupo y espera acotada.
