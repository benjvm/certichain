# Aceptación de revocación — Fase 10

## Aceptación final 10E — 18/10/2026

Base `main`, HEAD `fe237a0803dfd186c7f6c71034e8883dde787d61`, árbol inicial
limpio. Se acepta la integración de 10A–10D mediante el runner existente y
recursos sintéticos propios. Esta sección es el registro vigente; los apartados
inferiores conservan sus resultados históricos. **10E y la fase 10 quedan cerradas
localmente para la demo Web/Chrome/Supabase local/Anvil**, con la excepción 10B
y los límites explícitos de esta sección. No equivale a lanzamiento público.
No commit, push, merge o despliegue remoto.

Contratos verificados en código/configuración: CertificateRegistry/protocol v1,
endpoints públicos cerrados v1/v2/v3 y compare v1; cliente producto usa v3, sin
consultas a versiones adicionales para completar resultados. Privados
revoke-certificate/revocation-progress/reauthorize-revocation con verify_jwt=true
y Auth adicional. 202 acepta SQL irreversible; 200 recupera la decisión original.
Worker externo firma EIP-1559; Edge público solo lee y Flutter no firma.

### Cambios específicos de aceptación

Se reutilizan run_phase10.ps1, fixtures reales, suites 10B/10C, viaje de producto
main.dart release y workflow revocation.yml. Sin cambios de producto, endpoints,
coordinador, ABI, Solidity, esquema, RLS, migraciones o locks.

- Corregida atribución de informes: run_id UUID desde antes del bootstrap,
  started_at, SHA/dirty y modo compartidos por preflight/aceptación/navegador.
  Artefactos anteriores archivados; se rechazan navegador/preflight ajenos o
  anteriores. Un fallo temprano no puede reutilizar un PASS Web antiguo.
- Resultados iniciales NOT_RUN; finalización después de cleanup, exit real y
  comprobación del navegador actual. Un cleanup fallido hace FAIL. attempts.ndjson
  recibe la pasada finalizada una vez. CI limpia/finaliza antes de subir los JSON.
- Seis regresiones del mecanismo de evidencia: fallo temprano, éxito antiguo,
  identidad/fecha, finalización única, cleanup fallido y resumen ajeno.
- Matriz HTTP ampliada: solicitud owner/admin actuales de suspended, suspensión
  sin revocación automática y emisión denegada; writes_stopped en deployment
  original impide reautorización/firma sin alterar SQL ni auditoría.
- Privacidad pública contrasta también valores reales de motivo/actor/request_id,
  hash documental, salt y ruta, solo en memoria, sin guardarlos en informes.

Archivos: supabase/tests/{run_phase10.ps1,phase10_acceptance.ts,phase10_checks.ts,
phase10_deployments.ts,phase9e_preflight.mjs,phase10_evidence.mjs,
phase10_evidence.test.mjs}, mobile/tool/blockchain_verification_browser.mjs,
.github/workflows/revocation.yml y documentación PHASE10_ACCEPTANCE, REVOCATION,
ROADMAP, TESTING, SECURITY, BLOCKCHAIN_OPERATIONS, BLOCKCHAIN_VERIFICATION y
DEMO_BLOCKCHAIN_LOCAL. No nueva decisión estructural/ADR: siguen ADR-0016/17/18.

### Matriz de aceptación integrada

| Área | Evidencia reproducible en la pasada final | Estado |
|---|---|---|
| Base limpia e históricos | Migraciones al crear stack; 978 pgTAP antes de fixtures, lint y verify_revocation_migration rollback-only | PASS |
| Auth/gateway/permisos | Auth password real, Edge por Kong, roles vigentes verified/suspended; issuer/titular/ajeno/plataforma/pending/rejected denegados | PASS |
| Suspensión | No revoca automáticamente, owner/admin pueden solicitar, emisión 403 | PASS |
| Idempotencia y decisión | Concurrencia, claves/payload en conflicto, recuperación y atributos originales; completed/código/PDF intactos | PASS |
| Respuesta perdida real | 10B proxy retiene todos los bytes, SQL confirma commit, socket/consumidor abortados; misma clave recupera 200 | PASS |
| Progreso y reautorización | Snapshot SQL sin mutaciones al consultar; reautorización explícita autorizada/auditada y denegaciones | PASS |
| Sin anchor/issue unsigned/issue tardío | Cancelación fenced y compensación del firmado con K/I/C/S originales | PASS |
| Crash/broadcast/lease/CAS | Reprocesado durable, broadcast real con respuesta perdida, workers concurrentes/vencidos | PASS |
| Nonces/replacements/reverts | Unknown bloqueado; anterior gana entre tres replacements; revert consumido, reconciliación y rotación | PASS |
| Saldo/permisos/deployments | Saldo insuficiente, canIssue/canRevoke independientes, permiso retirado, anterior disabled y writes_stopped | PASS |
| Reorg/divergencia/restore | Issue/revoke separados, evidencia incompatible, reset y PG/Storage propios; SQL no se reactiva | PASS |
| Producto Web release | Emitir/PDF/wallet/revocar/confirmar/cancelar/misma clave/detalle/progreso/evidencia revoke | PASS |
| Público/privacidad | SQL revocado durante demora/RPC caído, recuperación, issue/revoke separados, sin datos privados | PASS |
| Compatibilidad/duplicados/documento | v1/v2/v3, código/enlace/QR estático, original/alterado y apertura sin inferir vigencia; exactamente un POST por arranque/recarga/navegación | PASS |
| Limpieza/atribución | Procesos/perfiles/TLS/temporales/Anvil/red/Edge/restore/stack propios; informe solo de esta ejecución | PASS |
| No-store aplicación | Todas las respuestas del handler, también errores | PASS |
| Gateway estricto | Ausencia externa de cabecera observada, nunca marcada como corregida | FAIL conocido, no bloqueante bajo política aceptada |
| Excepción 10B | Solo 401/códigos/cuerpo genéricos previos identificados; Auth/JWT intactos | PASS |
| Cámara | Captura/permisos/ciclo/getUserMedia/vídeo/probes nativos y dobles excluidos de forma acotada | SKIP/NOT_RUN |
| Alojado, Android completo/iOS, Firefox/Safari, Sepolia/PoS, accesibilidad humana | Sin evidencia propia nueva | NOT_RUN |

