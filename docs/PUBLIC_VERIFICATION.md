# Verificación pública — Fase 8A

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

## Incrementos posteriores

- **8B pendiente:** pantalla de verificación por código y adaptación al contrato,
  errores de red/límite y explicación del significado de resultados.
- **8C pendiente:** QR, enlaces navegables y escáner, con contratos de navegación
  y exposición voluntaria del código; sin publicar información privada.
- **8D pendiente:** comparación de PDF elegido, privacidad y recursos; pruebas
  integrales del recorrido pantalla/QR/copia y endurecimiento adicional.

Blockchain y revocación completa tienen sus propios incrementos. Antes de 8B:
mantener este v1, definir UX de issuer_unavailable/429/503 y decidir cómo el titular
obtendrá/compartirá su código con autorización. No ampliar el DTO por conveniencia.
