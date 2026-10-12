# Aceptación técnica de backend 9C

Base revalidada: `5d29a98580493bef07220c0b48780eec7348876c`, árbol inicial limpio.
Trabajo local 12–13/10/2026; cierre de comprobaciones el 13/10/2026.
Cambios locales sin commit/push/merge/despliegue remoto. 9A sigue normativo;
contrato/ABI/build/fixtures 9B intactos. Flutter, v1 pública y revocación de
producto fuera del incremento. 9D/9E/10 permanecen pendientes.

## Arquitectura y persistencia entregadas

Migración nueva creada por CLI 2.117.0:
`20261012204952_durable_private_anchoring.sql`. Seis tablas en
certichain_private: deployments, issuers, anchors, operations, attempts, nonces.
RLS sin políticas cliente, sin grants directos PUBLIC/anon/authenticated/
service_role; RPC técnicas con SECURITY DEFINER/search_path vacío/EXECUTE técnico.
FK compuestas de publicación/certificado/institución/binding/deployment y
canonical_attempt. Bytea con longitud 20/32, cantidades numeric/bigint;
fronteras operativas EVM en decimal string, sin convertir uint256 a JS number.

Identidad K/I/H/S/C, actor original, payload y snapshots administrativos
inmutables. Una operación issue por anchor y anchor por certificado/deployment;
otra key recupera, reutilizar key para otro payload conflictúa. Salts CSPRNG,
concurrentes/reinicio/reorg mantienen el mismo. Evidencia/auditorías append-only
acotadas a 64, sin borrado destructivo. Lease 120 s, token/generation/CAS,
padre primero y ninguna transacción SQL esperando RPC.

Dominio puro en `_shared/blockchain/domain`; compromiso/coordinador en
application; ethers/RPC y persistencia en data. BlockchainRegistry y puertos
propios para infraestructura. ABI/runtime del módulo generado iguales a 9B.
Ethers 6.15.0 congelado en deno.lock: ABI/RLP/EIP-1559/secp256k1/Keccak estándar.
SDK/CLI/Foundry/Solidity existentes conservados. Las conversiones de nonce que
requiere ethers se rechazan por encima de MAX_SAFE_INTEGER, nunca redondean.
Vector SHA256 exacto de 9B compartido, no criptografía Ethereum propia.

## Endpoint y firma

anchor-certificate, anchor-progress, reauthorize-anchor con verify_jwt=true y
consulta Auth real. JSON cerrado UTF-8 <=2 KiB, UUID canónicos, sin datos de
autoridad ni identidad on-chain del cliente. PDF privado íntegro, autorización
actual y snapshot revalidado al commit. DTO operation_id/status no-store.
202 solicitud, 200 recuperación: ninguno acredita confirmación. Blocked no
se reautoriza al consultar. Reautorización explícita conserva actor e historia.

CLI `supabase/admin/blockchain.ts`: register/configure/admin-worker/worker/
close-local/purge-raw. Signers separados; worker ordinario no recibe admin key
ni hace setIssuer. Config version/snapshots durables. Firma raw EIP-1559,
hash local/nonce/calldata/raw guardados antes de broadcast; commit fallido no envía.
Observar todos los hashes antes de preparar sustitución, incluidos antiguos.
Nonce exclusivo sin resolver, no reciclar por timeout/saltar consumos desconocidos.
Replacements del mismo nonce: tres, fees >=20%, presupuesto. Revert resuelto
necesita reautorización para intento posterior del mismo anchor (ADR-0016).

Antes de firma/reconciliación: chainId, dirección/versión, runtime 9B, bloque/hash
deployment, genesis/environmentId. Null RPC no se trata como ausencia/dropped.
Receipt status=1 sin calldata/evento/estado/timestamp/signer/bloque compatibles
no confirma. Anvil una confirmación y not_applicable; Sepolia no ejecutada.
Reorg conserva orphan/reinclusión; divergencia no se resuelve mediante retry ciego.

## Validación local observada

