# Aceptación del MVP y cierre de 10E

Estado revisado el **30/10/2026**: **10E y la fase 10 están cerradas para la demo Web/Chrome con Supabase local y Anvil, con CI observada correcta**. Se elimina el antiguo pendiente de observar CI del commit de integración. Las limitaciones de plataforma, proveedor y lanzamiento continúan vigentes.

## Evidencia remota vigente

Consultados por API los runs, jobs y pasos del SHA exacto `3c892cde3d0d21316089b2f8b6bb94702ca6f36a`, del 30/10/2026:

| Workflow | Ejecución | Resultado |
|---|---|---|
| Complete certificate revocation | [41088795797](https://github.com/benjvm/certichain/actions/runs/41088795797) | completed / success |
| Blockchain verification client | [41088795783](https://github.com/benjvm/certichain/actions/runs/41088795783) | completed / success |
| Private durable anchoring | [41088795615](https://github.com/benjvm/certichain/actions/runs/41088795615) | completed / success |
| Blockchain registry | [41088795709](https://github.com/benjvm/certichain/actions/runs/41088795709) | completed / success |
| Database permissions | [41088795618](https://github.com/benjvm/certichain/actions/runs/41088795618) | completed / success; database, flutter y android |

El job de revocación `124176884833` ejecutó formato/lint/tipos, suites backend y Flutter, SQL/RLS, preservación histórica, recorrido release, parada del stack y finalización de evidencia. Los logs registran:

- 978 comprobaciones pgTAP y lint SQL sin errores.
- 272 tests backend Deno, sin fallos.
- 266 tests Flutter correctos y 12 omitidos.
- 183 aserciones del navegador de producto, `phase10-production-browser: PASS`.
- Aceptación `phase10-acceptance`, modo `full`, Flutter `PASS`.
- Finalización del run `9ae1375d-292c-4838-9a0e-019de5280690`: `result=PASS`, `stack_cleanup=PASS`, `flutter=PASS`.

Los datos anteriores acreditan ese SHA y el alcance ejecutado. La presente edición documental no dispara nuevos workflows ni equivale a validar futuras modificaciones de producto.

## Alcance aceptado

| Área | Comportamiento comprobado |
|---|---|
| Emisión y documento | Auth real, membresía vigente, institución verified, PDF privado e inmutable y acceso autorizado |
| Decisión de revocación | Owner/admin de emisora verified o suspended; SQL inmediato e irreversible, motivo privado e idempotencia |
| Fallos de respuesta | Recuperación de la misma decisión y clave sin repetir la revocación |
| Worker EVM | Firma externa a Flutter/Edge público, leases/fencing, ledger, nonces, replacements y reverts |
| Issue tardío | Reconciliación y compensación del issue firmado con la identidad original |
| Evidencia | Separación SQL/issue/revoke, receipts/eventos/bloques canónicos, reorg y divergencia |
| Recuperación | Restore privado PostgreSQL/Storage, bytes/identidad originales y no duplicación |
| Producto Web | Emisión, wallet, PDF, revocación, progreso, reautorización, apertura y cambio de sesión |
| Público | Consulta sin Auth, presupuesto compartido, QR estático/enlaces y comparación de PDF sin subirlo |
| Privacidad | Motivo/actor/hash/salt/ruta fuera de DTO público, QR, informes y logs |
| Informes | run_id, SHA/dirty, modo, fechas y cleanup; un PASS antiguo no acredita una pasada nueva |

202 significa decisión SQL aceptada, nunca confirmación EVM. Un RPC caído, reorg o rollback de aplicación no reactiva un certificado. `completed` describe publicación documental; no se redefine como confirmación blockchain. Contratos vigentes: [revocación](REVOCATION.md), [evidencia y apertura](BLOCKCHAIN_VERIFICATION.md) y [operación](BLOCKCHAIN_OPERATIONS.md).

## Cabeceras y excepción del proveedor

Las respuestas de los handlers CertiChain requieren `Cache-Control: no-store`, incluidos sus errores. La ausencia observada en ciertos 401 JWT genéricos anteriores al handler es un **FAIL del diagnóstico estricto**, aceptado únicamente bajo la excepción cerrada del usuario. No es una reparación de Supabase. Se mantienen `verify_jwt=true`, Auth real y autorización SQL.

La política comprueba ruta, escenario, estado, códigos y cuerpo genérico en memoria; cualquier error no reconocido falla. Detalle preservado en [SECURITY](SECURITY.md#excepción-del-gateway-jwt), [ADR-0018](adr/0018-irreversible-revocation-and-public-v3.md) y `supabase/tests/phase10_gateway_policy.ts`. Supabase alojado sigue NOT_RUN.

## Readiness JWT y fallo anterior de 9E

El [run 39659007204](https://github.com/benjvm/certichain/actions/runs/39659007204) del SHA `fe6581a` falló al esperar «Espacio institucional»: Auth respondió 200, `institution_members` y `certificates` devolvieron 401/PGRST303 y después `profiles` devolvió 200. El deadline fue posterior a esas lecturas fallidas. El log no retenía la categoría exacta del rechazo JWT; un reloj interno desactualizado es una hipótesis, no una causa probada de aquel run.

Los harnesses release comprueban Auth/SELECT propio después de compilar y antes de Chrome. Solo el mensaje exacto `401/PGRST303/JWT issued at future` permite hasta tres GET con esperas de 500/1000 ms. No se reintentan logins, mutaciones ni tráfico del navegador. La pasada 9E local del 30/10 terminó con 58 checks HTTP/Anvil/restore, 180 aserciones Web y cleanup correctos. La CI posterior de 9E del SHA `3c892cd` también terminó correctamente. En el run remoto 10E, readiness pasó al primer intento; no se afirma haber reproducido el error temporal.

## Límites y pendientes reales

| Comprobación | Estado |
|---|---|
| Web Chrome, Supabase local y Anvil | PASS en el SHA indicado |
| Android main.dart, compilación debug | PASS en CI; no acredita aceptación nativa completa |
| Diálogos/adaptadores de archivos Android | Aceptación estable pendiente; intermitencia histórica tras cancelación |
| Android app completa, iOS, Firefox y Safari | NOT_RUN como aceptación integral |
| Sepolia y finalidad PoS | NOT_RUN; Anvil usa `finality=not_applicable` |
| Supabase alojado, custodia y restore de producción | NOT_RUN |
| Accesibilidad humana y dispositivos físicos | NOT_RUN |
| Cámara y dobles de permisos/captura/ciclo | SKIP/NOT_RUN por instrucción del usuario |
| Protección para tráfico público y política legal de retención | Pendientes de diseño y validación |

`CERTICHAIN_TEST_CAMERA=0`. Motivo exacto: «Omitidas por instrucción del usuario; no hay cámara física disponible». La exclusión no afecta códigos manuales, enlaces, generación/decodificación de QR estático, PDF, Auth, permisos SQL ni blockchain.

El registro de reinicios de Vector del 18/10 era una observación operativa del host, separada del cleanup de los recursos propios. La CI actual acredita el cleanup de su runner; no verifica el estado actual de aquel servicio local ni lo presenta como reparado.

## Reproducción e informes

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1
# Sin acreditar Flutter:
./supabase/tests/run_phase10.ps1 -BackendOnly
```

Versiones, aislamiento y recorrido visible en [DEVELOPMENT](DEVELOPMENT.md) y [DEMO_BLOCKCHAIN_LOCAL](DEMO_BLOCKCHAIN_LOCAL.md). Suites mutables siempre secuenciales. Los JSON ignorados de `mobile/build/phase10-evidence/` incluyen `run`, `preflight`, `result`, `full`/`backend-only` y `browser`; deben compartir run_id/SHA/dirty y modo, con fechas compatibles. `history/<nuevo-run_id>/` y `attempts.ndjson` conservan ejecuciones previas. No publicar bodies, PDFs, dumps, aperturas, claves, tokens o raw transactions.

Los informes individuales de fases anteriores se retiraron de la documentación mantenida porque sus contratos y límites están consolidados aquí y en las guías técnicas. El historial de Git conserva las evidencias y los intentos históricos; no se transforman sus FAIL/NOT_RUN en PASS actuales.