CERTICHAIN_TEST_CAMERA=0. Motivo exacto:
«Omitidas por instrucción del usuario; no hay cámara física disponible».
Se conservan QR de imagen estática, enlaces,
códigos manuales, PDF, Auth, SQL y blockchain. Anvil no acredita finalidad PoS.

### Comandos y evidencia nueva

Prerrequisitos/guion: [DEMO_BLOCKCHAIN_LOCAL](DEMO_BLOCKCHAIN_LOCAL.md).
Versiones fijadas comprobadas: Node 24.14.0; CLI 2.117.0; Deno 2.2.12; Flutter
3.47.4/Dart 3.13.3, revisión 9584c6713b324636289d067944a46fd6b49df14b; Foundry
1.8.5/Solidity 0.8.37. Docker y Chrome se registran desde los ejecutables actuales.
No se actualizan SDK o locks para conseguir verde.

| Ejecución local nueva | Resultado |
|---|---|
| run_phase10.ps1 final, run_id 11bc699b-f9a0-4b86-8ca8-df99c291b369 | PASS, 297 checks reales y cleanup propio PASS |
| main.dart release HTTPS, Chrome 155.0.8059.84 | PASS, 183 aserciones |
| Migraciones limpias/SQL/RLS, antes de fixtures | PASS, 978 pgTAP; preservación histórica y lint PASS |
| Flutter formato/análisis/tests | PASS, 143 archivos sin cambios; sin incidencias; 266 PASS/12 SKIP existentes |
| Backend Deno y política gateway | PASS, 272 pruebas |
| Contrato Foundry fmt/tests | PASS, 28 pruebas; ABI/build congelados sin drift |
| Node transporte/harness/evidencia/readiness | PASS, 33; 2 SKIP: cámara y fixture Unix en Windows |
| Deno formato/lint/tipos según workflow | PASS, 74/67 archivos formato/lint; tipos del entrypoint y dependencias |
| PowerShell parser, actionlint, enlaces locales, diff whitespace | PASS |
| Regresión independiente run_phase9c.ps1 | PASS, 163 checks reales, 978 pgTAP/lint y limpieza propia PASS |

Runner final iniciado 2026-10-18T18:12:06.785Z (20:12:06 Madrid), aceptación
18:14:19.446Z, navegador evaluado 18:18:56.988Z y finalización tras cleanup
18:19:08.783Z. Windows x64, Docker 29.8.2 y toolchains fijadas anteriores.
Todos los informes nuevos son dirty=true sobre fe237a08; no acreditan un commit
10E inexistente ni la ejecución remota del workflow modificado.

Una emisión/un anchor/tres aperturas en Web; dos POST revoke con la misma clave
(202 con cuerpo descartado y recuperación 200 de la decisión original). Ocho POST
públicos; página anónima v1=0/v2=0/v3=7/compare=0. Comparación con apertura original/
alterada local, QR estático y cambio/logout con respuesta privada retenida PASS.
La prueba 10B **distinta** demuestra interrupción de transporte después de commit
SQL independiente, sin recibir bytes: el descarte determinista Web no se presenta
como corte de socket del proveedor. No cambios de criterio o timeout para verde.

Auth/privacidad/no-store aplicación PASS. Matriz gateway de 17 casos: nueve
excepciones externas reconocidas; diagnóstico estricto Cache-Control FAIL,
política revisada PASS. Ausencia de cabecera **no corregida**, alojado NOT_RUN.
La primera pasada de esta revisión, run_id 35a9691c-e836-4473-9a28-6f52803bae82,
registró 289 checks/183 Web PASS antes de ampliar la matriz; está archivada bajo
history/11bc699b-f9a0-4b86-8ca8-df99c291b369. Ambos intentos conservados.
Una comprobación fmt inicial detectó CRLF en browser_harness.mjs del checkout;
se normalizaron finales de línea sin diff de contenido versionado y el gate final
completo pasó. No se atribuye ese intento inicial como PASS.

