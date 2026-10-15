# Verificación pública — Backend 8A e interfaz Web 8B

## Incremento local de revocación — 15/10/2026

[REVOCATION](REVOCATION.md) define los endpoints Auth, motivo/auditoría privados,
SQL irreversible, worker durable y evidencia pública v3 con issue/revoke separados.
V1/v2 y compare conservan contrato; la app usa v3. Resultados ejecutados y
dictamen vigente: [PHASE10_ACCEPTANCE](PHASE10_ACCEPTANCE.md). Los apartados
que describen revocación futura conservan el contexto histórico de sus fases.
La demo se reproduce con `./supabase/tests/run_phase10.ps1`; sin despliegue remoto,
Sepolia ni corrección Android atribuida. Cámara=0 con la exclusión persistente.

## Alcance local

**Completada y comprobada localmente el 04/10/2026.** 557 SQL, 44 Deno y 296
aserciones HTTP públicas pasan; se conservan las suites anteriores. No es un
despliegue remoto ni una ejecución GitHub Actions de 8A.

8A implementa contrato, consulta restringida PostgreSQL, Edge Function pública,
presupuesto compartido, pruebas SQL/Deno/HTTP y CI. No implementa pantalla
Flutter, QR, enlace navegable, escáner, comparación de una copia, blockchain,
nuevo flujo de revocación ni despliegue remoto. Estado de validación y resultados
reales en [TESTING.md](TESTING.md). Decisiones en
[ADR-0011](adr/0011-public-registry-verification.md).

