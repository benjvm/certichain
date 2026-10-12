# Demo técnica reproducible de verificación — 8D

Este guion ejecuta la aplicación real (`mobile/lib/main.dart`) en Web release,
con configuración pública válida y HTTPS loopback. Crea un stack **nuevo** fuera
del checkout, usa datos sintéticos y lo destruye en `finally`. Preserva el stack
habitual `certichain`/54321. No ejecuta despliegues ni escribe blockchain.

Estado al 10/10/2026: 8D publicada en 6235486. Actions 37373509169 intento 1 no
ejecutó pasos por fallo interno/adquisición de runners hosted; aceptación CI
pendiente. Resultados locales nuevos en [PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md),
publicación/rerun exclusivamente del operador según
[PHASE8_OPERATOR_CHECKLIST.md](PHASE8_OPERATOR_CHECKLIST.md).

## Preparación

Windows/PowerShell 7, Docker Desktop Linux funcionando, Git, OpenSSL (Git para
Windows), Chrome, Flutter **3.47.4** / Dart **3.13.3**, Node **24.14.0** y Supabase
CLI **2.117.0** en PATH. `.node-version`, `mobile/tool/package-lock.json` y
`engine-strict` fijan las herramientas; no usar Node 22. El CLI puede indicarse
con `$env:SUPABASE_CLI='ruta/al/supabase.exe'`. Flutter depende del SDK Android
solo para las comprobaciones nativas opcionales.

Puertos 55320–55329, 9083 y 7358 libres; Docker descarga las imágenes del stack
si aún no existen. Los probes HTTP usan conexiones independientes y deadlines.
No copiar `.env`, `.temp` ni volúmenes del stack habitual. Las migraciones y
funciones se copian exactamente; solo los harness copiados cambian la conexión
loopback y el nombre del contenedor. Nunca usar `db reset` sobre el stack habitual.

Desde la raíz del repositorio:

```powershell
./supabase/tests/run_phase8d.ps1
# Validación ampliada: SQL/HTTP/Deno/Flutter y harness complementarios, secuenciales.
./supabase/tests/run_phase8d.ps1 -Full
```

El script rechaza otras versiones Node, prepara un proyecto `certichain_8d_*`,
regenera/verifica assets, construye release y ejecuta el recorrido. Cada etapa
fallida aborta la ejecución y conserva un diagnóstico sanitizado. Finalmente
elimina solo los contenedores/volúmenes y el directorio temporal de ese proyecto.
Si detener Docker falla, conserva ese directorio para inspección y comunica error.

## Recorrido mostrado

1. Inicia sesión como emisor sintético autorizado, elige su institución verificada
   y emite desde el formulario real seleccionando un PDF sintético. Contrasta el
   hash y cada byte publicado en Storage.
2. Cierra sesión y entra como titular: abre su detalle y descarga los mismos bytes.
   Muestra QR, copia efectivamente el enlace por clipboard y comprueba que solo
   contiene el código público.
3. Abre ese enlace en otro contexto anónimo, con una cookie previa en el mismo
   origen. Comprueba una única consulta pública sin cookie/Authorization/apikey.
4. Niega permiso de cámara, lo concede después y lee un vídeo de ese QR renderizado
   mediante getUserMedia y ZXing de producción. Confirma una sola consulta y
   verifica que la cámara se detiene.
5. Selecciona el PDF original y la copia renombrada: `match`; cambia un byte:
   `integrity_mismatch`. Cancela selección, prueba vacío, 8 MiB+1 y exactamente
   8 MiB. El navegador envía únicamente código/hash, nunca el documento.
6. Fixtures controlados muestran suspensión, revocación y caducidad manteniendo
   `match` independiente. No es un nuevo flujo de revocación de producto.
7. Dos repeticiones con respuestas retenidas prueban cambio A→B y cancelación;
   503, respuesta malformada/excesiva, desconexión y timeout muestran error y
   «Consulta anterior». Un reintento explícito actualiza `checked_at`.
8. Agota el presupuesto sintético y espera **una ventana real de 60 segundos**.
   No hay petición automática al terminar `Retry-After`; solo el reintento
   explícito consulta otra vez. Después comprueba recarga, historial, logout y
   aislamiento al cambiar de cuenta.

En el host quedan solamente `mobile/build/phase8d-evidence/result.json` y capturas
públicas sintéticas `comparison-*.png` y `qr-synthetic.png`. El JSON contiene etapas, versiones,
contadores y tiempos; no payloads privados ni URLs firmadas. El build contiene
solo configuración pública; TLS, clave de servicio y fixtures técnicos quedan
en temporales del host y se limpian. El certificado TLS tiene SAN loopback y el
navegador de pruebas confía únicamente en su SPKI; la app mantiene HTTPS obligatorio
en release. No publicar ese build de demo: apunta al origen local del harness.