Preservación/limpieza final: ningún contenedor/red Anvil propio restante y los
once IDs de contenedores habituales coinciden. Diez servicios habituales,
incluidos PostgreSQL/Auth/Storage, conservan además StartedAt. La comparación
estricta de **todos** los StartedAt dio FAIL: Vector habitual cambia su arranque.
Se conserva ese resultado en mobile/build/phase10e-cleanup.json, no se reescribe
como PASS. Su mismo ID, política unless-stopped, contador 263 de reinicios,
eventos retenidos start/die con exit 0 y oom=false son compatibles con autoreinicio
del agente de logs; no se observaron stop/kill/destroy para ese ID en los eventos
retenidos. No se intervino ni se reparó el Vector habitual. Esta observación
operativa no es una revocación fallida ni un reset del stack por el runner;
queda como pendiente independiente del operador. La comprobación de identidad y
arranque de los diez servicios de datos/Auth/Storage, y cleanup propio, sí PASS.
La regresión independiente se ejecutó después del runner final, sin suites SQL
mutables simultáneas. Log phase10e-9c.log conserva 163 checks y limpieza propia.

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
# Node fijado en PATH, Docker operativo; runners mutables secuenciales:
./supabase/tests/run_phase10.ps1
./supabase/tests/run_phase9c.ps1
# Solo backend, no acredita Web:
# ./supabase/tests/run_phase10.ps1 -BackendOnly
npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions supabase/tests/phase10_gateway_policy_test.ts
node --test supabase/tests/phase10_evidence.test.mjs mobile/tool/browser_harness_test.mjs supabase/tests/edge_runtime_test.mjs blockchain/scripts/download.test.mjs blockchain/scripts/harness.test.mjs
node blockchain/scripts/forge.mjs fmt --check
node blockchain/scripts/forge.mjs test
Push-Location mobile
try {
  dart format --output=none --set-exit-if-changed lib test tool
  flutter analyze
  flutter test --reporter expanded
} finally { Pop-Location }
blockchain/.tools/actionlint/actionlint.exe .github/workflows/revocation.yml
git diff --check
```

fmt/lint/check adicionales usan exactamente los targets del workflow revisado.
Informes sanitizados mobile/build/phase10-evidence/{run,preflight,result,full,browser}.json:
run_id, SHA/dirty, versiones y fechas deben concordar. history/<nuevo-run_id>/
conserva el juego anterior; attempts.ndjson conserva cada finalización.
Los logs nuevos son mobile/build/phase10e-*.log; CI observada en phase10e-ci.json.

### CI observada del commit base

Lectura API GitHub, sin disparar ejecuciones. SHA exacto fe237a0803dfd186c7f6c71034e8883dde787d61,
intento 1, completed/success en los cinco workflows:
[revocación 39149038645](https://github.com/benjvm/certichain/actions/runs/39149038645),
[anclaje 39149038554](https://github.com/benjvm/certichain/actions/runs/39149038554),
[verificación 39149038632](https://github.com/benjvm/certichain/actions/runs/39149038632),
[contrato 39149038504](https://github.com/benjvm/certichain/actions/runs/39149038504),
[base de datos 39149038602](https://github.com/benjvm/certichain/actions/runs/39149038602).
Job de revocación 117738716013: todas sus etapas success, incluida release y
limpieza. Son CI del commit base 10D, no de los cambios locales de esta aceptación.
CI del futuro commit 10E pendiente; sin push ni escritura remota en esta tarea.

### Operador y límites del cierre

[Pasos MANUALES de revocación](REVOCATION.md) y
[diagnóstico/recuperación](BLOCKCHAIN_OPERATIONS.md): revisar backup/vínculo,
migraciones pendientes/dry-run y aplicar solo nuevas; desplegar los endpoints
con JWT; contrastar binding/I/signer/canRevoke/deployment vivo; worker con secretos
solo en host confiable; reconciliar todos los intentos y reautorizar explícitamente;
comprobar SQL/receipts/eventos/bloques canónicos y conservar historial. Ninguno de
esos pasos remotos se ejecutó. Rollback de app no revierte una decisión SQL.
El cierre local/Web no equivale a lanzamiento público ni valida las plataformas
NOT_RUN de la matriz. La exclusión de cámara no bloquea el alcance autorizado.

## Revisión específica 10D — 18/10/2026

[Cambios, evidencia nueva y límites del cliente](PHASE10D_ACCEPTANCE.md).
Base bb17d346: normalización Unicode, recuperación, permisos/sesión, fecha SQL
del titular y evidencia issue/revoke anterior sin consultas duplicadas. No cambia
backend/contratos 10A–10C. Los resultados inferiores son históricos y no acreditan
esta revisión ni la aceptación pendiente de 10E.
**10D cerrada localmente para Web/Chrome:** 266 Flutter PASS (12 SKIP), análisis/
formato limpios, 289 checks reales, 978 pgTAP y 183 aserciones release Web PASS;
cleanup propio PASS. Primer intento integral FAIL conservado. CI nueva pendiente.

## Revisión específica 10C — 18/10/2026

La revisión backend sobre `d63014e` reutiliza el coordinador/ledger existentes.
Corrige validación previa a promoción de receipts, observación de reverts
consumidos y retirada de atribución canónica en divergencia. Añade una migración
avanzada, sin tocar las compartidas, contratos públicos o Flutter.
Resultados nuevos y dictamen independiente: [PHASE10C_ACCEPTANCE](PHASE10C_ACCEPTANCE.md).
**10C cerrada localmente:** 289 checks reales de fase 10, 163 de emisión/ledger,
978 pgTAP en cada runner, 272 Deno y 28 Foundry PASS; limpieza propia PASS.
Migración nueva `20261018120000_revocation_evidence_reconciliation.sql`.
Los resultados inferiores de 10B/10D/10E son históricos; no se vuelven a aceptar
esas fases en esta revisión ni se reabre la excepción JWT limitada de 10B.

## Revisión y requisito vigentes — 18/10/2026

Base main/HEAD `741b3a02f5f72e69e7cb790c1806a8e00057ce14`, árbol inicial limpio.
Los cambios locales de esta revisión se identifican como dirty=true; no se han
publicado ni desplegado. Se aplica la excepción explícita de
[ADR-0018](adr/0018-irreversible-revocation-and-public-v3.md) y
[PHASE10B_GATEWAY](PHASE10B_GATEWAY.md): no-store obligatorio para los handlers;
solo el 401 JWT genérico previo reconocido puede carecer de la cabecera. La
observación estricta continúa FAIL y no se atribuye una corrección a Supabase.

CI consultada para ese SHA: [revocación, run 39130026892](https://github.com/benjvm/certichain/actions/runs/39130026892),
job 117683117339, 251 escenarios PASS y uno FAIL en el gate estricto del gateway;
Flutter Web de aceptación NOT_RUN, aunque los tests Flutter previos pasaron.
[Anclaje, run 39130026918](https://github.com/benjvm/certichain/actions/runs/39130026918),
job 117683117039, falló en bootstrap con 403 de la release API de Solidity. Esos
logs no incluyen evidencia para afirmar rate limit; etapas posteriores NOT_RUN.
Ambos FAIL históricos se conservan. La CI del próximo commit queda pendiente;
las comprobaciones locales nuevas se registran aparte más abajo.

Cambios de este incremento: política/DTO de evidencia y regresiones del harness,
gate de aceptación, transporte del bootstrap y sus cuatro workflows consumidores.
No hay nueva migración, cambios de handlers, SQL, ABI, Solidity ni dependencias.
Auth real, permisos vigentes, decisión irreversible, alias/idempotencia y PDF/
publicación completed se conservan. La revisión siguiente de 10C corresponde a
firmas durables, reconciliación previa, lease/CAS/nonces, reorg, issue tardío y
obligaciones por deployment.

Archivos modificados: `supabase/tests/phase10_backend.ts`,
`phase10_gateway_probe.ts`, `phase10_acceptance.ts`; nuevos
`phase10_gateway_policy.ts` y `phase10_gateway_policy_test.ts` en ese directorio.
`blockchain/scripts/bootstrap.mjs` reutiliza los nuevos `download.mjs` y
`download.test.mjs`. Workflows `anchoring.yml`, `revocation.yml`, `verification.yml`
y `blockchain.yml`; README blockchain, PHASE10B_GATEWAY, esta aceptación,
REVOCATION, SECURITY, TESTING, ROADMAP y ADR-0014/0018. Sin migraciones nuevas.

## Ejecuciones locales nuevas — 18/10/2026

Todas sobre HEAD 741b3a0 con cambios de esta revisión (dirty=true), Windows x64,
Node 24.14.0, Deno 2.2.12, Supabase CLI 2.117.0, Docker 29.8.2, Foundry 1.8.5 y
solc 0.8.37. Flutter 3.47.4/Dart 3.13.3/revisión fijada en modo integral.

| Comprobación realmente ejecutada | Resultado nuevo |
|---|---|
| Probe gateway real, inicio 13:29:46.108Z | 17 Auth/permisos PASS; aplicación no-store PASS; privacidad PASS; nueve excepciones; diagnóstico estricto FAIL; política revisada PASS; cleanup PASS |
| `run_phase10.ps1 -BackendOnly`, aceptación desde 13:31:55.58Z | PASS, 256 escenarios; Flutter NOT_RUN; cleanup PASS |
| `run_phase10.ps1`, aceptación desde 13:36:23.216Z | PASS, 256 escenarios + Web release; cleanup PASS |
| Web release main.dart, evaluado 13:39:47.048Z | PASS, 177 aserciones, Chrome 155.0.8059.84 |
| `run_phase9c.ps1`, integración independiente de anclaje | PASS, 163 comprobaciones reales Auth/Edge/Storage/Anvil; 970 pgTAP, lint y cleanup propios PASS |
| SQL en ambos runners 10 | 970 pgTAP por ejecución; lint y preservación de históricos PASS |
| Deno funciones + política nueva | 252 PASS, cero FAIL (19 de política) |
| Descargas Node + harness blockchain | 10 PASS (8 transporte + 2 existentes) |
| Harness navegador + readiness Edge | 17 PASS, 2 SKIP: cámara y fixture ejecutable Unix en Windows |
| Flutter formato/análisis/tests | 141 archivos sin cambios; sin incidencias; 241 PASS, 12 SKIP de cámara |
| Foundry formato/tests | PASS, 28 casos; fuzz 512 y campaña de invariantes 128×64 |
| Bootstrap real local sin token | PASS: tags, digest/checksums oficiales, SHA-256 y archivos instalados verificados |
| Build normal, ABI/artefactos congelados y ABI backend | PASS, sin drift |
| Deno fmt/lint/check (incluido JS con ts-check), actionlint cuatro workflows, enlaces locales, git diff --check | PASS |

Timestamps UTC; los JSON exactos prevalecen sobre los segundos redondeados del
texto. Informes sanitizados en `mobile/build/phase10-evidence/`: gateway-probe.json,
backend-only.json, full.json y browser.json. attempts.ndjson conserva pasadas y
history conserva copias previas a esta revisión; no se reescriben los FAIL del
16/10 como PASS. La tabla describe estas ejecuciones nuevas exclusivamente.

Web: una emisión, un anchor, una revocación, dos aperturas, siete POST públicos;
página anónima v1=0/v2=0/v3=6/compare=0. QR de imagen estática, comparación del
PDF original/alterado, apertura privada, outage RPC, refresh explícito, cambio de
cuenta y logout PASS. El build release no contiene secretos backend. PDF exacto,
publicación completed/código/evidencias, decisión irreversible y alias/idempotencia
se conservan también en las pruebas de pérdida de transporte y concurrencia.

La aceptación backend y la integral muestran Auth/privacidad/aplicación PASS y
nueve rechazos genéricos con no-store ausente: aceptación revisada PASS, diagnóstico
estricto FAIL. Alojado, Android/iOS, Firefox/Safari, Sepolia/finalidad PoS y revisión
humana NOT_RUN; no se amplía su evidencia. Cámara SKIP/NOT_RUN en todas las pasadas:
«Omitidas por instrucción del usuario; no hay cámara física disponible».

**Dictamen: 10B cerrada localmente bajo el requisito revisado autorizado.** La
limitación externa sigue visible; no se afirma haber corregido Supabase alojado.
10C conserva implementación y regresiones ejecutadas; su siguiente revisión
específica debe auditar firmas durables/replacements, reconciliación, lease/CAS,
nonces, reorg, issue tardío y obligaciones por deployment. No hay nueva auditoría
formal de 10C ni despliegue, push, merge o cambios remotos. La CI de estos cambios
está pendiente del próximo push; los dos runs FAIL de 741b3a0 siguen siendo la CI
observada para ese SHA.

## Continuación: diagnóstico del gateway — 16/10/2026

[Prueba, componente responsable, impacto y opciones](PHASE10B_GATEWAY.md).
Probe focalizado nuevo, inicio 11:37:48 UTC / 13:37:48 Madrid: **17/17 checks de
autenticación/autorización/status PASS; 9 respuestas sin no-store; global FAIL**.
Sin token, inválido y expirado: 401 sin Cache-Control en las tres rutas, emitidos
por el main service generado por CLI antes del user worker. Sesión válida llega
al handler (400 con cuerpo incompleto); progreso owner 200 y ajeno 404, no-store.
verify_jwt=true conservado, sin cambios de producto/configuración, nuevo proxy o
migración. No hay ajuste soportado en la CLI fijada para esa cabecera; alojado
NOT_RUN, sin extrapolarle el resultado local. Informe gateway-probe.json separado
de las pasadas siguientes. El cierre estricto 10B sigue pendiente.

## Revisión exclusiva 10B — 16/10/2026

Base local `main`, HEAD `ae97f35859e20b470c4dbdde20a2cb84eff0aae0`, árbol inicial
limpio. El commit ya incluye implementaciones 10A–10E. Esta revisión reutiliza
sus endpoints/tablas/RPC/ledger; no vuelve a implementar 10C–10E ni transforma
los resultados del 15/10 en evidencia nueva. Sin commit, push, merge, despliegue,
fondos/claves reales, acceso remoto o reset del stack habitual.

Existían Auth real, verify_jwt=true, actor del ID autenticado, permisos SQL
owner/admin actuales de emisora verified/suspended bajo el orden de bloqueos
existente, decisión irreversible, alias institucionales y reautorización auditada
de revoke. La integración ampliada detectó que blockchain_lock lanza 22023 para
una operación inexistente: el endpoint de reautorización lo presentaba como 503
en vez del 404 uniforme. Se añade exclusivamente la migración
`20261016110000_revocation_reauthorization_unavailable.sql`: traduce esa ausencia
a PT404 en la RPC de revocación y conserva todos los demás bloqueos/guards.
Las dos migraciones compartidas del 15/10 permanecen intactas.

Corregido: handler selecciona y valida los seis campos del DTO y los dos de cada
elemento synchronization; descarta añadidos privados, rechaza RPC malformada con
503 cerrado y conserva null históricos. Solo una solicitud con `created=true`
válido devuelve 202. Se rechaza el salto final antes aceptado por `$` en UUID,
manteniendo la normalización de mayúsculas; deadline del cuerpo pasa a 503.
No cambian la normalización del motivo ni su huella autoritativa SQL.

La nueva prueba de transporte tiene barrera del harness: recibe/retiene la
respuesta real Edge, confirma commit desde otra conexión SQL y aborta el socket
del consumidor antes de entregarle bytes. Reintenta y compara decisión, fecha,
motivo, alias, operaciones y PDF exacto. No hay sleeps ni fallos en producción.
HTTP y RPC SQL directa contrastan NFC, LF, trim y límites de puntos Unicode.
Se añaden casos reales de sesión, pérdida de membresía, progreso sin mutaciones,
reautorización denegada/autorizada y concurrencia con un anchor firmado.

**Incumplimiento detectado:** el gateway JWT de Supabase CLI 2.117.0 devuelve
401 sin Cache-Control antes de ejecutar el handler. Medición local independiente
2026-10-16T10:49:12.369Z (12:49:12 Madrid): las tres rutas devolvieron
`status=401, cache_control=null`. Evidencia sanitizada local:
`mobile/build/phase10-evidence/10b-gateway-cache.json`. El gate del runner exige
no-store también allí y falla; no se acepta una excepción ni se desactiva JWT.
El código de los handlers no puede añadir cabeceras a una respuesta emitida antes
de invocarlos. Corresponde corregir/verificar esa cabecera en la infraestructura
gateway, sin cambiar verify_jwt/Auth, contratos públicos, dependencias o Solidity.

La aceptación histórica inferior se conserva literalmente. El cierre estricto
**10B sigue pendiente** de ese requisito HTTP extremo a extremo. La revisión
posterior 10C corresponde a firmas durables, autorización al firmar/reemplazar,
reconciliación previa, lease/CAS/nonces, issue tardío, reorg y obligaciones por
deployment; esta pasada backend no acredita Flutter/10D ni aceptación Web/10E.

Archivos del incremento: functions/revoke-certificate/handler.ts y handler_test.ts;
tests/phase10_backend.ts (nuevo), phase10_checks.ts, phase10_acceptance.ts,
revocation.test.sql, verify_revocation_migration.ps1 y la migración correctora
indicada; se reutiliza issuance_hardening.mjs sin modificarlo, en Node
24.14.0 con pipes privados, porque el shim crypto de Deno no verificó el JWT ES256;
.github/workflows/revocation.yml (fmt/lint de la cobertura nueva); esta aceptación,
REVOCATION, SECURITY, TESTING y ROADMAP. ABI/Solidity, app y permisos intactos.

### Resultados nuevos observados

Windows, Node 24.14.0, Supabase CLI 2.117.0, Deno 2.2.12, Docker 29.8.2,
Foundry 1.8.5/Solidity 0.8.37; sin actualizar toolchains o dependencias. Pasada
final backend-only iniciada `2026-10-16T10:59:31.726Z` (12:59:31 Madrid), HEAD
ae97f358… con cambios locales. `mobile/build/phase10-evidence/backend-only.json`
y result.json: **FAIL**, **251 escenarios PASS y 1 FAIL**, exclusivamente el gate
de no-store del gateway; las tres observaciones son 401/cache_control=null.
full.json histórico no se reemplaza. attempts.ndjson conserva los intentos.

| Comprobación ejecutada en esta revisión | Resultado |
|---|---|
| SQL/RLS completo, incluida nueva regresión de operación ausente | PASS, 970 comprobaciones |
| Aplicación de la migración nueva en stack propio | PASS; migraciones compartidas intactas |
| Preservación histórica rollback-only, incluidas las tres migraciones | PASS; fecha/auditoría/elegibilidad/documentos conservados |
| Lint SQL public/certichain_private | PASS, sin errores |
| Suite Deno de todas las funciones | PASS, 233; 133 del handler compartido de revocación |
| Deno fmt/lint/check --frozen de funciones y harness afectados | PASS |
| Node browser_harness_test + edge_runtime_test | 17 PASS, 2 SKIP: cámara y fixture exclusivo Unix en Windows |
| Auth/Edge/SQL/Storage/Anvil reales con run_phase10.ps1 -BackendOnly | 251 PASS / 1 FAIL; resultado global FAIL, no aceptación parcial disfrazada |
| Recuperación con corte real después del commit; canonicalización HTTP/SQL; alias; PDF/completed | PASS |
| Auth expirado/inválido/anónimo; eliminado/bloqueado; caída y recuperación Auth | PASS en las tres rutas; caída → 503/no-store |
| Permisos por rol/institución y pérdida de membresía, progreso sin mutaciones, reautorización y carreras SQL | PASS |
| Regresiones existentes faults/concurrency/deployments ejecutadas por el runner | PASS; no equivalen a nueva aceptación integral 10C–10E |
| Gateway JWT previo al handler | FAIL en tres rutas: 401 sin no-store |
| Limpieza propia y comprobación de contenedores restantes | PASS; solo stack habitual, sin reset |
| Actionlint 1.7.12, parser PowerShell, enlaces Markdown locales, git diff --check | PASS |

Las comprobaciones posteriores al gate del runner (incluido su reset final de
Anvil), Flutter/Web, Android/iOS, Safari/Firefox, Sepolia, CI nueva y validación
humana: NOT_RUN; sin atribuirles resultados históricos como ejecución nueva.
No se ejecutó la suite completa independiente 9C/Foundry; sí el build/ABI
congelados y las regresiones reales anteriores del runner indicadas arriba.

Intentos intermedios conservados como FAIL: copia de una aserción SQL provisional;
uso de Buffer implícito de Node desde Deno en el fixture PDF (se reutilizó el
adaptador existente); deadline mutable del worker reutilizado en el harness;
verificación ES256 del helper Node ejecutada desde Deno (probe aislado también
FAIL; resuelto ejecutando el helper intacto con Node); y 503 de operación ausente
(corregido con migración nueva). Ninguno se cuenta retroactivamente como PASS.

Comandos ejecutados desde raíz: `./supabase/tests/run_phase10.ps1 -BackendOnly`;
`npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions`;
Deno fmt --check/lint de supabase/functions y phase10_backend/checks/acceptance;
Deno check --frozen de esos entrypoints, phase10_acceptance y admin/blockchain;
`node --test mobile/tool/browser_harness_test.mjs supabase/tests/edge_runtime_test.mjs`;
actionlint de revocation.yml, parser PowerShell de verify_revocation_migration.ps1,
enlaces locales y `git diff --check`. El runner ejecutó SQL, preservación y lint
contra su propio stack desechable. El probe Auth adicional también limpió el suyo.

Cámara SKIP/NOT_RUN, CERTICHAIN_TEST_CAMERA=0:
«Omitidas por instrucción del usuario; no hay cámara física disponible».

## Evidencia histórica del 15/10/2026

15/10/2026. Base/HEAD inicial y remoto main reconsultados:
`bb2a93c61950f258136bc88d4b9ad44b46848fc5`, árbol inicial limpio. Cambios locales
sin commit/push/merge/despliegue remoto ni datos reales. **Revocación completa aceptada para demo Web local**, con los límites enumerados. CI de fase 10 NOT_OBSERVED
hasta observar el SHA que contenga estos cambios. Los cuatro success de fase 9
(38645390011/38645389979/38645389971/38645389759) acreditan solo la base.

## Entrega verificable 10A–10E

| Incremento | Implementación |
|---|---|
| 10A | Migración nueva 20261015100000: decisión y alias privados, guard irreversible/identidad, autorización owner/admin verified/suspended, transición SQL inmediata, cancelación unsigned y outbox por todos los anchors |
| 10B | revoke-certificate, revocation-progress, reauthorize-revocation; Auth real, JWT, contrato cerrado acotado, idempotencia y auditoría; no-store y denegaciones uniformes |
| 10C | Coordinador, autorización SQL, persistencia/recuperación de revoke; canRevoke, eventos y C/I canónicos; issue tardío esperado, nonces/reverts/rotación/reorg sin reactivar SQL |
| 10D | Feature revocation/domain/data/presentation; motivo privado/confirmación, recuperación manual y barreras de sesión; wallet/detalle y público v3 con fechas y evidencia issue/revoke separadas |
| 10E | Runner propio run_phase10.ps1, SQL/preservación antes de fixtures, Auth/Storage/Edge/Anvil reales y main.dart release HTTPS; pruebas de fallos, regresiones y revocation.yml congelado |

Migración pública nueva 20261015110000 añade snapshot v3 en una sentencia.
V1/v2 cerrados conservados, sin salts/actor/motivo público ni nuevo enum público.
Contrato/ABI/build 9B y dependencias de producto intactos. [ADR-0018](adr/0018-irreversible-revocation-and-public-v3.md)
y [REVOCATION](REVOCATION.md) detallan política, campos, errores y pasos MANUALES.

## Evidencia ejecutada (actualizable al terminar la pasada)

Windows x64, PowerShell, Node 24.14.0 (PATH de tarea, sin cambiar instalación),
Supabase CLI 2.117.0, Deno 2.2.12, Docker 29.8.2, Foundry 1.8.5/Solidity 0.8.37,
Flutter 3.47.4/Dart 3.13.3 revisión 9584c6713b324636289d067944a46fd6b49df14b.

| Ejecución observada | Resultado |
|---|---|
| SQL/RLS con migraciones nuevas y regresiones | PASS: 925 comprobaciones, sin relajar aserciones |
| Lint public/certichain_private | PASS sin errores |
| Preservación de migración sobre históricos activos/revocados | PASS en transacción rollback-only propia, sin inventar auditoría/identidad/elegibilidad |
| Deno funciones completas | PASS: 115 tests; tipos/lint y formato se verifican separadamente |
| Node browser/Edge harness | PASS: 17; SKIP cámara con motivo exacto y fixture Unix en Windows |
| Flutter phase10 dominio/adaptadores/widgets | PASS: 13; analyze sin incidencias en última ejecución |
| Flutter suite completa, cámara=0 | PASS: 241, 12 exclusiones existentes (cámara/opt-in local); formato de 141 archivos sin cambios y analyze sin incidencias |
| Foundry contrato intacto | PASS: 28, incluidos fuzz e invariantes 128×64; fmt --check |
| Regresión real 9C sobre migraciones finales | PASS: 163 checks, incluidos tres replacements y ganador antiguo, ledger perdido, reorg, rotación/revert y reset; SQL/lint previos y cleanup PASS |
| Última aceptación integral Web | **PASS**: 182 checks backend/SQL/HTTP/Anvil/restore y 177 aserciones Web, Chrome 155.0.8059.41; cleanup propio PASS |
| Última backend-only con dos deployments reales | **PASS**: 189 checks, mismas regresiones SQL/preservación/lint y cleanup; Flutter NOT_RUN, sin reemplazar full.json |
| Flutter regresiones phase9d/verificación | PASS: campaña focalizada 76 incluida fase10 inicial |
| Flutter regresiones instituciones/wallet/detalle/emisión | PASS: 70 incluidas seis pruebas fase10; análisis anterior tenía dos avisos de llaves, corregidos y reanalizados |
| Backend real inicial | PASS: 129 checks; no acredita Flutter ni nuevas ampliaciones posteriores |
| Recorrido Web real de segunda pasada | PASS: 173 aserciones, incluida SQL→revoke EVM→evidencia anónima |
| Resultado integral de esa pasada | FAIL después de navegador: deadline temporal del adaptador reutilizado por una inyección de fallo. Corregido aislamiento del harness; exige nueva pasada completa |
| Actionlint y sintaxis PowerShell | PASS local; no equivalen a Actions |

Se conservan intentos en mobile/build/phase10-evidence/attempts.ndjson. Primera
pasada Web falló buscando etiqueta/hash en un mismo texto seleccionable; se
separó el rótulo visible conforme al panel existente. Un fixture SQL inicial
cambió estado institucional sin claims de plataforma: falló; corregido usando
la autorización existente. Un fmt encontró os error 1224 y se repite al liberar
el archivo. Ninguno de esos intentos se transforma retroactivamente en PASS.

## Matriz de aceptación real

phase10_checks cubre owner/admin, verified/suspended, issuer/titular/ajeno/
plataforma/anon/pending/rejected, idempotencia/concurrencia/respuesta perdida,
off-chain/cancelación unsigned, firmas issue tardías, canIssue=false/canRevoke=true,
baja de miembro y reautorización auditada, RPC detenido, reorg real issue/revoke,
preservación de PDF/apertura, históricos y ausencia de motivo público.

phase10_faults cubre crashes de revoke antes de persistir firma, después de
persistir/broadcast/receipt, proceso CLI nuevo, CAS vencido, firma durable después
de perder membresía, saldo, nonce desconocido sin saltos, deployment disabled y
writes_stopped, permiso retirado, revert consumido, rotación con otra EOA y receipt
issue incompatible con revoke. phase10_deployments comprueba contrato nuevo real mientras hay issue firmado en el
anterior deshabilitado, sin redirigir firmas ni crear salts. phase10_concurrency añade barreras SQL reales para
ambos órdenes de revocación/baja de miembro. La pasada completa ejecutó checks/faults/concurrency. La pasada backend-only
posterior ejecutó además la prueba de dos deployments reales: PASS sin atribuirla
al Web previo.

El navegador reutiliza el arranque Chrome/readiness/CDP aislado de fase 9. Cuenta
v1/v2/v3/compare por pathname y POST; comprueba una consulta pública al arrancar/
recargar, incluidos duplicados tardíos y mezclados. Mantiene QR de imagen estática,
comparación PDF/apertura local, Auth, Storage y respuesta real retenida tras logout.
Worker externo al cliente; claves solo en host. No capturas de apertura ni
secretos/PDF/H/S/raw/JWT/capacidades/dumps en los resúmenes.

## Reproducción y límites

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1
# Solo backend, no acredita Flutter:
./supabase/tests/run_phase10.ps1 -BackendOnly
```

