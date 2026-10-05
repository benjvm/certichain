# Aceptación de la fase 8D

**Estado:** implementación y validación local terminadas para la demo Web técnica,
con pendientes de plataforma/validación humana explícitos. Cambios en working tree,
sin nuevo commit, push ni despliegue. Base revisada:
`d31a2735b3c51a651f101da5b764612a45862cac`. Git estaba limpio al iniciar y no había
commits posteriores. No hay una ejecución CI 8D observada.

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

## Resultados locales finales

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
