# Operación privada de anclajes — 9C

## Recuperación de revocaciones 10C — 18/10/2026

[Aceptación específica](PHASE10C_ACCEPTANCE.md). Aplicar la migración nueva
20261018120000 después de las existentes, antes de usar el coordinador actualizado.
No requiere cambiar ABI, contrato, red, claves o configuración Edge/Flutter.
La validación completa precede a la persistencia de confirmación y liberación
del nonce. Una divergencia retira la atribución vigente y conserva el historial.

Reiniciar el mismo worker sobre la operación existente después del lease;
reutiliza firma/hash/bytes y ledger. No crear otra operación por respuesta perdida.
Para blocked/failed, ejecutar observación de todos los intentos, corregir causa y
reautorizar explícitamente por owner/admin actual. Los reverts ya consumidos
refrescan observed_at sin perder receipt ni volver a imponer su fallo antiguo;
ello permite una segunda recuperación auditada si también falló el siguiente
intento. El EOA rotado conserva I y utiliza su propio historial íntegro de nonce.
Ninguna firma nueva usa reservas del EOA anterior sin resolverlas.
Un intento observado pending ya está aceptado en mempool: conserva reserva y
observación sin reenviar en esa pasada. Así un rechazo de bytes ya conocidos no
invalida continuamente la reconciliación necesaria para reautorizar. Unknown
permite retransmitir los bytes durables; no demuestra que el intento se abandonó.

Los deployments anteriores deshabilitados conservan sus obligaciones. Solo
retransmisión/observación de bytes existentes permitida por el protocolo; nuevas
firmas requieren habilitación explícita del deployment original, configuración
válida y canRevoke vigente. No redirigir al deployment habilitado actual.
Reorg conserva observaciones fechadas y SQL revoked; reset exige recuperar la
identidad exacta. Anvil nunca acredita finalidad PoS.

## Incremento local de revocación — 15/10/2026

[REVOCATION](REVOCATION.md) define los endpoints Auth, motivo/auditoría privados,
SQL irreversible, worker durable y evidencia pública v3 con issue/revoke separados.
V1/v2 y compare conservan contrato; la app usa v3. Resultados ejecutados y
dictamen vigente: [PHASE10_ACCEPTANCE](PHASE10_ACCEPTANCE.md). Los apartados
que describen revocación futura conservan el contexto histórico de sus fases.
La demo se reproduce con `./supabase/tests/run_phase10.ps1`; sin despliegue remoto,
Sepolia ni corrección Android atribuida. Cámara=0 con la exclusión persistente.

## Aceptación y recuperación local 9E

[run_phase9e.ps1](../supabase/tests/run_phase9e.ps1) comparte infraestructura 9D y
ejecuta publicación/solicitud/worker/progreso/v2/apertura/archivos de producción.
`-BackendOnly` comprueba infraestructura sin acreditar Flutter.
Guion: [DEMO_BLOCKCHAIN_LOCAL](DEMO_BLOCKCHAIN_LOCAL.md); evidencia:
[PHASE9E_ACCEPTANCE](PHASE9E_ACCEPTANCE.md). No cron ni servicios remotos.

La recuperación nueva usa destinos aislados PG y Storage con datos sintéticos:
ledger privado completo y bytes recuperados deben conservar H/K/I/C/S y coincidir
con el registro canónico original. El backup de bytes es independiente del dump
SQL. No basta restaurar storage.objects: es necesario recuperar bytes por API y
comprobarlos. El ejercicio no prueba el proveedor remoto ni copias/volúmenes reales.

Restaurar el entorno original exacto no equivale a crear otro deployment/cadena.
Reset invalida identidad previa y debe conservar evidencia histórica, sin fallback
silencioso a off_chain_only ni firmar contra un contrato distinto. Un ledger
incompleto no autoriza reconstruir firmas o saltar nonces; se conserva el bloqueo
demostrado en 9C. Estado ejecutado de restore y limpieza en la aceptación 9E.