SQL y preservación preceden fixtures mutables. Cada runner usa stack Supabase,
Anvil, red, procesos, perfiles Chrome y temporales propios. finally detiene solo
esos recursos; el entorno habitual no se resetea. Las pasadas completas
anteriores y la última satisfactoria limpiaron sus stacks/directorios. El stack backend inicial también
se detuvo y retiró. Cleanup de las pasadas finales Web y backend-only: PASS; stacks, Anvil, redes y
temporales propios retirados, con entorno habitual preservado.

Android archivos conserva la incidencia 9E (última aceptación nativa estable FAIL);
no se atribuye corrección. Android app completa, iOS, Safari, Firefox, Sepolia/
finalidad PoS y accesibilidad humana NOT_RUN sin evidencia propia. Anvil usa
not_applicable. No lanzamiento público ni custodia/restore remoto acreditados.
Cámara, incluidos dobles de permisos/captura/ciclo de vida, **SKIP/NOT_RUN**:
«Omitidas por instrucción del usuario; no hay cámara física disponible».

La pasada integral satisfactoria identifica HEAD bb2a93c6… y dirty=true, inicio
2026-10-15T18:31:58.486Z. full.json conserva 182 checks y browser.json 177
aserciones; una publicación, un anchor, una revocación, dos aperturas y siete
POST públicos. Página anónima: v1=0/v2=0/v3=6/compare=0. La siguiente pasada
backend-only no reemplaza esa evidencia Web. Backend-only posterior: inicio
2026-10-15T18:37:27.886Z, 189 checks, PASS, stack_cleanup=PASS. El navegador
final se evaluó a las 18:34:59.362Z (20:34:59 en Madrid).

