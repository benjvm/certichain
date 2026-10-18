# Fase 10C — sincronización EVM de la revocación

Revisión local del 18/10/2026. Base `main`, HEAD
`d63014ea84a5d9a4b1ee4294407bb59dadfc5b32`, árbol inicial limpio; cambios de esta
revisión sin commit/push. Las evidencias de 10A/10B y del 15/10 son históricas.
Se conserva la excepción JWT limitada de [10B](PHASE10B_GATEWAY.md).

## Implementación reutilizada y correcciones

Ya existían decisión SQL irreversible, obligaciones por anchor/deployment,
cancelación de issue sin firma con fencing, compensación del issue firmado,
puerto BlockchainRegistry, adaptador EIP-1559, worker externo, ledger de nonces,
leases/CAS, replacements, reautorización auditada y observación de reorgs.
No se reconstruyen esos componentes ni se cambian contratos públicos o Flutter.

Se corrigen cuatro puntos del recorrido existente:

- Validar nonce del intento y estado C/I/revocación tanto en inclusión como en
  head **antes** de persistir el receipt y liberar la reserva. La comprobación
  anterior de C/I de revoke ocurría después de esa promoción. Issue también
  valida su estado en head antes de promoverlo; la excepción para issue tardío
  solo admite identidad compatible con compensación existente.
- Refrescar la observación de un revert ya consumido que se salta al recuperar.
  Sin ello, tras un segundo fallo su fecha podía ser anterior a la reautorización
  previa e impedir otra recuperación explícita. La acción técnica `reconciled`
  usa el mismo fence; conserva receipt, historial y estado de la operación.
- Retirar canonical_attempt/confirmaciones/finalidad al clasificar divergencia
  por la acción de error, conservando la evidencia histórica. No se transforma
  un timeout en ausencia, divergencia o éxito.
- Conservar una observación mempool pendiente sin retransmitir innecesariamente
  esos bytes en la misma pasada. El rechazo RPC de una retransmisión ya conocida
  podía actualizar la fecha del bloqueo después de observar el intento y hacer
  imposible reautorizar. Unknown conserva la retransmisión de los mismos bytes;
  pending conserva la reserva y no autoriza firmas nuevas implícitamente.

El adaptador compara toda la identidad del deployment con su binding antes de
RPC/firma y exige que la segunda lectura del receipt concuerde con la primera
en hash/status/from/to/bloque/índice. Null temporal devuelve indisponibilidad.
ABI, runtime/build congelados, Solidity, dependencias y bootstrap 10B intactos.
Son correcciones del protocolo aceptado en ADR-0015/0016/0018; no hay una nueva
decisión estructural ni un ledger alternativo.

## Archivos

Migración nueva: `20261018120000_revocation_evidence_reconciliation.sql`, que
sustituye únicamente blockchain_update_job, sin backfill, DML de certificados,
grants nuevos ni edición de migraciones compartidas.

Código: coordinator.ts y evm_registry.ts bajo functions/_shared/blockchain.
Pruebas nuevas: application/coordinator_test.ts y data/evm_registry_test.ts.
Ampliadas phase10_faults/concurrency/deployments, blockchain_verification.test.sql
y verify_revocation_migration.ps1. phase10_acceptance y phase9d_environment
mejoran exclusivamente la localización/diagnóstico cerrado de fallos del harness.
Documentación: esta aceptación, PHASE10_ACCEPTANCE, REVOCATION,
BLOCKCHAIN_OPERATIONS, TESTING y ROADMAP.

## Evidencia nueva

Ejecuciones nuevas sobre el HEAD indicado con dirty=true, Windows x64, Node
24.14.0, Deno 2.2.12, Supabase CLI 2.117.0, Docker 29.8.2,
Foundry 1.8.5 y solc 0.8.37, sin actualizar toolchains.

| Comprobación ejecutada | Resultado local nuevo |
|---|---|
| `run_phase10.ps1 -BackendOnly`, inicio 14:26:08.539Z | PASS, 289 escenarios reales Auth/Edge/SQL/Storage/Anvil; Flutter NOT_RUN |
| SQL/RLS, migración nueva y preservación histórica rollback-only | PASS, 978 pgTAP; lint sin errores; migraciones compartidas intactas |
| Fallos/reinicio/lease/CAS/response loss/issue tardío/reorg | PASS, incluidos procesos CLI nuevos y ambos reorgs combinados |
| Dos reverts consumidos y posteriores recuperaciones auditadas/rotación EOA | PASS, los tres intentos y receipts se conservan |
| Replacements de revoke en mempool real | PASS, tres replacements; relación, mismo nonce/calldata, ambas fees >=20%; gana el intento original |
| Membresía retirada bloquea replacement; observación bloqueada y reautorización | PASS, sin firma implícita ni salto de nonce |
| Workers concurrentes, takeover de lease y worker antiguo reanudado | PASS, una firma/operación y confirmación preservada |
| Dos anchors/contratos reales, obligación antigua deshabilitada | PASS, obligación actual confirmada y anterior bloqueada; posterior recuperación explícita del original |
| Estado incompatible en inclusión/head; issue receipt usado para revoke | PASS, divergencia sin promover evidencia o liberar la reserva |
| PDF/SQL/auditoría/completed/identidad | PASS, comparaciones exactas en memoria antes/después de fallos y replacements |
| Deno funciones y política gateway | PASS, 272 pruebas, incluidas 20 nuevas de coordinador/adaptador |
| Foundry fmt/tests | PASS, 28 casos; invariantes 128 runs / 8192 llamadas |
| Node transporte/bootstrap y harness blockchain | PASS, 10 pruebas |
| Harness navegador y readiness Edge | 17 PASS, 2 SKIP: cámara y fixture Unix en Windows |
| Deno fmt/lint/check, parser PowerShell, enlaces locales, diff whitespace | PASS |
| Bootstrap fijado, build normal, artefactos y ABI backend | PASS, sin drift |
| Cleanup runner 10 | PASS, stack/directorio/Anvil/red/Edge/destinos propios retirados |
| Regresión independiente `run_phase9c.ps1` | PASS, 163 comprobaciones reales; 978 pgTAP, lint y cleanup propios PASS |