Windows x64, Docker Desktop, Supabase CLI 2.117.0, Deno 2.2.12, Node host 22.14.0
(CI conserva Node 24.14.0), Foundry 1.8.5/Solidity 0.8.37 existentes. Anvil Linux
propio en contenedor/red privada, sin fork y publicado solo en loopback. Se
reutiliza el ID de imagen Edge Supabase compatible con glibc. El archivo Linux
Foundry conserva versión/checksum 9B. DNS anvil:8545/RPC entre contenedores
comprobado; loopback interno incorrecto y HostIp=127.0.0.1 también comprobados.
Backend Docker real; worker host, sin RPC ni claves de firma en Edge.

Comandos ejecutados sobre proyectos descartables certichain_8d_* nuevos,
API 55321/DB 55322, fuera del checkout; el habitual no se arrancó ni reseteó.
Cada pasada completa termina Anvil/red/Edge/Supabase propios y elimina su copia.

- `supabase db reset --local --workdir STACK_PROPIO`: aplica todas las migraciones.
- `supabase test db --local --workdir STACK_PROPIO`: **825 comprobaciones, PASS**,
  incluidas 611 existentes y 214 nuevas de permisos/catálogo/roles reales.
- `supabase db lint --local --schema public,certichain_private --level warning --fail-on warning`:
  sin errores de schema.
- Deno fmt/lint/check --frozen y test functions: **81 tests, PASS**.
- `./supabase/tests/run_phase9c.ps1`: **163 checks reales, exit 0** en la pasada
  Docker completa, incluida rotación tras revert, recuperación sin historial
  privado de nonce y un intento anterior que gana después de tres replacements.
- `node blockchain/scripts/backend-abi.mjs --check`: igualdad reproducible.
- `node blockchain/scripts/artifacts.mjs --check`: artefactos normales 9B intactos.
- `actionlint .github/workflows/anchoring.yml`, sintaxis PowerShell y
  `git diff --check`: PASS local; esto no ejecuta el workflow remoto.

Regresiones independientes, ejecutadas secuencialmente con SQL primero en
certichain_8d_82316f4b: issuance_http 366, issuance_hardening_http 135,
certificate_pdf_http 90, public_verification_http 296, hash_comparison_http 255
comprobaciones PASS; private_storage e institution_concurrency exit 0.
La caducidad de descarga y rate limit de esas suites usan espera real.

Recorrido real: Auth password → publicación 7B active/completed → endpoint →
anchor/operación privados → raw firmado/persistido → eth_sendRawTransaction →
receipt y evento CertificateIssued → lectura del mismo bloque → confirmed SQL.
No eth_sendTransaction del smoke ni manifiesto sintético/histórico reutilizado.

Cadena real: solicitud concurrente única, workers concurrentes, firma/hash/ABI,
pending, tres replacements y ganador anterior conservando todos los hashes;
funds/revert/unknown nonce; reorg por
evm_snapshot/evm_revert, orphan y reinclusión en bloque distinto, reset y manifest
incompatible. Se prueba también head por debajo de la inclusión anterior:
un null solo no invalida; se comprueba un head canónico estable inferior,
se retira evidencia actual y se conserva la observación orphan.
Auth: actor retirado antes de firma, recuperación blocked y reautorización
auditada; firma previa a retirada conserva observación y confirmación real.
Administración durable: idempotencia/conflicto, falta de fondos, reautorización
platform_admin, versiones de permisos y reconciliación del head vigente sin
sobrescribirlo con un snapshot administrativo histórico.
SQL: rechazo real del commit de firma no consume nonce ni envía; recuperación
del commit retoma la misma reserva. Errores de constraints al persistir firma
se convierten en error cerrado: no propagan DETAIL con la fila privada/raw.
RPC rechazado y servidor HTTP local lento
producen error técnico; el segundo usa deadline corto del harness, no simula
una inclusión ni afirma demostrar consenso. Evidencia incompatible real frente
a snapshot deliberadamente dañado conserva receipt y pasa a divergence.
Comando CLI worker real en dos procesos Deno separados: submitted/confirmed,
sin admin key. Rotación administrativa durable con revert del antiguo firmante,
reautorización y nonce cero de la EOA nueva: mismo anchor/salt/compromiso e
historia de ambas cuentas. Nonces se comparan dentro de una EOA, no entre EOAs.
Pérdida aislada del ledger privado: se recupera el receipt original compatible,
pero no se inventa historial ni se salta al nonce observado. La siguiente
firma queda bloqueada ante consumo desconocido; conserva la evidencia anterior.
Crash alrededor de firma durable, broadcast y receipt: barreras de código en
harness aislado; las inclusiones resultantes sí son reales.
Leases/edad de replacement/retención: reloj controlado solo en SQL del stack
aislado, sin cambios de duración/flags en producto. No se presenta como espera
real de cinco minutos/siete días. Salt corrompido solo en fixture protegido:
detiene firma, restaura bytes exactos y reautoriza, sin sustituir compromiso.