**Dictamen: revocación completa aceptada para demo Web local.** No equivale a
lanzamiento público. CI del SHA futuro, Android archivos/app completa, iOS,
Safari/Firefox, Sepolia/finalidad PoS y accesibilidad humana conservan sus límites.

## Archivos y comandos de validación

Nuevos: ambas migraciones indicadas; functions/revoke-certificate,
revocation-progress, reauthorize-revocation y verify-certificate-v3; feature Flutter
revocation y parser/panel público; phase10_checks/faults/concurrency/deployments/
acceptance, revocation.test.sql, verify_revocation_migration.ps1, run_phase10.ps1;
phase10_test y phase10_adapters_test; revocation.yml; REVOCATION y ADR-0018.
Integración en main/app/workspace/wallet, coordinador/adaptador/puerto, handler v2
con selector explícito v3, harness y contadores, configuración y documentos
ROADMAP/SECURITY/TESTING/SECURE_ISSUANCE/PUBLIC_VERIFICATION/BLOCKCHAIN_OPERATIONS/
BLOCKCHAIN_VERIFICATION/DEMO_BLOCKCHAIN_LOCAL; historia 9E preservada.

Comandos realmente ejecutados desde raíz (Flutter desde mobile):

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1
./supabase/tests/run_phase10.ps1 -BackendOnly
./supabase/tests/run_phase9c.ps1
npx --yes deno@2.2.12 fmt --check supabase/functions supabase/tests/phase10_acceptance.ts supabase/tests/phase10_checks.ts supabase/tests/phase10_faults.ts supabase/tests/phase10_concurrency.ts supabase/tests/phase10_deployments.ts
npx --yes deno@2.2.12 lint supabase/functions supabase/tests/phase10_acceptance.ts supabase/tests/phase10_checks.ts supabase/tests/phase10_faults.ts supabase/tests/phase10_concurrency.ts supabase/tests/phase10_deployments.ts
npx --yes deno@2.2.12 check --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts supabase/tests/phase10_acceptance.ts supabase/functions/verify-certificate-v3/index.ts supabase/functions/revoke-certificate/index.ts supabase/functions/revocation-progress/index.ts supabase/functions/reauthorize-revocation/index.ts
npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions
node --test mobile/tool/browser_harness_test.mjs supabase/tests/edge_runtime_test.mjs
node blockchain/scripts/forge.mjs fmt --check
node blockchain/scripts/forge.mjs test
# Desde mobile:
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

Además: actionlint 1.7.12 de los cinco workflows, parser PowerShell de los dos
scripts nuevos, enlaces Markdown locales y git diff --check. Los runners ejecutan
pub/npm congelados, decoder --check, build normal/ABI congelado, SQL, preservación,
lint y aceptación. No se han actualizado SDKs/locks/dependencias ni migraciones
compartidas. La incidencia de formato 1224 se resolvió y el último check pasó.
