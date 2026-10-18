# 10B — diagnóstico de Cache-Control anterior al handler

16/10/2026. Continuación de [la revisión 10B](PHASE10_ACCEPTANCE.md), en main/HEAD
`ae97f35859e20b470c4dbdde20a2cb84eff0aae0` con los cambios locales anteriores
preservados. No se ha corregido infraestructura alojada ni cerrado 10B.

## Reproducción observada, sin secretos

Entorno **local desechable**, API `http://127.0.0.1:55321`, Supabase CLI 2.117.0,
imagen `public.ecr.aws/supabase/edge-runtime:v1.74.3`. Petición exacta inocua,
sin apikey ni credenciales reales:

```powershell
curl.exe -i -X POST http://127.0.0.1:55321/functions/v1/revoke-certificate -H "Content-Type: application/json" -H "Authorization: Bearer invalid" --data "{}"
# Mismo rechazo sin token: ejecutar la petición sin el header Authorization.
```

Respuesta: HTTP **401**, `Cache-Control` **ausente**, header `sb-error-code`
`UNAUTHORIZED_INVALID_JWT_FORMAT`. Sin Authorization: HTTP **401**, Cache-Control
ausente y `UNAUTHORIZED_NO_AUTH_HEADER`. La misma prueba reproduce el problema
en `/functions/v1/revocation-progress` y `/functions/v1/reauthorize-revocation`.
El ejemplo solo funciona mientras el stack propio está arrancado; no apunta al
proyecto habitual ni a un proyecto remoto.

La ejecución ampliada del harness, iniciada a `2026-10-16T11:37:48.021Z`
(13:37:48 Madrid), atraviesa **Kong y el servicio principal real de la CLI**, sin
mock ni proxy añadido. Usa usuarios sintéticos y sesión de Auth por password.
El JWT expirado conserva algoritmo/kid/claims del token real y se firma mediante
el helper Node existente, que verifica primero su firma original. Claves y tokens
solo en memoria/pipes privados; no figuran en petición de ejemplo, logs o informe.

| Caso | Rutas verificadas | HTTP observado | Cache-Control |
|---|---|---|---|
| Sin token | Las tres privadas | 401 | ausente |
| Bearer invalid | Las tres privadas | 401 | ausente |
| JWT real firmado pero expirado | Las tres privadas | 401, UNAUTHORIZED_ASYMMETRIC_JWT | ausente |
| Sesión válida con JSON `{}` incompleto | Las tres privadas | 400 invalid_input | no-store |
| JWT de API anon, sin identidad de usuario | Las tres privadas | 401 unauthenticated del handler | no-store |
| Owner actual, consulta válida del certificado propio de fixture | revocation-progress | 200 | no-store |
| Sesión válida ajena, consulta del mismo certificado | revocation-progress | 404 revocation_unavailable | no-store |

**17/17 comprobaciones de autenticación/autorización y status: PASS.**
**9/17 respuestas incumplen no-store** (los tres primeros casos por ruta).
Resultado global del probe **FAIL**, exit 1 deliberado por el requisito pendiente.
Sesión válida con cuerpo incompleto comprueba llegada al handler, no una emisión
o reautorización exitosa; la consulta owner/ajeno comprueba la autorización SQL.
La reautorización funcional autorizada/denegada pertenece a la pasada anterior
documentada, no se cuenta como nueva ejecución de este probe.

Informe sanitizado: `mobile/build/phase10-evidence/gateway-probe.json`. Incluye
fecha, entorno, verify_jwt=true, status esperado/observado y códigos cerrados;
nunca bodies privados ni cabeceras Authorization. No sustituye result.json,
backend-only.json ni full.json anteriores. Cámara NOT_RUN, CERTICHAIN_TEST_CAMERA=0:
«Omitidas por instrucción del usuario; no hay cámara física disponible».

## Componente que responde y control disponible

Ruta local: cliente → Kong existente → **main service del Edge Runtime generado
por Supabase CLI** → worker/handler de CertiChain. El emisor del 401 es el main
service, no el handler y no la validación Auth adicional de CertiChain.

Se inspeccionó `/root/index.ts` del contenedor propio: la rama verifyJWT devuelve
el error antes de crear el user worker. Su constructor de error añade Content-Type
y sb-error-code, pero no Cache-Control. El bundle observado (texto UTF-8 leído
sin salto final) tuvo SHA-256
`45792be71a1497d1554aaa82e06cf65768e5438d4c11af2e608acebcc0abe3c6`.
Una solicitud directa desde el contenedor Kong al servicio `edge_runtime:8081`
también recibió 401. No se modificó ninguno de esos componentes.

Fuentes primarias fijadas y contraste documental:

- [CLI 2.117.0, serve.main.ts](https://github.com/supabase/cli/blob/v2.117.0/apps/cli/src/shared/functions/serve.main.ts):
  getResponse/getAuthErrorResponse, líneas 63–94; control verifyJWT, 299–316;
  creación del worker posterior. Coincide con el bundle cargado.
- [Plantilla Kong de la misma CLI](https://github.com/supabase/cli/blob/v2.117.0/apps/cli/src/commands/start/templates/kong.yml.ts):
  functions-v1 enruta a Edge Runtime; no añade Cache-Control a su respuesta.
- [Esquema de configuración 2.117.0](https://github.com/supabase/cli/blob/v2.117.0/apps/docs/public/cli/config.schema.json):
  función admite enabled, verify_jwt, import_map, entrypoint, static_files y env,
  con additionalProperties=false. edge_runtime tampoco ofrece cabeceras para
  errores JWT ni sustitución del main service. No hay un ajuste de ese tipo en
  supabase/config.toml. Las variables del handler y su entrypoint se aplican
  después de la comprobación JWT; cambiar sus headers no intercepta este 401.
- [Autenticación de Edge Functions](https://supabase.com/docs/guides/functions/auth):
  la plataforma valida JWT antes del handler con verify_jwt=true.
  [Referencia de configuración](https://supabase.com/docs/guides/local-development/cli/config#functions.function_name.verify_jwt).

**Alojado: NOT_RUN.** La documentación confirma la comprobación anterior al
handler, pero no demuestra las cabeceras de un despliegue alojado concreto. No se
han invocado endpoints remotos, usado credenciales remotas ni realizado despliegues.
No hay en la configuración revisada una opción para controlar ese error de la
infraestructura gestionada; no se afirma que el alojado tenga el mismo defecto.

## Impacto, requisito pendiente y opciones

El rechazo mantiene JWT y no concede acceso al handler ni a la decisión privada.
No se observó motivo, actor, documento, token ni dato del certificado en esos 401.
No se ha demostrado almacenamiento efectivo en caché o una fuga. El defecto
incumple la garantía explícita de no-store para todas las respuestas; no invalida
los PASS de autenticación, autorización, irreversibilidad e idempotencia.

Requisito pendiente: el componente que emite el rechazo JWT debe devolver
Cache-Control: no-store para token ausente, inválido y expirado, conservando 401 y
verify_jwt=true. La matriz HTTP debe pasar también contra el entorno objetivo
cuando exista una prueba remota autorizada, sin equiparar local y alojado.

Opciones, ninguna aplicada aquí:

1. Solicitar una corrección upstream del main service local; si una prueba
   alojada autorizada confirma el defecto allí, solicitarla a Supabase para esa
   capa gestionada. Evaluar una versión corregida y repetir la matriz antes de
   actualizar la CLI fijada. Una actualización local no cambia el servicio alojado.
2. En infraestructura autohospedada controlada, añadir la directiva en el main
   service o gateway **existente**, conservando toda validación JWT, y probar el
   camino HTTP público. Exige poseer esa configuración; no es un arreglo del
   proyecto alojado. No se parchea el contenedor efímero de la CLI para fabricar PASS.
3. Si producto decide aceptar una excepción limitada al 401 genérico previo al
   handler, documentar y aprobar expresamente el cambio de requisito/ADR. No se
   ha aceptado esa excepción ni se cierra 10B con ella.

No se añade un proxy: implicaría otra capa operativa y ruta pública, y no corregiría
la URL directa de Supabase. Para estos errores genéricos no se justifica ese
cambio de arquitectura como parte de 10B. Cambiar solo el handler o desactivar
verify_jwt tampoco resuelve el requisito en la capa responsable.

## Repetición focalizada y límites

Con Node 24.14.0 y SUPABASE_CLI 2.117.0 en PATH/configuración de proceso:

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
$env:CERTICHAIN_TEST_DISPOSABLE='1'
$env:CERTICHAIN_SOURCE_ROOT=(Get-Location).Path
$taskGatewayRoot=./supabase/tests/prepare_disposable_local.ps1 -Start
try {
  Push-Location -LiteralPath $taskGatewayRoot
  try {
    npx --yes deno@2.2.12 run --allow-all --frozen --config supabase/functions/deno.json supabase/tests/phase10_gateway_probe.ts
    # Exit 1 mientras falte no-store; consultar el informe sanitizado.
  } finally { Pop-Location }
} finally {
  ./supabase/tests/stop_disposable_local.ps1 -Root $taskGatewayRoot
}
```

El runner general conserva el gate estricto y reutiliza la matriz ampliada.
Esta ejecución focalizada no vuelve a acreditar SQL completo, EVM, Flutter o
10C–10E. Formato/lint/tipos se verifican sobre el harness modificado. No hay
corrección de producto, nueva migración, dependencia o proxy en esta continuación.
Fmt/lint/check --frozen, actionlint 1.7.12, enlaces locales y git diff --check:
PASS. Cleanup del runtime, contenedores y directorio propios: PASS; permanecen
solo los contenedores del stack habitual. El informe incorpora stack_cleanup=PASS.