El JSON vigente registra `source_commit` obtenido de Git, `working_tree_dirty`
y `evaluated_at` UTC. Un working tree modificado no acredita exclusivamente ese
SHA. Los JSON históricos con `base_commit=d31a273` usaban una constante; conservar
su fecha/contexto y no emplear ese campo como identificación del commit ejecutado.

## Herramientas individuales y limpieza

Para investigar una etapa, crear otro stack con `prepare_disposable_local.ps1
-Start`, guardar su ruta y usar `CERTICHAIN_TEST_BACKEND_ROOT` para los harness Web,
`CERTICHAIN_TEST_DISPOSABLE=1` y ejecutar HTTP/SQL desde esa ruta. Nunca correr
suites que alteran fixtures/presupuesto simultáneamente. Los harness comprueban
la identidad del proyecto además de la variable de entorno.

```powershell
$taskStack = ./supabase/tests/prepare_disposable_local.ps1 -Start
$env:CERTICHAIN_TEST_BACKEND_ROOT = $taskStack
$env:CERTICHAIN_TEST_DISPOSABLE = '1'
try {
  Push-Location mobile
  try { node tool/release_verification_browser.mjs } finally { Pop-Location }
} finally {
  ./supabase/tests/stop_disposable_local.ps1 -Root $taskStack
}
```

Para Edge, indicar `CHROME_EXECUTABLE` y `CERTICHAIN_EVIDENCE_DIRECTORY` con un
subdirectorio propio bajo `mobile/build`; no reutilizar evidencia de Chrome.
Firefox/Safari requieren el procedimiento manual de PHASE8_ACCEPTANCE.md.

La cámara Web es emulada. Android dispone de probes complementarios para selector,
permisos y ciclo de vida; no equivale al recorrido completo de Auth/emisión en
Android ni a una cámara física. Ver resultados y pendientes en
[PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md).


## Probes Android complementarios

Usar emulador descartable o read-only dedicado, sin paquete com.example.mobile
instalado. No ejecutar sobre una app existente: el runner la rechaza.

```powershell
Push-Location mobile
flutter build apk --debug --target=tool/qr_native_smoke.dart
./tool/qr_native_smoke.ps1 -Serial emulator-5554
flutter build apk --debug --target=tool/pdf_native_smoke.dart
./tool/pdf_native_smoke.ps1 -Serial emulator-5554
flutter build apk --release --target=lib/main.dart
Pop-Location
```

La cámara comprueba permiso denegado, concedido después, inicio del adaptador real,
fondo/primer plano con reactivación explícita, cierre y revocación. El PDF prueba
cancelación y selector/saver OS, bytes exactos, conservación del original y copia
cache propia. Cada probe desinstala solo su instalación y borra sus fixtures en
finally. El póster virtual opcional (-QrImage) no produjo detección dentro de 40 s
en esta ejecución: la decodificación QR Android y la cámara física siguen pendientes.
No equivale a ejecutar main.dart completo en Android. Detener solo el emulador
propio (por serial confirmado) al terminar; no guardar snapshot si es read-only.

`-QrImage` debe ser un PNG propio cuyo contenido sea UUID estricto o enlace
`https://certichain.example/#/verify/<UUID>` (base del probe). Un QR del harness Web
con origen localhost se rechaza correctamente; no prueba fallo del decoder.
Resolver la ruta con `Resolve-Path` desde mobile antes de inyectarla. La revisión
del 10/10 corrigió la resolución relativa frente a Push-Location y detecta KO de
la consola emulator aunque adb termine exit 0. El emulador puede aceptar una
ruta inexistente con OK y mantener el póster por defecto: comprobar la captura
antes de interpretar un timeout como fallo ML Kit.

Para el recorrido Android **principal** pendiente, usar otra instancia dedicada,
crear dos cuentas sintéticas mediante Auth y el alta institucional existente
(SECURE_ISSUANCE.md/INSTITUTION_ADMIN.md), aprobar solo la institución de prueba y
dar al emisor una membresía autorizada. El titular copia su UUID desde Mi perfil.
Configurar una URL HTTPS de la app y una API HTTPS accesibles al dispositivo,
con certificado de confianza. El TLS/SPKI del harness Chrome no configura confianza
Android. No desactivar HTTPS ni validación TLS para hacer pasar el recorrido.
Construir `flutter build apk --release --target=lib/main.dart` con
`--dart-define=SUPABASE_URL=<API HTTPS>`,
`--dart-define=SUPABASE_PUBLISHABLE_KEY=<clave pública del stack>` y
`--dart-define=PUBLIC_VERIFICATION_BASE_URL=<app HTTPS>`; instalar únicamente en
esa instancia sin paquete previo. Repetir pasos 1–8 anteriores, registrar versión,
resultados y tiempos, y limpiar solo cuentas/objetos/instalación propios.
No equivale al probe, ni al build main sin configuración que solo prueba compilación.