7A–7D ya entregaron emisión autenticada, validación PDF, SHA-256 sobre bytes
finales, idempotencia, recuperación y documento privado. La
[ejecución 7D 37218682263](https://github.com/benjvm/certichain/actions/runs/37218682263)
es **evidencia previamente observada**, aportada al cierre de 7D. No es CI de
estos cambios 8A; no se ejecutó ni se observó un nuevo GitHub Actions para 8A.

## Contrato v1

Actualización de diseño 9A (12/10/2026): v1 y sus RPC permanecen intactos;
credential_code, enlaces y QR conservan formato. Blockchain aún no integrada.
La futura ampliación usará endpoint/schema v2 separado, con estado del registro,
evidencia EVM, integridad de copia y fechas/orígenes independientes. Campos
permitidos, confirmaciones/finalidad y contraste en explorador:
[PHASE9A_BLOCKCHAIN_SPEC.md](PHASE9A_BLOCKCHAIN_SPEC.md), sección 10.
El hash esperado no se publicará tampoco en cadena: se registra un compromiso
con salt privado. Sin apertura, match v1 sigue confiando en Supabase; no se
promete comparación documental independiente. RPC caído no significa
not_found, revocado o integrity_mismatch. No se anuncia confirmado on-chain
por tener completed/valid off-chain.

`POST /functions/v1/verify-certificate`, sin sesión Auth, Authorization ni apikey.
JSON UTF-8, Content-Type `application/json` (opcional `; charset=utf-8`), máximo
**2048 bytes reales**, incluso sin Content-Length. Solo un campo permitido:

```json
{"credential_code":"e42f105a-a36b-40de-8326-47da5749eae3"}
```

UUID ASCII de 36 caracteres con guiones 8-4-4-4-12, hexadecimal sin restricción
de versión, mayúsculas/minúsculas equivalentes. Se normaliza a minúsculas antes
de buscar; no trim, llaves, URN, separadores alternativos ni UUID sin guiones.
No se admiten valores no string, arrays, null ni campos adicionales. Parámetros
query y cabeceras no configuran la consulta ni el presupuesto.

Una publicación elegible devuelve 200 y **exclusivamente nueve campos**:

```json
{
  "schema_version":"1",
  "result":"valid",
  "credential_code":"e42f105a-a36b-40de-8326-47da5749eae3",
  "title":"Certificado sintético",
  "issuer":{"name":"Institución sintética"},
  "issued_at":"2026-10-04T10:00:00.123456+00:00",
  "expires_at":null,
  "checked_at":"2026-10-04T12:00:00.654321+00:00",
  "verification_source":"certichain_registry"
}
```

`schema_version` es el string literal `"1"`; `verification_source` es siempre
`certichain_registry`. `issuer` solo contiene `name`, el nombre actual de la
institución. No existe logo institucional en este esquema. Fechas RFC3339
de PostgreSQL, conservando hasta seis decimales; la función no convierte a
Date JavaScript. `expires_at` admite null. `checked_at` es un único instante
servidor por consulta y también se usa para decidir expiración.

Para ausencia de evidencia elegible, respuesta uniforme 200:

```json
{"schema_version":"1","result":"not_found"}
```

No incluye código reflejado, instante, título ni metadatos institucionales.
El orden de claves JSON no forma parte del contrato. No hay campos privados:
titular/nombre/correo, IDs internos, issued_by, descripción, membresías,
ruta/hash/documento, URL firmada, idempotencia, fingerprints, leases o secretos.
La Edge valida también la lista cerrada recibida de BD antes de responder.

| HTTP | Respuesta mínima | Observación |
|---|---|---|
| 200 | contrato v1 | Incluye not_found |
| 400 | `{"error":"invalid_input"}` | Formato, JSON, MIME o campos inválidos |
| 405 | `{"error":"method_not_allowed"}` | Allow: POST, OPTIONS |
| 413 | `{"error":"payload_too_large"}` | Límite real del stream excedido |
| 429 | `{"error":"rate_limited"}` | Retry-After entero 1–60 del servidor |
| 503 | `{"error":"temporary_failure"}` | Infraestructura, timeout o proyección inesperada |

OPTIONS devuelve 204 vacío y CORS; no consulta BD ni consume presupuesto.
Todas las respuestas llevan CORS (`*`, sin cookies) y Cache-Control: no-store;
Retry-After está expuesto a navegadores. Los otros métodos no consumen cupo.
Se consume presupuesto antes de validar POST: agotado, incluso un cuerpo inválido
obtiene 429. No se devuelven errores SQL, constraints ni cuerpos upstream.
Lectura de entrada: deadline 3 s; cada fetch RPC: abort a 5 s; respuesta upstream
limitada a 8 KiB y lectura a 3 s; bloqueo del limitador a 2 s. Los fallos se
acotan por etapa. No se registran cuerpos, códigos, PII, tokens o credenciales.

## Evidencia pública elegible

Se reutiliza `certificates.credential_code`: 7B genera UUID aleatorio independiente
del ID interno mediante gen_random_uuid(). El UNIQUE existente impide duplicados,
y la guarda de 7A congela el código de toda fila ligada a operación. No se añade
public_id ni índice adicional: la igualdad sobre el código canónico aprovecha
su índice único. Los códigos históricos no se normalizan ni se reasignan.

La consulta exige simultáneamente:

- vínculo del certificado con una operación `completed`;
- certificate_id y target_certificate_id iguales al certificado;
- misma institución, titular y actor/emisor en ambos registros;
- document_hash SHA-256 hexadecimal minúsculo de 64 caracteres, coincidente
  con stored_hash y pdf_hash;
- document_path canónico `<institution_id>/<certificate_id>.pdf`.

Las FK compuestas, checks y triggers existentes siguen protegiendo esas
identidades. Una reserva, finalizing incompleto, intento fallido o histórico
sin evidencia suficiente se trata como desconocido. No se inventan hashes,
documentos ni vínculos para convertir antiguos registros en verificables.

La consulta normal **no descarga ni hashea hasta 8 MiB de PDF por petición**.
Comprueba la evidencia persistida al publicar por 7B; no comprueba existencia
actual de Storage ni integridad actual de sus bytes en cada consulta. El acceso
privado al documento mantiene su comprobación independiente de 7C.

## Prioridad y significado de resultados

Elegibilidad se evalúa antes del estado. Para un certificado elegible:

1. `revoked`: status revoked, incluso caducado o con institución suspendida.
2. `expired`: no revocado y expires_at <= checked_at, incluida igualdad exacta.
3. `issuer_unavailable`: no revocado/caducado y institución no verified.
4. `valid`: vigente, no revocado y institución verified.

Suspender el emisor no equivale a revocar cada certificado. 8A lee el estado
existente; no abre una operación de revocación. No existe pending en este
contrato porque no hay proceso blockchain.

`valid` significa cumplimiento de estas condiciones en el registro CertiChain.
No demuestra identidad de quien presenta el código ni una prueba blockchain.
Integridad de una copia elegida por el verificador requerirá calcular su hash y
compararlo mediante un contrato posterior; no se realiza en 8A.

## Permisos y presupuesto global

`lookup_public_certificate(text)` y `consume_public_verification_budget()` son
RPC estrechos SECURITY DEFINER, search_path vacío y referencias cualificadas.
EXECUTE solo de service_role; revocado de PUBLIC, anon y authenticated. El helper
privado de prioridad tampoco es ejecutable por service_role/roles API. El esquema
privado no está expuesto. La clave técnica vive exclusivamente en backend;
el verificador no consulta RPC directamente. Ningún grant de certificados,
operaciones, perfiles, instituciones o Storage se amplía.

`certichain_private.public_verification_budget` tiene RLS sin políticas ni grants
a PUBLIC/anon/authenticated/service_role. Contiene una única fila con inicio de
ventana y contador 0–60. No guarda IP, código ni eventos. La función bloquea esa
fila FOR UPDATE, lee el reloj después de adquirir el bloqueo, renueva si han
transcurrido 60 s y concede como máximo 60 consumos. El rechazo no incrementa
más allá de 60; Retry-After redondea hacia arriba hasta el fin de ventana.
Ausencia de fila, errores o contención demasiado larga fallan cerrado con 503.
Consumo y consulta son dos transacciones: errores de entrada/consulta no devuelven
el cupo ya consumido. Ninguna entrada del cliente puede reiniciar ni parametrizar
límites. No se confía en X-Forwarded-For; no se identifica a personas.

Es un presupuesto **global para la demo local**: cualquier verificador comparte
capacidad con los demás y podría agotarla para todos. Ventanas fijas permiten
ráfagas junto a la frontera. No es estrategia completa de tráfico público de
producción; antes de desplegar deben diseñarse ingress, límites de concurrencia,
abuso/equidad y observabilidad sin datos innecesarios.

## Reproducción local sin tocar el entorno habitual

Docker, Node 24.14.0, Supabase CLI 2.117.0 y Deno 2.2.12; mismas versiones de CI.
Desde raíz, en PowerShell, crear un segundo proyecto fuera del repositorio:

```powershell
$sandbox = & ./supabase/tests/prepare_disposable_local.ps1 -Start
Push-Location $sandbox
try {
  # start ya reconstruyó todas las migraciones en volúmenes nuevos.
  & $env:SUPABASE_CLI test db --local
  $env:CERTICHAIN_TEST_DISPOSABLE = '1'
  node supabase/tests/public_verification_http.mjs
  node supabase/tests/issuance_http.mjs
  node supabase/tests/issuance_hardening.mjs
  node supabase/tests/private_storage.mjs
  node supabase/tests/certificate_pdf_http.mjs
  node supabase/tests/institution_concurrency.mjs
  ./supabase/tests/verify_certificate_migration.ps1
  ./supabase/tests/verify_private_issuance_migration.ps1
  ./supabase/tests/verify_public_verification_migration.ps1
  & $env:SUPABASE_CLI db lint --local --schema 'public,certichain_private' --level warning --fail-on warning
} finally {
  & $env:SUPABASE_CLI stop --no-backup
  Remove-Item Env:CERTICHAIN_TEST_DISPOSABLE -ErrorAction SilentlyContinue
  Pop-Location
}
```

El preparador usa project_id aleatorio y puertos 55320–55329/9083. No copia
.temp/.branches/env ni datos, no resetea el proyecto habitual y no imprime claves.
Copia las migraciones/funciones sin alterarlas; solo adapta en las copias de
harness las referencias de contenedor y puerto loopback. Si esos puertos están
ocupados, se detiene sin modificar otros stacks. Conserva fuentes temporales para
inspección; stop --no-backup afecta solo al proyecto descartable. En PowerShell
con política restrictiva se puede abrir un proceso `powershell -NoProfile
-ExecutionPolicy Bypass` exclusivamente para esta reproducción.

Cada harness HTTP arranca y termina su propio functions serve; ejecutarlos
secuencialmente. El de 8A exige la marca explícita de entorno descartable porque
ajusta reloj/contador e inyecta fallos mediante SQL técnico local. Conserva y
restaura la fila del presupuesto. Usa Auth/Storage reales solo para crear/limpiar
fixtures; la petición de verificación es fetch sin credenciales. Teardown
elimina únicamente identidades/instituciones/certificados/objetos propios con el
helper existente. Los fixtures de caducidad son publicaciones sintéticas de
fechas pasadas compatibles con constraints; no cambian fechas ya emitidas ni
desactivan guardas para probar revocación.

Para consulta manual en el sandbox todavía arrancado, ejecutar en una consola
`& $env:SUPABASE_CLI functions serve` desde su directorio; en otra:

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:55321/functions/v1/verify-certificate -Method Post -ContentType 'application/json' -Body '{"credential_code":"e42f105a-a36b-40de-8326-47da5749eae3"}'
```

Sin fixture con ese código, obtiene not_found. Para un valid, usar el código real
de una publicación de 7B consultado por un operador SQL local autorizado. No usar
service_role en el cliente ni --no-verify-jwt global. El stack habitual continúa en
54321 y no recibe la migración automáticamente por probar en el sandbox.

## Reparto vigente de los incrementos

- **8B:** pantalla pública, enlaces Web navegables y QR del titular.
- **8C completada localmente y CI observada:** escáner y comparación;
  Actions 37350396753 intento 2 valida d31a273. Despliegue pendiente.
- **8D implementada localmente:** recorrido main.dart release HTTPS y endurecimiento;
  publicada en 6235486; resultados y plataformas pendientes en PHASE8_ACCEPTANCE.md.
  CI 37373509169 intento 1 observada el 10/10: run failure/jobs cancelled antes de pasos por
  runners hosted no adquiridos/error interno GitHub; aceptación CI pendiente.

Este reparto corrige la discrepancia del documento de 8A; su evidencia histórica
se conserva. Blockchain y revocación completa tienen sus propios incrementos.

## Interfaz Web y compartición local — 8B

`/verify` abre el formulario público; `/verify/<UUID>` consulta una vez el código.
Web usa `http://localhost:7357/#/verify/<UUID>`. El Router estándar sincroniza
atrás/adelante/recarga y conserva el código al restaurar Auth. La pantalla está
disponible con/sin sesión y tras errores del acceso privado. main monta el
repositorio público antes de esperar Supabase. No se añaden librerías de routing.

El UUID se recorta por fuera y normaliza a minúsculas; se rechazan entradas
inválidas sin HTTP. Consultar/actualizar son acciones explícitas; no hay polling.
El estado procede del servidor, sin reclasificación por reloj del dispositivo.
Se muestran título, emisor, emisión, expiración opcional, código y checked_at,
con fechas UTC explicadas. not_found no recibe campos ficticios. Se explica que
se consulta el registro, sin comprobar la identidad del presentador o una copia.

Cliente HTTP independiente, únicamente credential_code; sin JWT/Authorization,
apikey o cookies (fetch credentials:omit en Web), tablas privadas ni RPC técnicos. Deadline total
15 s (petición abortable) y respuesta real limitada a 8 KiB. Lista de claves v1
cerrada, tipos/versión/fuente/UUID/fechas/resultados validados; lo inesperado es
error técnico. 400 corrige entrada, red/timeout admiten reintento manual, 503
indica indisponibilidad y 429 explica la espera. Retry-After entero bloquea
consultas hasta vencer; si falta/es inválido se espera una ventana completa.
El contador de pantalla no cambia el presupuesto backend de 60 POST/60 s.

Generaciones descartan respuestas A después de editar/iniciar B y tras dispose.
Un 429 tardío conserva su espera, sin asociar un resultado viejo al nuevo código.
No hay historial ni preferencias de consultas. Los cambios de Auth no provocan
HTTP público ni invalidan la sesión por un fallo público.

Desde el detalle propio, Mostrar QR y enlace hace una lectura autenticada mínima
de id, holder_id, credential_code e issuance_operation_id, filtrada por id y
holder_id. Revalida identidad/token/vencimiento al recibir. Sin vínculo 7B no hay
enlace. Las FK/checks/inmutabilidad existentes protegen el vínculo; el endpoint
público determina la elegibilidad y estado final. No se leen operaciones privadas,
PDF/hash/perfiles ajenos ni se abren grants. Caducados/revocados/emisor suspendido
con vínculo siguen compartibles; el código nunca se reemplaza por certificates.id.

PUBLIC_VERIFICATION_BASE_URL debe apuntar a la app, separado de SUPABASE_URL.
HTTPS salvo HTTP loopback en debug; sin credenciales/query/fragmento, base con
path opcional normalizada y URL hash construida centralmente. Ausencia/base
inválida explica que compartir está indisponible; el formulario sigue funcionando.
QR local mediante qr 4.0.0, contraste negro/blanco y cuatro módulos de margen.
Solo contiene la URL y el UUID, nunca JWT/apikey/datos/PDF/hash/capacidad firmada.
No modifica ni regenera el PDF emitido. Copia con confirmación semántica y enlace
seleccionable. El panel pertenece al detalle y se elimina al cambiar sesión o
cuenta y al salir. Decisión: [ADR-0012](adr/0012-public-web-navigation-and-credential-sharing.md).

### Chrome con puerto fijo

Con el stack descartable arrancado y functions serve en otra consola, desde mobile:

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=7357 --dart-define=SUPABASE_URL=http://127.0.0.1:55321 --dart-define=SUPABASE_PUBLISHABLE_KEY=CLAVE_PUBLICA_LOCAL --dart-define=PUBLIC_VERIFICATION_BASE_URL=http://localhost:7357
```

Sustituir CLAVE_PUBLICA_LOCAL por la publishable/anon del **stack descartable**;
no usar service_role. Obtenerla localmente con supabase status, sin versionarla.
HTTP está autorizado solo en desarrollo debug. La base habitual no recibe un
reset ni las migraciones automáticamente. El harness descrito en TESTING crea
identidades/publicaciones sintéticas y limpia sus propios recursos.

Para un certificado propio real: iniciar sesión como titular, abrir wallet y
detalle, Mostrar QR y enlace, Copiar enlace; abrirlo en un perfil/ventana privada
sin sesión. Un histórico muestra ausencia y requiere una publicación 7B existente
o una emisión autorizada. Recargar conserva el UUID. localhost solo es accesible
en el mismo equipo; un teléfono externo requiere un entorno accesible por red o
despliegue posterior. Solo enlaces Web: no Universal Links ni Android App Links.


## Comparación de una copia local y escáner — 8C

POST /functions/v1/compare-certificate-hash, JSON UTF-8, máximo 2048 bytes,
exclusivamente:

```json
{"credential_code":"e42f105a-a36b-40de-8326-47da5749eae3","document_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}
```

Respuesta HTTP 200 cerrada con tres campos: schema_version string "1",
verification (proyección v1 obtenida en esta comparación) y file_integrity
match/integrity_mismatch/unavailable. Certificado inexistente, histórico o con
publicación incompleta obtiene exactamente:

```json
{"schema_version":"1","verification":{"schema_version":"1","result":"not_found"},"file_integrity":"unavailable"}
```

Un registro elegible devuelve match o integrity_mismatch con todos los campos
v1 de verification, incluidos checked_at y verification_source. Es posible
coincidencia/discrepancia en valid, revoked, expired e issuer_unavailable.
Prioridad y elegibilidad son idénticas a 8A; estado y hash se leen juntos en
PostgreSQL. El hash registrado no sale del backend. verify-certificate conserva
su v1 sin nuevos campos.

Ambos endpoints consumen el mismo presupuesto global atómico 60 POST/60 s antes
de validar, sin particionarlo por endpoint, sesión o IP. OPTIONS permanece 204
sin consumo. CORS/no-store y errores existentes: 400 invalid_input, 405
method_not_allowed, 413 payload_too_large, 429 rate_limited con Retry-After y 503
temporary_failure. La entrada no admite nombre, ruta, Base64, multipart ni bytes.
El cliente no envía JWT/Authorization/apikey/Cookie incluso con proxy del mismo
origen; fetch usa credentials:omit y no sigue redirects. No crea objetos Storage.

Comparar mi PDF aparece para resultados elegibles. Selecciona un archivo local,
rechaza vacío/>8 MiB antes de leerlo cuando hay metadatos y limita la lectura.
Calcula SHA-256 exacto y canónico localmente, cediendo entre bloques; muestra
selección, cálculo, consulta, resultado, cancelación o error. El PDF no se
reescribe: guardar/exportar de nuevo puede producir una discrepancia. Estado e
integridad se muestran separados. Actualiza el certificado/checked_at con la
respuesta. No valida identidad del presentador ni blockchain. Los bytes se
liberan tras cálculo y el digest tras éxito/cancelación/salida; solo se retiene
para reintento explícito en el flujo activo tras error. Un 429 bloquea las dos
acciones y sobrevive al cambio de ruta. Reemplazo/código/salida invalida respuestas.

Escanear QR usa cámara solo por acción y con PUBLIC_VERIFICATION_BASE_URL válida.
Permiso/preparación/lectura/error, pausa al salir o segundo plano, liberación y
alternativa manual. Se acepta enlace canónico de 8B de esa base/ruta o UUID directo
estricto, máximo 2048 caracteres. No se abren URLs ajenas. Se rechazan esquemas,
dominios, userinfo, query, escapes en UUID, espacios y formatos ajenos. Tras
identificar se detiene y muestra UUID; Verificar código identificado confirma
una sola consulta. Fotogramas/capturas no se persisten. Decisiones, permisos,
soporte y mantenimiento: [ADR-0013](adr/0013-public-candidate-hash-and-qr-scanning.md).

Antes de build/run, preparar el decoder local (el archivo generado está
versionado y se debe regenerar al actualizar la dependencia):

```powershell
Push-Location mobile/tool
npm ci --ignore-scripts
node prepare_decoder.mjs
Pop-Location
```

Web necesita HTTPS o loopback HTTP seguro, getUserMedia y permiso. El decoder se
sirve de web/decoder, sin CDN; no se usa el BarcodeDetector experimental. Android
CAMERA opcional; iOS NSCameraUsageDescription. Cámara física Android/iOS y otros
navegadores no comprobados. No pedir permiso de fotos/micrófono.

### Aplicación local y publicación futura preparada

Desde la raíz, crear un stack NUEVO y descartable; no resetear el habitual:

```powershell
$taskStack = & ./supabase/tests/prepare_disposable_local.ps1 -Start
# En otra consola, desde $taskStack: supabase functions serve
supabase test db --local --workdir $taskStack
Invoke-RestMethod -Uri http://127.0.0.1:55321/functions/v1/compare-certificate-hash -Method Post -ContentType 'application/json' -Body '{"credential_code":"e42f105a-a36b-40de-8326-47da5749eae3","document_sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}'
# Finalmente, SOLO el stack devuelto:
supabase stop --no-backup --workdir $taskStack
```

CLI fijada 2.117.0: usar el binario disponible o npx supabase@2.117.0.
El preparador devuelve proyecto/config separados y copia las diez migraciones,
funciones y config nuevas. En un stack local existente que deba conservar datos,
el operador puede aplicar solo migraciones pendientes con `supabase migration up
--local --workdir RUTA_LOCAL` tras revisar el proyecto; aquí no se aplicó al habitual.

Preparado para un operador posterior; NO ejecutado remotamente en esta entrega:

```sh
# Verificar primero el vínculo existente al proyecto correcto.
supabase db push --linked --dry-run
supabase db push --linked
supabase functions deploy verify-certificate --project-ref PROJECT_REF
supabase functions deploy compare-certificate-hash --project-ref PROJECT_REF
```

Migración nueva 20261005120000_public_candidate_hash_comparison.sql primero;
publicar ambos endpoints después porque comparten public_handler.ts. Config
verify_jwt=false solo en los endpoints públicos respectivos; conservar JWT de
issue-certificate/certificate-pdf y no usar --no-verify-jwt global. Backend y Web
con decoder deben publicarse coordinadamente posteriormente. Fixtures destructivos,
comandos completos y distinción evidencia local/CI: [TESTING.md](TESTING.md).


## Endurecimiento y demo integral — 8D

El límite RPC se valida sin coerción: result es string de su enum; las claves
siguen cerradas. Las fechas aceptan años 0001–9999, calendario gregoriano real,
00–23:00–59:00–59, Z u offset ±00:00–23:59 y fracción opcional de 1–6 cifras.
No admite segundo intercalar, 24:00, año cero, fracción mayor ni salto final.
No normaliza ni redondea el valor, incluidos microsegundos. Una proyección RPC
inválida produce error técnico 503, nunca valid/not_found aceptados por coerción.
La ausencia exige integrity=unavailable; los registros verificables exigen match
o integrity_mismatch. Ambas validaciones están cubiertas en Deno y Flutter.

Una comparación fallida conserva explícitamente el resultado y checked_at
anteriores, muestra «Consulta anterior» y el error de la nueva operación. Nunca
los presenta como consulta reciente; una respuesta válida vuelve a «Comprobado».
Cambiar código, cancelar o salir aborta el transporte propio y descarta respuestas
antiguas. 429 deshabilita acciones hasta Retry-After; no consulta automáticamente:
el usuario reintenta. El E2E espera una ventana real completa y prueba esta acción.

El presupuesto global compartido de 60 POST/60 segundos incluye entradas inválidas.
Es suficiente para la demo actual; un usuario puede agotarlo para todos. Antes de
un lanzamiento público hay que diseñar protección contra abuso, cuotas y capacidad
sin incorporar PII innecesaria. No es un límite individual por usuario/IP.

La demo reproducible usa un stack nuevo con identidad/puertos propios, fuera del
checkout, y main.dart release con configuración pública válida y HTTPS loopback.
Auth, PostgREST, Edge y Storage son reales. TLS, service_role, SQL y fixtures quedan
en el host. El navegador recibe solo URL pública y anon key pública para las
operaciones privadas. Las consultas públicas utilizan credentials=omit incluso
con cookies en el mismo origen. [DEMO_VERIFICATION.md](DEMO_VERIFICATION.md) explica
preparación, ejecución y limpieza. Los harness 7D/8B/8C siguen como complementos.
# Ampliación vigente 9D

Producción Flutter consulta el endpoint independiente verify-certificate-v2,
schema_version='2', sin Auth/apikey/cookies. registry conserva v1 literal;
blockchain muestra evidencia y fecha/origen propios, con ausencia uniforme y
off_chain_only. No se modifican verify-certificate/compare-certificate-hash v1.
Los tres comparten presupuesto global atómico 60 POST/60 s y cooldown de UI.
Una comparación v1 trae su propio registro; evidencia de otro snapshot se marca
anterior. Fallo v2 jamás se sustituye por aparente confirmación v1.

Apertura autenticada en certificate-opening, compartición explícita y cálculo
H/K/C local con PDF <=8 MiB y JSON <=2 KiB. Nunca H/salt en API pública/enlaces/QR.
Estados/finality/deadlines/configuración y comandos completos:
[BLOCKCHAIN_VERIFICATION](BLOCKCHAIN_VERIFICATION.md),
[ADR-0017](adr/0017-public-blockchain-evidence-and-private-opening.md).
Los apartados de 8A–8D inferiores conservan contratos v1 e historia.
