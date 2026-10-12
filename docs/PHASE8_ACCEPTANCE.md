# Aceptación de la fase 8D

**Estado vigente al 10/10/2026:** 8D está publicada en
`62354866e1c127e445c369bedee58742581ec2cd` («8D stage»). Checkout `main` limpio al
iniciar esta revisión, idéntico a `main` remoto, sin commits posteriores.
La aceptación CI está pendiente por un fallo externo anterior a la ejecución.
Los cambios de documentación de esta revisión quedan locales, sin commit/push
ni despliegue. Checklist: [PHASE8_OPERATOR_CHECKLIST.md](PHASE8_OPERATOR_CHECKLIST.md).

## CI observada el 10/10/2026

[Actions 37373509169](https://github.com/benjvm/certichain/actions/runs/37373509169),
intento **1**, commit **6235486**, workflow `database.yml`: completed/failure.
Los jobs `database` **111976231865** y `flutter` **111976231713** terminaron
cancelled, con **cero pasos**, runner_id 0 y nombre de runner vacío. Se consultaron
run, intento/jobs, check-runs del commit, logs y artefactos mediante el conector.
Cada check contiene una anotación; el endpoint de anotaciones fue rechazado por
el conector y la sesión de navegador sin autenticar devolvió 404 del repo privado.
El operador aportó el texto visible de las tres anotaciones:

- Ambos jobs: «The job was not acquired by Runner of type hosted even after multiple attempts».
- Workflow: «Internal server error». Correlation ID:
  `6242d09f-3d5d-4096-bdbb-8e8b882693e7`.

**Causa confirmada:** Actions no asignó runners hosted; fallo interno antes de
compilar o probar. La causa interna de GitHub no se conoce. No hay evidencia de
defecto de código, tests, facturación o cuotas. Logs flutter: 404 BlobNotFound;
sin artefactos, incluido `phase8d-release-evidence`. No hubo rerun remoto durante
esta revisión. El operador debe reejecutar tras resolver/comprobar disponibilidad
y, si reaparece, escalar a GitHub con run/UTC/ID de correlación. No se modifican
checks, acciones fijadas ni timeouts para ocultarlo.

## Revalidación local del 10/10/2026

Windows/PowerShell **7.6.5**, Flutter **3.47.4** / Dart **3.13.3**, Node
**24.14.0**, CLI **2.117.0**, Deno **2.2.12**. PostgreSQL **17.6**, Edge runtime
**1.74.3**, Docker **29.8.2 Linux**. Las versiones CLI/SDK/dependencias se
mantuvieron congeladas. Chrome/Edge cambiaron desde 154 histórico a 155 actual.
No se cambiaron código de producto, contratos, dependencias ni migraciones.

| Comando/área ejecutada | Resultado actual |
|---|---|
| `./supabase/tests/run_phase8d.ps1 -Full` | **Exit 0**, comando completo, stack nuevo y limpieza finally |
| SQL + lint + cuatro preservaciones | **611 PASS**, lint limpio, cuatro PASS; migraciones intactas |
| HTTP emisión / hardening / descarga | **366 / 135 / 90 PASS**, 14 publicaciones hardening; Storage privado PASS |
| HTTP verificación / comparación | **296 / 255 PASS**, presupuesto compartido atómico, permisos y fallos |
| Concurrencia | **8 owner +6 emisión PASS** |
| Deno fmt/lint/check frozen/test | **68 PASS**; fmt ampliado del workflow **43 archivos PASS** |
| Flutter formato/análisis/test | 111 archivos sin cambios, análisis limpio, **198 PASS +1 opt-in omitido** |
| Builds/harness complementarios | 7D **69 Flutter +29 host PASS**; 8B+8C **74 PASS**, 16 verify/4 compare; PDF Chrome PASS |
| `./supabase/tests/run_phase8d.ps1` | **Exit 0**, segundo stack nuevo; Chrome main.dart release **127 +141 PASS**, 1 emisión/11 verify/24 compare |
| Guion por defecto con `CHROME_EXECUTABLE=msedge` | Primer intento FAIL esperando QR; repetición acotada **exit 0**, **127 +141 PASS**, 1 emisión/11 verify/24 compare |
| Node CDP/readiness/metadatos | **8 PASS**, incluidas dos regresiones nuevas de SHA/working tree/diagnóstico seguro |
| `./mobile/tool/native_adb_test.ps1` | **7 PASS**, KO exit 0, diagnóstico acotado y rutas relativas/literales/ausentes |
| Assets/lockfiles | npm ci sin EBADENGINE, regeneración/check/diff PASS; lockfiles intactos |
| Smoke CDP Windows / Linux Docker reconstruido | **45 /45 PASS**; Linux Node 24.14.0, Chrome 154.0.8037.97, Ubuntu 24.04 |
| Android main.dart | debug/release **build PASS**, release 71,8 MB; **no recorrido completo** |
| APK main debug/release secretos técnicos | **1.812 comprobaciones PASS** de archivos ZIP descomprimidos contra service_role/JWT secret del stack; valores no emitidos |

El `-Full` arrancó antes de añadir la etapa PowerShell nueva; esa etapa y las
regresiones finales se ejecutaron separadamente. No se atribuye al primer comando
la ejecución de una etapa que aún no contenía. El recorrido release sí ejercitó
los metadatos corregidos. Tras las correcciones se revalidaron sus áreas y
`git diff --check`. Ninguno de estos resultados equivale a CI.

Evidencia Chrome: `mobile/build/phase8d-evidence/result.json` y capturas sintéticas;
primer resultado Full conservado en `mobile/build/phase8d-evidence-full/result.json`.
Ambos registran **source_commit=6235486, working_tree_dirty=true y evaluated_at**.
Corrección comprobada: el harness anterior fijaba base_commit=d31a273 en cualquier
checkout. Ahora identifica Git real sin exportar rutas/diagnósticos. Los errores
de cámara Web registran etapa precisa, estado/dimensiones del vídeo y captura
anónima sintética; no relajan deadlines ni checks.

### Android y límites de la reproducción actual

Emulador **36.5.11.0**, adb **37.0.0 /1.0.41**, Pixel_2 API **34 x86_64**, instancia
propia read-only, sin snapshots. Primer probe cámara **PASS**: permiso denegado,
concedido después, adaptador iniciado, pausa/regreso/reactivación/cierre/revocación.
Probe PDF real **PASS**, también con renderer software: cancelar, selector/saver,
bytes exactos, copia cache ausente y original conservado.

La lectura QR no obtuvo PASS. Se observaron instalación sin espacio (data 90%),
timeout en native-qr-decode, otra repetición detenida en background-pause y
deadlines ADB de shell/instalación en los intentos aislados, incluido SwiftShader.
Son resultados fallidos, no confirmación de regresión del producto ni del decoder.
No se aumentaron deadlines. El recorrido Android completo no se ejecutó: los
probes no forman un driver de cuentas sobre main.dart y la confianza TLS/SPKI del
harness Chrome no configura un origen HTTPS confiable en Android.

Se comprobó un defecto del **probe**: GetFullPath relativo ignora Push-Location,
de modo que la imagen existente bajo mobile/build se buscaba bajo el cwd del
proceso. La captura camera-preview-later.png mostró cámara real con póster
por defecto, sin QR. Resolve-Path literal corrige esa ruta, con regresión.
La consola adb emu devuelve KO para comandos rechazados aunque exit=0;
ahora se detecta. Una ruta inexistente de virtualscene-image también puede
recibir OK sin cambiar el póster: se exige archivo existente antes de inyectar.
Esto no confirma la causa histórica del timeout Android del 05/10.

Capturas sintéticas/diagnóstico local en `mobile/build/phase8d-native-evidence`.
Se mantuvo la instalación personal intacta: paquete previo ausente, solo APK y
fixtures propios, finally de probes y cierre de la instancia read-only propia.
Cámara física, Firefox/Safari/iOS y revisión humana siguen **NO VERIFICADOS**.
Los tests semánticos/layout 320 px/texto ×2 pasan; no sustituyen teclado/foco/
lector de pantalla humanos. Chrome platform tests Linux siguen obligatorios en
CI; no se ejecutaron aquí sobre Linux Flutter y no se marca PASS su limitación
histórica Windows.

Chrome Full: emisión **421 ms**, QR **373 ms**, 8 MiB selección/hash/consulta
**1.233 ms**, total **184.974 ms**. Guion por defecto: **453 /383 /2.156 ms**, total
**186.666 ms**. Son tiempos del recorrido/automatización con build, timeout
deliberado y ventana real; una muestra coincidió con actividad del emulador.
No son benchmarks aislados ni medidas de cámara física. Edge final: emisión
**445 ms**, QR **363 ms**, 8 MiB **1.168 ms**, total **165.774 ms**.

| Plataforma / versión y build | Prueba y resultado vigente | Evidencia / pendiente |
|---|---|---|
| Chrome 155.0.8059.39, Windows release main.dart | Dos recorridos **127 +141 PASS** cada uno | phase8d-evidence[-full]/result.json; cámara Y4M emulada, física pendiente |
| Edge 155.0.4283.45, Windows release main.dart | **1 FAIL QR**, repetición **127 +141 PASS** | phase8d-evidence-edgefirst/failure.json y phase8d-evidence-edge/result.json; causa del fallo aislado no confirmada |
| Chrome 154.0.8037.97, Ubuntu 24.04 Docker | Smoke CDP **45 PASS** | Imagen reconstruida con Node 24.14.0; no E2E Flutter/Linux completo |
| Android API34 x86_64 Pixel_2, emulator 36.5.11.0 | main debug/release build PASS; primer probe permisos/lifecycle PASS; PDF PASS | Capturas/errores de probes; **QR nativo y main completo pendientes**; cámara emulada |
| Web/Android cámara física | **NO EJECUTADO** | Procedimiento manual; no hardware físico adjunto |
| Firefox / Safari / iOS | **NO EJECUTADO** | No entornos disponibles; procedimiento manual |
| Flutter widgets semántica/layout 320 px/texto ×2 | **PASS** dentro de 198 tests | No sustituye teclado/foco/lector de pantalla humanos |
| Revisión humana accesibilidad | **PENDIENTE** | Checklist del operador |

El primer Edge llegó hasta el enlace anónimo y no encontró «Verificar código
identificado» dentro del deadline (104.145 ms totales). Se conserva su FAIL,
sin atribuirlo a UND_ERR_SOCKET, carga, producto o decoder. La repetición se hizo
una vez, sin emulador activo, stack nuevo, mismo deadline y mismas aserciones;
no fue retry de un POST persistente. No se confirmó una regresión reproducible.
El harness ahora registrará camera-real-decoder, estado de vídeo y captura pública
si reaparece; el primer failure.json previo conserva anonymous-link como último
checkpoint. No se promete estabilidad física por este PASS emulado.

El stack habitual estaba **detenido al iniciar** y no se arrancó/resetó: se
preserva ese estado. Solo se crearon proyectos certichain_8d_* fuera del repo.
No commit/push/merge/rerun remoto/despliegue. El temporal Edge histórico se
reinspeccionó, sin procesos asociados; el borrado volvió a ser rechazado
automáticamente y sigue en la checklist para limpieza manual.
También se rechazó la limpieza final de tres logs/PID propios y del tag de imagen
de smoke incluido en esa orden; no se ejecutó ni se eludió la restricción.
Rutas exactas/procedimiento en la checklist. No quedan contenedores/volúmenes
certichain_8d_* ni procesos de emulador propios activos; los volúmenes habituales
certichain e internhub se preservaron. Los artefactos build se conservan para revisión.

**Dictamen:** **Diseño 9A posible con aceptación 8D pendiente**. Bloqueo externo
de CI confirmado y regresiones locales suficientes para diseñar 9A; no aceptación
completa ni autorización de lanzamiento. No queda un defecto reproducible de
producto demostrado por esta revisión. Antes de declarar base validada, el
operador debe publicar las correcciones y obtener success de ambos jobs sobre
ese SHA exacto, revisar phase8d-release-evidence y cerrar/aceptar expresamente los
pendientes de plataforma/humanos. El presupuesto global 60 POST/60 s requiere
revisión antes de lanzamiento público.

## Evidencia local histórica del 05/10/2026

La implementación siguiente se validó entonces sobre working tree basado en
`d31a2735b3c51a651f101da5b764612a45862cac`, antes de publicarse como 6235486.
Los resultados históricos no sustituyen la CI de 8D ni validan ediciones posteriores.

Fecha: 2026-10-05. Windows, Europe/Madrid; AMD Ryzen 5 5600, 32 GiB RAM, Docker
Desktop Linux. Flutter 3.47.4 / Dart 3.13.3, Node 24.14.0, Supabase CLI 2.117.0,
Deno 2.2.12, PostgreSQL 17.6. Herramientas fijadas en workflow/lockfiles.

## Evidencia histórica independiente

Actions **37350396753, intento 2**, database/flutter success sobre 8C, según la
evidencia proporcionada: 182 Flutter +1 opt-in omitido, 611 SQL, 65 Deno,
296 HTTP públicas, 255 HTTP comparación, 7D 69 Flutter+29 host y 8B+8C
74/16 POST verify/4 POST compare. **No valida los cambios 8D.**
El intento 1 falló con fetch/UND_ERR_SOCKET al preparar una institución; la causa
histórica concreta permanece sin confirmar.

## Resultados locales históricos

| Área | Resultado y evidencia |
|---|---|
| Flutter | PASS formato, analyze limpio, **198 tests +1 opt-in omitido** |
| Deno | PASS fmt/lint, check frozen de cuatro entrypoints, **68 tests** |
| SQL | PASS **611 tests**, RLS/RPC/tablas/bucket privado; lint sin warnings; cuatro preservaciones PASS |
| Emisión HTTP | PASS **366** aserciones, Auth/Edge/Storage, leases/idempotencia/recuperación |
| Endurecimiento emisión | PASS **135** aserciones, PDF compatibles/límites/abuso, 14 publicaciones sintéticas |
| Storage privado | PASS aislamiento anon/authenticated, upsert/reemplazo, MIME/límite, bytes conservados |
| Descarga HTTP | PASS **90** aserciones y caducidad real; readiness se cuenta separadamente (8C tenía 92) |
| Verificación HTTP | PASS **296** aserciones, entrada inválida consume presupuesto atómico |
| Comparación HTTP | PASS **255** aserciones, DTO mínimo y concurrencia del presupuesto compartido |
| Concurrencia | PASS 8 escenarios de propietarios +6 de emisión, solapamiento/rechazos reales |
| Harness | PASS 6 tests Node (3 CDP+3 readiness); 45 smoke Windows, 45 Linux Docker, 45 Edge |
| Assets | PASS npm ci Node24 sin EBADENGINE; regeneración/--check; UMD/licencia/manifest idénticos a Git |
| Regresión 7D complementaria | PASS 69 Flutter+29 host |
| Regresión 8B+8C complementaria | PASS 74 aserciones, 16 verify/4 compare POST |
| Adaptadores PDF Chrome | PASS build real, cancelación, 8 MiB, bytes, blob y revocación URL |
| **main.dart release Chrome** | **PASS 127 aserciones funcionales +141 inspecciones de artefactos**, 1 emisión/11 verify/24 compare POST |
| **main.dart release Edge** | **PASS 127 +141**, 1 emisión/11 verify/24 compare POST |
| Android | main.dart debug/release compilados; probes reales de cámara/permisos/ciclo de vida y PDF/cache PASS |
| Secretos | PASS builds Web; scan inicial APK 2.718 checks y APK release final 1.032 checks; sin valores técnicos emitidos |
| Limpieza | PASS dos ejecuciones del guion con stacks nuevos, exit 0 y eliminación de sus directorios; primer stack también eliminado; emulador propio detenido; stack habitual disponible en 54321 |

El guion por defecto se ejecutó dos veces. Las etapas de `-Full` se ejecutaron
individualmente de forma coordinada; no se afirma haber ejecutado `-Full` como
un único comando. Comandos en [DEMO_VERIFICATION.md](DEMO_VERIFICATION.md).
SQL ejecutado simultáneamente con fixtures Web falló por interferencia en conteos;
se corrigió el orden y volvió a pasar limpio. No se atribuye al esquema.

Los JSON finales están en `mobile/build/phase8d-evidence/result.json` y
`mobile/build/phase8d-evidence-edge/result.json`, junto a capturas públicas
sintéticas `comparison-*.png` y `qr-synthetic.png`. Solo contienen etapas,
versiones, resultados, contadores y tiempos. Las capturas se inspeccionaron:
«Registro encontrado y vigente»/«Certificado revocado» y «El PDF coincide» se
presentan por separado. CI sube únicamente ese directorio sanitizado.

## Criterios del recorrido y seguridad

La entrada principal es **lib/main.dart release**, con configuración pública
completa y HTTPS loopback, Auth/PostgREST/Edge/PostgreSQL/Storage reales y UI,
semántica y adaptadores de producción. No llama hooks Dart instrumentados.
La confianza TLS del navegador de pruebas se limita al SPKI del certificado
local; no se relaja HTTPS de producción. Secretos, SQL y fixtures quedan en el host.

Emisor autorizado → selección/emisión → bytes publicados → titular/descarga
exacta → QR y copia efectiva → contexto anónimo → getUserMedia/ZXing local real
con cámara Y4M → una confirmación pública → original/renombrado `match` → un byte
cambiado `integrity_mismatch`. Suspensión/revocación/caducidad mediante fixtures
controlados conservan la integridad independiente. No hay nuevo flujo de revocación.

Se verifican petición pública sin Authorization/apikey/Cookie incluso con cookie
en el mismo origen, body comparación exclusivamente código/hash y ausencia de
upload del candidato. DTO público cerrado sin hash registrado/titular/rutas/URL
firmada; QR/clipboard sin credenciales/capacidad privada; decoder/fotogramas locales.
SQL/HTTP mantienen denegación de RPC técnicos, bucket privado y aislamiento privado
entre titulares/cuentas. No hay migraciones nuevas ni cambios en las anteriores.

Errores 503, backend desconectado, timeout, respuesta malformada/excesiva y 429
muestran error; comparación fallida marca DTO/checked_at anteriores como
«Consulta anterior». Reintento válido actualiza la fecha. Dos repeticiones release
con respuestas retenidas prueban A→B y cancelación; tests de controlador repiten
selección/lectura/dispose tres veces. Vacío/cancelado/8 MiB+1 no envían POST;
8 MiB exactos calcula localmente el hash correcto. Auth/recarga/historial no duplican
consultas. Cámara/streams/timers/selectores/transporte propio se liberan.

El presupuesto global atómico compartido **60 POST/60 s** incluye entradas inválidas.
La renovación espera una ventana temporal real, sin mover reloj ni contador durante
ella, y exige acción explícita tras Retry-After; no hay polling. Manipulaciones y
guards de teardown solo en stacks descartables, restaurados en finally/transacción.
Sirve a la demo; un usuario puede agotarlo para todos. Protección y capacidad para
lanzamiento público son requisitos posteriores.

## Causas confirmadas y recursos

Se reprodujeron/corrigieron coerción array→valid y fechas imposibles, confirmación
doble QR, permiso inactive que ocultaba denegación, old-ready de un proceso anterior
y relanzamiento de compatibilidad Edge que escapaba al cierre. Se mantienen las
correcciones CDP 8C. La causa histórica UND_ERR_SOCKET sigue sin diagnóstico concreto.

Readiness exige marcador del serve actual y probes acotados Auth/PostgREST/Storage,
rechazo JWT y **GET 405 del módulo público real**, sin RPC, consumo ni credenciales
públicas. Salida/fallo prematuro se detecta. Conexiones del operador independientes;
POST de creación sin reintento ciego, teardown descubre escrituras propias con
respuesta perdida y confirma deletes.

Android reveló una retención efectiva de caché: Flutter usa `code_cache` para
Directory.systemTemp, y file_picker 13.1.0/android_file_picker 2.0.0 copia a
`cache/file_picker/<timestamp>/<file>`. Se deriva solo esa carpeta hermana dentro
de la app y se validan raíz canónica/forma/ausencia de enlaces. La regresión host
y el probe nativo comprueban copia ausente y original conservado. No se vacía una
caché global. Selección sin ruta, provider, crash o borrado denegado dependen del
OS; no se garantiza borrado seguro del soporte.

La preparación nativa despierta/desbloquea almacenamiento e indexa el fixture
antes de DocumentsUI. El emulador agotó espacio tras varias instalaciones:
INSTALL_FAILED_INSUFFICIENT_STORAGE se registró como fallo de entorno y se reinició
solo la instancia read-only propia, sin snapshots. ADB tiene límites propios
(uiautomator 10 s/otros 30 s/install 90 s), cierre de invocación/pipes y diagnósticos
sanitizados. No se añaden dependencias de producción ni una decisión estructural;
se amplía ADR-0013. Blockchain y revocación completa permanecen fuera de 8D.

## Plataformas y comprobaciones pendientes

| Plataforma | Resultado real | Cámara/alcance pendiente |
|---|---|---|
| Chrome 154.0.8037.93 / Windows | PASS Web release principal | Y4M/ZXing real; física pendiente |
| Edge 154.0.4258.53 / Windows | PASS Web release principal | Emulada/ZXing real; física pendiente |
| Chrome 154.0.8037.97 Ubuntu 24.04 Docker | PASS smoke CDP 45 | No equivale al E2E completo Linux; CI 8D pendiente |
| Firefox | No instalado, NO EJECUTADO | Procedimiento manual pendiente |
| Safari | Sin macOS, NO EJECUTADO | Procedimiento manual pendiente |
| Android Pixel_2, SDK 34, x86_64 read-only | Builds main debug/release PASS; probes PDF/permisos/cámara/lifecycle PASS | Confirmación QR con póster virtual no terminó en 40 s; **lectura QR nativa pendiente**, sin causa confirmada. Recorrido main/Auth completo y dispositivo físico pendientes |
| iOS | Sin Xcode, NO EJECUTADO | Build/run, permisos, cámara, selector/lifecycle pendientes |

`flutter test --platform chrome ...` en Windows quedó cargando y se interrumpió:
**no es PASS**. Se conserva obligatorio en CI Linux; no se sustituye por una
promesa de universalidad. Revisión humana de teclado/lector de pantalla pendiente.
Tests de widgets revisan 320×568/360/390 px y texto ×2, semántica/error/resultados,
alternativa manual y estados con texto, sin depender del color.

## Medidas

Último Chrome: total **179.955 ms**, incluido build, timeout deliberado y ventana
real. Emisión 489 ms, detección QR 372 ms, comparación PDF pequeño 501/442/437 ms,
selección+SHA-256+consulta de **8 MiB 1.176 ms**. Edge: total 164.238 ms, emisión
376 ms, QR 374 ms y 8 MiB 1.173 ms. Incluyen automatización/esperas de UI, no son
medidas de cámara física ni exclusivamente del hash. Hasher Dart VM de producción,
tres muestras 8 MiB: 102/92/79 ms y 244 ticks de event loop. Cede cada 64 KiB;
no se observó bloqueo sostenido.

## Procedimiento manual restante

1. En Firefox/Safari/Android/iOS, stack sintético exclusivo y configuración pública
   HTTPS válida, ejecutar pasos de DEMO_VERIFICATION.md; registrar build/versión,
   duración/resultados sin credenciales ni payloads privados.
2. Cámara física: permiso denegado/concedido/revocado, QR impreso/otra pantalla,
   repetición/doble confirmación, cámara ocupada/inexistente, fondo/resume y salida.
3. Selector: cancelación/cambio, 0/8 MiB/8 MiB+1, salida durante lectura/hash/consulta,
   conservación de originales y liberación de copia propia.
4. A 320 px/texto ×2: Tab/Shift+Tab/Enter, foco visible/orden, lector de pantalla,
   anuncio de errores y «Certificado revocado» separado de «El PDF coincide».
5. Recarga/historial/logout/cambio de cuenta, aislamiento privado y ausencia de POST
   públicos duplicados. Detener/limpiar solo ese entorno.

La revisión automática rechazó el borrado recursivo de un temporal de la primera
prueba Edge: `C:\Users\bensa\AppData\Local\Temp\certichain-release-8d-467qzA`, motivo
«blocked by policy». Su proceso está detenido, fixtures/budget limpiados/restaurados;
**esa carpeta concreta queda para limpieza manual**. El resto de stacks y el emulador
propios se detuvieron/limpiaron. Estos pendientes no se etiquetan PASS.