## Lectura Edge y cliente 9D

Edge verify-certificate-v2 añade EVM_RPC_URL **solo para lectura**, junto con
EVM_ENVIRONMENT_ID; no claves de firma/administración. En Docker, conectar su
contenedor a la red privada Anvil propia y usar http://anvil:8545. El lector
no invoca worker, no encola, no firma ni concilia escrituras. Flutter nunca
recibe esa URL, secretos ni un manifiesto histórico como configuración viva.
Conservar backend worker host y sus variables privadas 9C. Sin worker activo,
la solicitud institucional permanece requested/pending, sin progreso ficticio.

El operador registra despliegue vivo normal nuevo, configura I/signer mediante
administración durable y ejecuta worker explícito como abajo. Flutter solicita,
recupera y actualiza operation_id/status reales; reautoriza blocked/failed,
divergence requiere revisión. Titular solo lee proyección pública y apertura.
Preparación, APIs y reproducción integral: [BLOCKCHAIN_VERIFICATION](BLOCKCHAIN_VERIFICATION.md),
`./supabase/tests/run_phase9d.ps1`. No automatización/cron ni Sepolia en 9D.

Publicación 7B → solicitud explícita autorizada → firma durable → envío raw →
receipt/evento/estado/bloque canónicos → confirmación persistida. completed no
encola EVM. Flutter, API pública v1 e históricos conservan su comportamiento.
El compromiso no acredita verdad académica ni compara un PDF sin apertura.

## Preparación y aislamiento local