Backup real: pg_dump custom privado dentro del contenedor con umask 077 y
pg_restore en otra BD sintética, usando supabase_admin para permisos de restore.
S/K/I/H/C y operación comparados en memoria; replay sin duplicate issue.
No dump/secretos en repo/logs/artefactos. No acredita restore de Storage/servicio
remoto. Raw purgado tras cierre + siete días controlados; hashes/receipts permanecen.

Intentos fallidos de desarrollo se conservan como historia: TAP inicialmente
mal serializado (corregido); Buffer global de helper Node bajo Deno (sustituido);
estimateGas pending causaba duplicado al reemplazar (fijado latest); pg_restore
con postgres carecía de SET log_min_messages (rol correcto supabase_admin);
RPC void 204 se parseaba como JSON (corregido); Edge propio quedaba abierto
(stopRuntime). Una recuperación HTTP inicial devolvió error después de concurrencia,
sin causa demostrada; repeticiones posteriores pasaron, sin retry ciego de POST.
SQL concurrente con fixtures vivos produjo fallos de supuestos de aislamiento;
se repitió en stack fresco con SQL primero y fixtures secuenciales. Lint estricto
detectó variable SQL sin uso: retirada junto con su RETURNING sobrante tras un
intento fallido de aplicar la migración. Dos arranques Anvil Docker fallaron por
usar la imagen Postgres musl con binario glibc; corregido a imagen Edge, deadline
global de readiness y puerto efímero con Deno.listen. Los procesos de prueba
atascados se interrumpieron; sus contenedores/redes propios se eliminaron.
El caso añadido de rotación detectó que comparar nonces entre EOAs diferentes
volvía a aplicar un revert anterior al confirmar el nuevo intento. Corregido:
se ordena por intentos y se distingue cuenta/nonce; los replacements siguen
exigiendo misma EOA/nonce, y un cambio de cuenta exige revert reconciliado y
reautorización explícita. Esa pasada fallida no se incluye como PASS final.

## CI y límites

Base 9B reconsultada por GitHub: runs 38301216330 y 38301216385, intento 1,
success y pasos ejecutados, SHA 5d29a985…; historia en aceptación 9B.
No acredita este árbol 9C sin commit. `anchoring.yml` añade Ubuntu 24.04,
herramientas fijadas, Supabase/Edge/Anvil reales, SQL nueva, readiness acotado,
fixtures secuenciales y stop always. Arranque sin volcar claves locales en logs.
Workflows existentes conservados. CI nueva
**NOT_OBSERVED**: no se ha creado/publicado SHA nuevo por instrucción del usuario.

No Flutter/v2/apertura pública, revocación de producto, cron, backfill o Sepolia.
Puerto revoke técnico no habilita solicitud de producto. Finality Sepolia y
reorg tras finalidad solo política/código, no evidencia Anvil de consenso PoS.
Variante worker en contenedor y restore de Storage requieren validación propia.
La UI no se ha modificado; las regresiones backend y CI base son evidencia
separada de un recorrido Flutter nuevo, que no se ejecuta en este incremento.

Cámara **NOT_RUN**, CERTICHAIN_TEST_CAMERA=0:
«Omitidas por instrucción del usuario; no hay cámara física disponible».
No reabrir 8D por hardware.

## Dictamen

Backend 9C apto localmente para iniciar 9D: anclaje real firmado, autorizado,
durable, idempotente y recuperable demostrado con Supabase y Anvil propios.
No hay bloqueo local del recorrido solicitado. Antes de atribuir aceptación
CI al incremento, debe publicarse con autorización un SHA nuevo y observar
sus workflows; esa publicación no forma parte de este encargo. 9D/9E/10
continúan pendientes, igual que las validaciones manuales específicas de
Storage restore y ejecución del worker dentro de contenedor.
Operación: [BLOCKCHAIN_OPERATIONS](BLOCKCHAIN_OPERATIONS.md).
