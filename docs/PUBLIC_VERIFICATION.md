# Verificación pública — Backend 8A e interfaz Web 8B

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

Docker, Node 22.14.0, Supabase CLI 2.117.0 y Deno 2.2.12; mismas versiones de CI.
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
- **8C pendiente:** escáner y comparación de una copia del PDF.
- **8D pendiente:** pruebas integrales y endurecimiento del recorrido completo.

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
apikey o cookies deliberadas, tablas privadas ni RPC técnicos. Deadline total
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