Supabase CLI 2.117.0, Deno 2.2.12, Foundry 1.8.5 y Solidity 0.8.37 existentes.
Ethers 6.15.0 y sus transitivas están congelados en deno.lock.

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
node blockchain/scripts/bootstrap.mjs
node blockchain/scripts/forge.mjs build --force
node blockchain/scripts/backend-abi.mjs --check
./supabase/tests/run_phase9c.ps1
```

El runner reutiliza el preparador descartable: proyecto certichain_8d_UUID,
puertos 55321/55322, directorio nuevo fuera del checkout. SQL se ejecuta antes
de los fixtures HTTP mutables; Anvil propio usa una red Docker exclusiva y un
puerto libre publicado en 127.0.0.1. finally limpia solo ese stack, contenedor
y red propios. No resetear el habitual
ni ejecutar suites mutables en paralelo.

El worker corre en el host, conecta con Kong/Edge/Storage publicados desde Docker
y con Anvil por loopback del host. Edge no hace RPC EVM ni recibe claves de firma.
La prueba conecta el contenedor de BD propio a la red del Anvil, resuelve
anvil:8545 y consulta chainId; confirma que loopback dentro del contenedor falla
y que la publicación administrativa del host está ligada a 127.0.0.1.
En Windows anvil-linux.mjs extrae el binario Linux del archivo 9B con checksum
congelado; en Ubuntu se usa el binario verificado por bootstrap. El contenedor
reutiliza el ID inmutable de la imagen Edge local Supabase compatible con glibc;
la imagen Postgres musl no es compatible. No introduce imagen flotante.
Para ejecutar el worker en un contenedor, conectarlo a ambas redes privadas y
usar anvil:8545 y Kong interno. Esa ubicación del proceso requiere validación
adicional; la conectividad privada entre contenedores sí se prueba aquí.

## Deployment y configuración administrativa

Los manifests 9B son históricos; su Anvil fue reseteado/detenido. Se rechaza el
ejemplo sintético. Desplegar el bytecode normal nuevo con administrador distinto
del firmante operativo. El harness usa una creación firmada y compara el runtime
con build-reference.json; no despliega el build de coverage.

Formato de registro: synthetic=false, environmentId, network, chainId decimal
string, contractAddress, protocolVersion=1, runtimeCodeHash, genesisHash,
deploymentBlock {number decimal string,hash}. Validación antes de firma y en cada
pasada: cadena, contrato/versión/runtime, bloque/hash y genesis. El módulo ABI y
runtime se generan desde 9B, con comprobación de igualdad. Registrar otro entorno
tras un reset; no alterar la identidad de operaciones existentes.

Variables solo del operador/backend: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
EVM_RPC_URL, EVM_MAX_COST_WEI, EVM_SIGNER_PRIVATE_KEY. Edge requiere
EVM_ENVIRONMENT_ID (por defecto local). Suministrar por entorno privado, no Git.

```sh
npx --yes deno@2.2.12 run --allow-env --allow-net --allow-read --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts register MANIFEST_PRIVADO
npx --yes deno@2.2.12 run --allow-env --allow-net --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts configure ACTOR_PLATFORM DEPLOYMENT INSTITUTION I SIGNER true true KEY
```

I: 32 bytes CSPRNG opacos no cero, persistentes por institución/deployment;
nunca nombre/email/UUID de aplicación. configure conserva I y snapshots
administrativos/config_version. ACTOR_PLATFORM ya debe existir y estar confirmado
operativamente; la RPC no concede ese rol. Administración EVM con
EVM_ADMIN_PRIVATE_KEY en sesión separada: admin-worker OPERATION. El worker
ordinario rechaza recibir esa clave y solo procesa issue, nunca setIssuer.
Cada EOA es exclusivo del coordinador. La creación del contrato debe usar otro
deployer; consumo previo desconocido de nonce se bloquea incluso al iniciar.
admin-worker vuelve a leer issuer en el head canónico: un receipt administrativo
histórico no demuestra que el permiso siga vigente. Si desired/observed difieren,
sync queda pending. configure con una key nueva puede crear otra config_version
explícita para restaurar la configuración deseada, conservando operaciones previas.
Key administrativa repetida con payload distinto conflictúa. La reautorización
administrativa usa `reauthorize ACTOR_PLATFORM OPERATION`, conserva requested_by
y exige privilegio platform_admin actual; no se hace al recuperar un trabajo.

## Solicitud, progreso y reautorización

POST /functions/v1/anchor-certificate con Auth real y JSON cerrado UTF-8 <=2048
bytes: certificate_id e idempotency_key UUID. Ningún actor/institución/RPC/red/
contrato/signer/permiso/K/I/H/S/C del cliente. 202 nueva, 200 recuperación;
solo operation_id/status, no-store, sin afirmar confirmación.

Autoriza owner/admin/issuer vigente de verified, certificado active no caducado,
completed coherente y binding habilitado/reconciliado. PDF privado leído,
inspeccionado y hasheado fuera del lock; snapshot revalidado al insertar. SQL
recalcula K/C y digest calldata. Misma key con otro certificado es conflicto;
otra key para el anchor recupera la operación existente, sin nuevo salt.

401 unauthenticated; 403 authorization_denied; 404 publication_unavailable;
409 idempotency_conflict/busy; 503 temporary_failure. Sin errores upstream.
POST /functions/v1/anchor-progress, operation_id, vuelve a autorizar y devuelve
solo operation_id/status. Titular o UUID conocido no abren datos operativos.
POST /functions/v1/reauthorize-anchor, operation_id, reautoriza blocked/failed
explícitamente; requiere reconciliar intentos anteriores y conserva requested_by.
Añade actor/rol/fecha, máximo 64. Recuperar solicitud no reautoriza implícitamente.
Divergence requiere resolución operativa, sin RPC de retry ciego.

## Worker y recuperación

```sh
npx --yes deno@2.2.12 run --allow-env --allow-net --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts worker OPERATION
```

Sin ID selecciona hasta diez trabajos. Lease 120 s, renovación al alcanzar 30 s,
token/generation y CAS. Orden: institución, publicación/certificado, binding,
anchor, operación, nonce. No SQL abierto durante RPC. Un lease no cancela bytes
ni proporciona fencing criptográfico. RPC diez segundos; pasadas acotadas.

Hash/raw/nonce/signer/payload se guardan antes de eth_sendRawTransaction. Commit
fallido impide envío. Reinicio/respuesta perdida observa el hash local y reenvía
los mismos bytes. Unknown no demuestra dropped; nonce se retiene. Se observan
todos los hashes, también replacements anteriores que podrían ganar. Permisos
se revalidan antes de nuevas firmas; bytes existentes se siguen observando.
Los fallos de constraints en la RPC de persistencia de firma se devuelven sin
DETAIL de la fila privada; no volcar errores SQL completos ni raw en diagnóstico.

Un nonce lógico sin resolver por EOA. Tras cinco minutos, hasta tres replacements
con mismo nonce/to/data/value=0 y ambas fees >=20% superiores, dentro del presupuesto.
No cancelación automática ni salto de nonce desconocido. Revert resuelto puede
tener otro intento con nonce posterior de la misma EOA o nonce conocido de una
EOA nueva autorizada, solo tras reautorización auditada: no es replacement del
nonce ya consumido. Misma operación/anchor, máximo 256 intentos,
ligado al límite de 64 reautorizaciones.

Receipt exige status=1, from/to/chain/calldata, evento exacto, signer, timestamp,
log index, estado y bloque canónico. Anvil: una confirmación, not_applicable.
Sepolia: doce y finalized según 9A, sin ejecución en este encargo. Reorg conserva
observación orphan y reusa identidad. Reorg finalized detiene escrituras.
K/C/I distintos o evidencia incompatible son divergence, sin sobrescribir.
El receipt incompatible se conserva con validated_log_index=null, sin promoción
y con confirmaciones/finalidad actuales invalidadas; permanece la evidencia anterior.
Mismo K/C/I sin receipt SQL busca evento original desde deployment: páginas de
2000 bloques, cuatro por pasada, cursor durable, recupera firma/evidencia original.

Backoff 15/30/60 s hasta cinco minutos. Fondos, permisos, deployment o nonce
desconocido bloquean; fallo RPC conserva estado. No borrar PDF, certificado ni
completed. Salt perdido: restaurar exacto; nunca inventar otro compromiso.
Si se recupera un receipt válido pero falta el historial de nonces de su EOA,
puede recuperarse la evidencia del certificado; el ledger nuevo queda en cero.
No se adelanta al nonce del receipt ni habilita firmas nuevas saltando consumos
desconocidos. Restaurar historial privado exacto o resolver operativamente antes
de reautorizar firmas; el harness prueba ese caso con cadena real y pérdida
deliberada de la fila exclusivamente en su stack aislado.

## Backups, retención y limpieza

Backup privado incluye vínculos public/auth y certichain_private. Storage tiene
backup independiente de bytes exactos. Limitar y cifrar acceso operativo; ningún
dump en logs, repositorio o Actions. Raw tx es una capacidad retransmisible.

El harness usa pg_dump custom con umask 077 dentro del contenedor propio y
pg_restore como supabase_admin en otra BD sintética. Compara S/K/I/H/C/operación
en memoria sin imprimirlos; finally borra BD/dump. No demuestra restore de
Storage ni servicio remoto. Tablas privadas no tienen SELECT directo de API.

Anchors/salt/operaciones/bindings/receipts se conservan. close-local OPERATION
cierra confirmed Anvil; purge-raw purga solo siete días después de ese cierre
o de finalized Sepolia. Mantiene hashes, metadata y evidencia. Límites de 64
receipts/auditorías requieren operador. No hay limpieza automática de documentos.

Cámara NOT_RUN: «Omitidas por instrucción del usuario; no hay cámara física disponible».
El texto técnico 9C anterior es histórico. 9D/v2 están integrados; 9E amplía su
aceptación local. Fase 10, cron remoto, backfill y Sepolia no se implementan aquí.