Hora de inicio UTC; los JSON exactos prevalecen sobre el texto. Evidencia
sanitizada: `mobile/build/phase10-evidence/backend-only.json`, result.json y
attempts.ndjson; logs locales phase10c-run4/deno-final/foundry/node/harness bajo
mobile/build. full.json/browser.json anteriores no se reemplazan ni se presentan
como ejecuciones de esta revisión. Auth/privacidad/aplicación no-store PASS;
diagnóstico estricto del gateway FAIL con nueve excepciones genéricas previas
aceptadas por 10B, visibles y sin ampliar esa excepción.

Se conservan tres intentos preliminares FAIL en attempts.ndjson: los dos primeros
(14:14:05 y 14:18:03 UTC) detectaron el helper que asignaba lease_until no nulo
a un token ya liberado; se corrigió el fixture, sin relajar el constraint.
El tercero (14:21:52 UTC) descubrió la reautorización bloqueada por retransmitir
un hash ya pendiente; motivó la corrección de producción y su prueba específica.
No se convierten esos resultados en PASS. La cuarta pasada completa es la nueva
evidencia satisfactoria de backend; la regresión independiente también terminó
con PASS, registrada en mobile/build/phase10c-9c.log.

Las barreras son del harness local, sin parámetros remotos de producción.
La pérdida de respuesta se inyecta en la frontera de transporte después de que
Anvil acepte los bytes reales; no se presenta como corte de socket del proveedor.
Las pruebas de replacements adelantan solo la condición de edad de la RPC copiada
en el stack desechable y restauran su definición exacta en finally; conservan
fencing, identidad, reserva y límites de comisión. Las pruebas nuevas 10C no
incorporan sleeps arbitrarios ni timeouts ampliados. Se usan wallets/certificados
sintéticos, sin fondos reales.

## Recuperación y límites

**Dictamen: 10C cerrada localmente para backend/Supabase local/Anvil.** La
regresión independiente conserva las garantías de emisión/ledger y confirma
issue reorg por separado, además de los reorgs de revoke y combinados de fase 10.
Los tres FAIL exploratorios se conservan; la evidencia nueva no altera la
aceptación histórica de otras fases ni equivale a GitHub Actions.

Reinicio: esperar vencimiento legítimo del lease; el nuevo proceso reclama otra
generación, observa hashes existentes y retransmite los mismos bytes cuando
corresponde. Una firma no persistida nunca se envía. Una respuesta de broadcast
perdida conserva hash/raw y no crea otra operación. El antiguo worker no supera
CAS. Replacements pertenecen a la misma operación, conservan nonce/calldata y
relación; también se observa el intento anterior que finalmente gane.

Blocked/failed: observar todos los intentos tras el bloqueo y corregir su causa;
owner/admin actual reautoriza explícitamente con auditoría. Un revert conserva
receipt y consumo de nonce; el siguiente intento usa nonce posterior conocido
o EOA rotado con ledger propio. No saltar nonces desconocidos. Divergence exige
investigación operativa de identidad/evidencia; no retry ciego. Disabled,
writes_stopped y reset conservan la obligación en su deployment original.

Reorg de issue/revoke retira atribución canónica, conserva observaciones fechadas
y recupera la misma identidad y bytes. Ningún fallo EVM reactiva SQL ni modifica
motivo, actor, request_id, fecha original, publicación completed o PDF.
SQL revoked_at, timestamp EVM y checked_at mantienen significados separados.
Anvil acredita inclusión/confirmación local, con finality=not_applicable.

GitHub Actions del árbol modificado NOT_RUN; no push, merge ni despliegue remoto.
Supabase alojado, Sepolia/finalidad PoS y custodia de producción NOT_RUN.
Esta revisión backend no vuelve a aceptar 10D/10E ni acredita nuevas pruebas de
Flutter, recorrido Web release, Android/iOS, Firefox/Safari o revisión humana.
La revisión siguiente 10D debe contrastar permisos/progreso/reautorización y
presentación diferenciada de SQL, issue, revoke y evidencia histórica en el cliente.

Cámara SKIP/NOT_RUN, CERTICHAIN_TEST_CAMERA=0:
«Omitidas por instrucción del usuario; no hay cámara física disponible».
Se conservan código y pruebas independientes de QR estático, códigos, enlaces,
PDF, Auth, SQL y blockchain; ninguna exclusión de cámara omite una suite completa.
