# Fase 9A — Protocolo blockchain de CertiChain, versión 1

Fecha: 2026-10-12. Estado: diseño aceptado; **sin integración ni despliegue**.
Decisiones: [ADR-0014](adr/0014-evm-network-toolchain-and-authority.md) y
[ADR-0015](adr/0015-private-commitments-and-durable-anchoring.md).
Este documento es normativo para 9B–9E y la revocación de fase 10. Los fragmentos
de interfaz son especificaciones, no archivos ejecutables del producto.

## 1. Base inspeccionada y límites

HEAD local y `origin/main` consultado con `git ls-remote`:
`2066e908af30913462cf3daf77324eab2a63dfc4`; árbol limpio antes de 9A.
No se encontraron instrucciones de subdirectorios. `blockchain/` está vacío:
no hay contrato, ABI, configuración Foundry ni implementación de
`BlockchainRegistry` reutilizable. El nombre en ARCHITECTURE era conceptual.

[Actions 38280055013](https://github.com/benjvm/certichain/actions/runs/38280055013),
intento 1, acredita ese SHA: `database`, `flutter`, `android` success, con pasos
ejecutados; Android compila main.dart debug, no demuestra un recorrido físico.
Se reconsultaron run/intento/jobs por el conector GitHub. El workflow fija
`CERTICHAIN_TEST_CAMERA='0'`. No acredita blockchain ni cámara física.

Fuentes de comportamiento actual inspeccionadas:

| Área | Fuente real y comportamiento |
|---|---|
| Esquema | `20260918192226_initial_schema.sql`: profiles, institutions, institution_members, certificates; enums reales owner/admin/issuer, pending/verified/rejected/suspended, active/revoked |
| Escrituras | `20260928202802_close_direct_certificate_writes.sql`: clientes sin INSERT/UPDATE/DELETE de certificates, también platform_admin |
| Administración | `20260928210000_institution_administration.sql`: membresías reales, bloqueo padre primero, último owner protegido |
| Publicación | `20260930120000_prepare_private_issuance.sql` y `20260930150000_authenticated_private_issuance.sql`: operación durable, FK compuestas, lease 120 s; `advance_certificate_issuance(...,'publish',...)` inserta active y completed atómicamente |
| Identificador/hash | publish genera `gen_random_uuid()::text` para credential_code; handler valida PDF y calcula SHA-256 antes/después de Storage; `stored_hash = pdf_hash = document_hash` |
| Documento | `20260930180000_authorized_certificate_document.sql` y certificate-pdf: acceso autorizado, comprobación de bytes y URL de 60 s |
| Público | `20261004173032_public_certificate_verification.sql` / `20261005120000_public_candidate_hash_comparison.sql`: snapshot completed/coherente, DTO v1 cerrado, comparación candidata sin revelar hash esperado |
| Recuperación | `supabase/admin/reconcile_issuance.mjs`: limpieza local explícita de huérfanos; no ancla ni elimina PDF completed |

`certificate_types`, `blockchain_records` y `verification_events` de diseños
antiguos **no existen**. Tampoco existen estados anchoring/anchor_failed en
certificates. La tabla privada `public_verification_budget` sí existe.
9A no cambia código, esquema, RPC, DTO, certificados, QR ni herramientas instaladas.
Históricos siguen off-chain; no habrá backfill automático.

## 2. Red, herramientas y evidencia de consenso

- Local: Anvil, chain ID **31337**, cadena descartable sin fork de mainnet.
- Demo: **Ethereum Sepolia**, chain ID **11155111**, una sola testnet. La fuente
  oficial sigue recomendándola para aplicaciones; Hoodi se orienta a validadores.
  Una testnet no ofrece conservación perpetua ni acreditación legal.
- Fijación propuesta para implementar 9B: **Solidity 0.8.37**, **Foundry v1.8.5**
  (Forge/Cast/Anvil), **OpenZeppelin Contracts v5.7.0**, solo Ownable/Ownable2Step.
  Tags/SHA y fuentes fechadas en ADR-0014. Pragma exacto `0.8.37`,
  `solc_version = '0.8.37'`, `evm_version = 'cancun'`, optimizer activado,
  200 runs, `via_ir = false`. Evita depender del target más reciente implícito.
  Compatibilidad propuesta por versiones/pragmas, **no compilada en 9A**.
  9B fijará dependencias y checksums de binarios, sin nightly/latest flotante.
- Foundry exclusivamente; sin Hardhat, proxies, NFT, tokens, pagos, transferencias,
  multichain ni wallet del alumno. OpenZeppelin evita mantener transferencia de
  administrador propia; la alternativa estándar Solidity exigiría implementar
  y auditar ese control. Seguimiento de seguridad y revisión al actualizar en 9B.

| Entorno | Incluida | Confirmada | Finalizada |
|---|---|---|---|
| Anvil | receipt exitoso, evento/estado y bloque canónicos | 1 confirmación | `not_applicable`; Anvil no demuestra finalidad PoS |
| Sepolia | mismos controles | >=12 confirmaciones canónicas | bloque de inclusión ancestro de `finalized`, con los controles anteriores |

Confirmaciones = `head.number - receipt.blockNumber + 1`, solo si el hash del
bloque de inclusión permanece canónico. Envío aceptado por RPC no es inclusión.
12 es una política conservadora de demo, no garantía matemática ni finalidad.
No inferir finalidad de un temporizador ni de `safe`. Si el proveedor no soporta
`finalized`, conservar confirmed y `finality=unknown`; no anunciar finalized.
`checked_at`, número/hash de head y bloque finalized se conservan por observación.

Antes de firmar y en cada reconciliación: eth_chainId, código del contrato,
versión y manifiesto de despliegue (dirección, hash del runtime exacto, bloque/hash
de despliegue, genesis hash del entorno). El manifiesto de Anvil distingue resets
incluso con igual chain ID/dirección; nunca se reutiliza evidencia tras reset.
Sepolia usa explorador configurado de confianza, por ejemplo
[Sepolia Etherscan](https://sepolia.etherscan.io/); el usuario no aporta el RPC.

Revisar hash canónico de cada inclusión no finalizada en cada pasada, antes de
publicar evidencia y al reanudar el worker. Releer estado a ese bloque, y head.
Reorg: invalidar evidencia vigente, confirmations=0, logical state=reorged;
conservar receipt anterior como observación orphaned, localizar la nueva
inclusión o reemitir el mismo contenido tras revalidación. Un cambio del bloque
previamente finalized detiene escrituras y fija divergence: requiere operador,
no un reintento automático. Incluso evidencia finalizada se contrasta al consultarla;
una lectura cacheada lleva su fecha y no simula una lectura en vivo.

## 3. Privacidad, clave y compromiso

Publicar SHA-256 documental permitiría reconocer un PDF conocido y correlacionar
copias. Omitirlo del API no lo ocultaría si estuviera en calldata/eventos/estado.
Se selecciona **compromiso con salt privado y apertura fuera de cadena**.
El hash documental sigue siendo SHA-256 de bytes exactos del PDF final; no hash
de Base64, JSON, ruta, nombre, renderizado ni PDF vuelto a guardar.

Definiciones binarias normativas (H/K/C usan SHA-256, no Keccak-256):

```text
U = 16 bytes de credential_code
K = SHA256(UTF8("certichain:certificate-key:v1") || 0x00 || U)
I = issuerId aleatorio opaco, 32 bytes, persistente por institución/despliegue
H = SHA256(bytes exactos del PDF almacenado), 32 bytes
S = salt aleatorio privado por anclaje, 32 bytes
C = SHA256(UTF8("certichain:document-commitment:v1") || 0x00 || K || I || H || S)
```

`||` concatena bytes sin separadores adicionales. Los prefijos son ASCII/UTF-8
sin BOM ni salto de línea; incluyen exactamente un NUL final. K y C tienen
dominios distintos. UUID: mismo formato aceptado por API v1, 36 caracteres ASCII
8-4-4-4-12, sin trim/llaves/URN; aceptar caso equivalente, pasar a minúsculas,
quitar los cuatro guiones y decodificar parejas hex de izquierda a derecha.
No `Guid.ToByteArray()` con endian mixto; no UTF-8 de la cadena UUID dentro del
hash. No se restringe versión de UUID de entrada; nuevas publicaciones son UUID
aleatorios del servidor. K no depende del certificado interno ni de la red:
es estable para el mismo credential_code. La identidad del registro incluye
además chain ID + dirección + versión de despliegue.

H, K, I, S y C son bytes32: en límites JSON, `0x` seguido de **64 hex minúsculos**;
se decodifican a 32 bytes, sin padding, truncado ni invertir endian. H actual en
SQL son 64 hex sin `0x`: quitar/añadir prefijo exclusivamente en el adaptador.
Direcciones son 20 bytes; transporte interno `0x` +40 hex minúsculos. ABI estándar
Solidity codifica argumentos estáticos en palabras de 32 bytes; esta codificación
ABI **no** se usa como preimagen de K/C. El contrato recibe K/C/I, no los calcula.

Los hashes propios de EVM (transacción, bloque, selector y topic de evento) usan
las reglas Ethereum/Keccak-256, no esta fórmula SHA-256. Hash local de tx es
Keccak-256 del sobre firmado EIP-1559 completo (0x02 + RLP); no SHA-256 del PDF
ni del JSON. runtimeCodeHash del manifiesto se define como Keccak-256 de los
bytes de eth_getCode decodificados. calldataDigest/payload_digest son SHA-256
de calldata ABI exacta (selector incluido): no JSON ni fees/nonce, por lo que
un replacement conserva ese digest. La biblioteca del adaptador implementará
ABI/RLP/secp256k1 estándar; no implementar criptografía EVM propia en 9C.

Salt generado con CSPRNG (`crypto.getRandomValues` backend) al crear la solicitud
durable, nunca UUID/fecha/PRNG común. I se genera igualmente con CSPRNG y se
rechaza cero. S se conserva privado antes de firmar, con backup protegido de BD;
reintentos, fee replacement, reinicio y reorg reutilizan exactamente S/K/I/H/C.
Perder S exige restaurar backup: nunca inventar otro para la misma clave. Si no
es recuperable, detener nuevas escrituras y declarar apertura unavailable;
el registro existente sigue observable, pero no se puede abrir el compromiso.

Acceso futuro a apertura mediante endpoint autenticado distinto: titular propio,
o owner/admin/issuer actual de emisora verified, con los controles de 7C sobre
publicación coherente. Plataforma sin propiedad/membresía no recibe apertura.
El titular conserva acceso al suspender al emisor. Respuesta no-store con
protocol_version, credential_code, issuer_id, document_sha256, salt y localizador
de contrato; sin PDF ni capacidad Storage. No enlaces/QR con apertura, logs,
preferencias ni endpoint público. El receptor autorizado puede entregarla
voluntariamente a un tercero; no se puede retirar lo ya compartido.

Con apertura y copia: tercero calcula H/K/C y compara C/I y estado contra el
contrato/bloque canónico, sin confiar en la comparación de hashes del backend.
Sin apertura: comprueba presencia del compromiso, emisor opaco, tiempos,
revocación y transacción; **no puede probar que su PDF corresponde a C**.
La comparación pública candidata v1 continúa confiando en el hash esperado de
Supabase, incluso si devuelve match. El backend no puede sustituir un C registrado
sin que cambie la prueba; sí sigue siendo confiable para autorizar y atribuir
instituciones, identidades y metadatos académicos.

K es opaco pero no secreto: quien conoce el QR/código puede derivarlo y observar
actividad. I agrupa certificados de una institución; dirección de servicio,
timestamps y transacciones permiten correlación. Una apertura revela H para ese
registro. Salts distintos evitan comparar públicamente documentos iguales por C.
No se afirma anonimato ni ausencia de riesgo de identificación indirecta.

### Vector sintético reproducible

Se usa `pdfFixture()` existente en `supabase/tests/pdf_fixture.mjs`, PDF sintético
de 330 bytes; no contiene datos reales. Valores/resultados comprobados en 9A;
9B/9C deberán compartirlos como vectores, no reinterpretarlos.

```text
credential_code = 00112233-4455-6677-8899-aabbccddeeff
U = 00112233445566778899aabbccddeeff
I = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
S = 202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f
H = 598c50f845d76f4fe6125df9906750584668e526be96e78ca43548eb60f20b1f
K = ca2b59a1b252b8233c8966af500b93f84873c2c3ca7642dab5f4470597c49638
C = 9b81a31ebdcfdb3b0fa0d60c557485c6b5d55e0e77e7730a2cf202c9a66155f4
key_preimage_bytes = 46
commitment_preimage_bytes = 162
```

I y S secuenciales solo en este vector. En producción/demo se generan aleatorios;
S no es una clave de firma. Prefijo `0x` omitido arriba para leer los bytes.

## 4. Contrato CertificateRegistry v1 y autoridad

Contrato mínimo sin actualización, borrado, transferencias de certificados ni
llamadas externas. Constructor recibe administrador no cero. Administrador y
firmante operativo distintos por política del backend y del manifiesto de
configuración; Ownable2Step no garantiza esa separación por sí solo.
`protocolVersion()` devuelve uint16 **1**. Funciones nonpayable, sin receive ni
fallback que acepten fondos. Ownable2Step para transferir
administración con aceptación; `renounceOwnership()` se sobrescribe para revertir
`RenounceDisabled()`. Es distinto de institution_members.role='owner'.

```solidity
// ABI objetivo; implementación y compilación pertenecen a 9B.
function protocolVersion() external pure returns (uint16);
function setIssuer(bytes32 issuerId, address signer, bool canIssue, bool canRevoke) external;
function getIssuer(bytes32 issuerId) external view
    returns (address signer, bool canIssue, bool canRevoke);
function issue(bytes32 certificateKey, bytes32 commitment, bytes32 issuerId) external;
function exists(bytes32 certificateKey) external view returns (bool);
function getCertificate(bytes32 certificateKey) external view
    returns (bytes32 commitment, bytes32 issuerId, uint64 registeredAt, uint64 revokedAt);
function revoke(bytes32 certificateKey) external;

event IssuerConfigured(bytes32 indexed issuerId, address indexed signer, bool canIssue, bool canRevoke);
event CertificateIssued(bytes32 indexed certificateKey, bytes32 indexed issuerId,
    bytes32 commitment, address signer, uint64 registeredAt);
event CertificateRevoked(bytes32 indexed certificateKey, bytes32 indexed issuerId,
    address signer, uint64 revokedAt);

error InvalidInput();
error IssuerUnauthorized(bytes32 issuerId, address caller);
error CertificateAlreadyExists(bytes32 certificateKey);
error CertificateNotFound(bytes32 certificateKey);
error CertificateAlreadyRevoked(bytes32 certificateKey);
error RenounceDisabled();
```

Estado: mapping K → registro {C,I,registeredAt,revokedAt}; mapping I → configuración.
Existencia se guarda explícitamente (mapping bool o campo bool privado), nunca
se deduce del timestamp. Consulta ausente revierte CertificateNotFound; exists
ausente/cero devuelve false. `registeredAt`/`revokedAt` son block.timestamp en
segundos uint64, no issued_at SQL ni fechas académicas; require timestamp cabe
en uint64 y es >0. No hay expires_at on-chain. Revocación booleana se deriva
de revokedAt>0, es irreversible y no borra C/I ni cambia registeredAt.

Orden de validación de issue: K/C/I no cero → autorización actual de I →
unicidad K → timestamp → escritura/evento único. Autorización requiere signer
no cero, msg.sender=signer y canIssue. Cualquier K existente, idéntico o con C/I
distintos, revierte CertificateAlreadyExists. No hay upsert ni éxito silencioso.
Revocar: K no cero → existencia → autorización del I **almacenado** con
canRevoke → no revocado → timestamp/escritura/evento. Segunda revocación autorizada
revierte CertificateAlreadyRevoked. No se recibe I arbitrario para revocar.

setIssuer solo administrador: I no cero; signer no cero si algún permiso true.
signer cero permitido exclusivamente con ambos false. Repetir configuración
idéntica no emite evento; cambio efectivo emite IssuerConfigured. Configuraciones
ausentes devuelven cero/false/false. No se elimina I ni se reasigna su institución.
Restricciones/errores de owner/transferencia/aceptación son los de Ownable2Step
fijado, incluidos OwnableUnauthorizedAccount y OwnableInvalidOwner.
Administración no concede emisión/revocación por sí sola.

La institución se vincula en una tabla privada a I estable. MVP: un único EOA
operativo de servicio, distinto del EOA administrador, puede configurarse para
varios I. On-chain verifica **el permiso de ese EOA para ese I** y la pertenencia
del certificado al I en revocación; no conoce Auth ni owner/admin/issuer humanos.
Una dirección compartida no identifica institución y puede actuar por cualquier
I que tenga asignado. Su compromiso afecta a todos esos emisores. La atribución
I↔institución y la autorización humana confían en plataforma/backend; no se
presenta como firma criptográfica personal de la universidad. Usar una cuenta por
institución ampliaría custodia y nonces; queda fuera de esta demo.

| Operación | Actor humano/servicio | Validación backend | Autorización on-chain |
|---|---|---|---|
| Emitir off-chain | owner/admin/issuer institucional | Auth real, membresía actual, verified, titular y PDF según 7B | Ninguna todavía |
| Solicitar anclaje | owner/admin/issuer emisora | mismos controles de actor/institución; completed, active, vínculos/hash/ruta y bytes íntegros | servicio: signer(I), canIssue |
| Reintentar/reautorizar anclaje | actor autorizado actual | revalidar lo anterior, misma operación/K/C; registrar nuevo actor autorizado | mismos permisos I |
| Solicitar revocación (10) | owner/admin emisora | Auth/membresía real; institución verified **o suspended**; certificado suyo | servicio: signer(I almacenado), canRevoke |
| Configurar I/permisos/rotar | operador de plataforma + administrador EVM | mapear institución real; acción administrativa explícita y auditada | owner del contrato |
| Consultar evidencia | cualquiera | proyección pública mínima; no abre PDF/salt | view sin permisos |
| Abrir compromiso | titular o miembro autorizado | política de 7C, no platform_admin implícito | fuera de cadena |

Suspensión: impedir nuevas solicitudes/firmas de emisión inmediatamente en BD;
solicitud administrativa durable pone canIssue=false, canRevoke=true en cadena.
Pending/rejected tampoco emiten y no solicitan revocación de producto; un operador
puede investigar sin suplantar owner/admin. Suspender no revoca certificados.
Si la sincronización de permisos falla, backend bloquea emisión y expone demora
administrativa; el EOA todavía autorizado podría escribir directamente hasta que
la transacción de retirada se incluya. No prometer atomicidad BD/EVM.

Rotación cambia signer de I, conservando I, C y registros: nuevo firmante revoca
certificados previos; antiguo pierde permisos desde inclusión canónica del cambio.
Retirada total fija cero/false/false; conserva consultas/historial y bloquea
revocación hasta nueva habilitación explícita. Backend no firma usando configuración
no reconciliada. Cambios de miembros solo alteran autorización backend; no hacen
al miembro una dirección EVM. Una transacción ya firmada/enviada no se puede
desfirmar al retirar al usuario: carrera reconocida y conciliada/auditada.

Datos permitidos en calldata/estado/eventos: K, C, I, direcciones técnicas,
permisos bool, versión y tiempos de bloque; selectores/ABI correspondientes.
Los receipts incluyen datos públicos de gas/nonce/bloque. **Nunca H/S/UUID en
texto, nombres, emails, DNI, titular, título legible, rutas, URL privada, PDF ni
motivo interno de revocación**, también en errores, constructor y scripts.
No cadenas libres/bytes arbitrarios de aplicación. Blockchain no comprueba
identidad del alumno ni veracidad académica ni que el compromiso esconda un PDF.

## 5. Puerto backend e infraestructura futura (9C)

Endpoint futuro `POST /functions/v1/anchor-certificate`, verify_jwt=true y Auth
real (mismo límite de confianza que issue-certificate). Entrada JSON cerrada
UTF-8 <=2 KiB: certificate_id UUID canónico e idempotency_key UUID; actor,
institución, red, contrato, K/C/I/H/S y signer se resuelven en servidor, no del
cliente. 202 con operation_id/status para nueva solicitud; 200 para recuperar
operación existente, sin afirmar confirmación. 401 sesión inválida, 403 actor
no autorizado/institución no verified, 404 publication_unavailable uniforme,
409 idempotency_conflict/busy, 503 temporary_failure. Sin hash/salt/ruta/secretos,
no-store y sin mensajes upstream. Worker no se invoca mediante endpoint público.

Misma clave de solicitud bajo institución/tipo y distinto certificado es
conflicto; mismo anchor/type con nueva clave recupera la operación existente,
nunca otro issue. Toda recuperación vuelve a autorizar al actor actual. Si la
operación está blocked por baja del actor original, la reautorización se solicita
explícitamente por una RPC técnica con Auth resuelto; no se adopta silenciosamente
al consultar estado. El tipo revoke y su motivo privado se habilitan solo en 10.
Consulta de progreso privada futura también mediante backend autenticado, por
operation_id con pertenencia a la emisora actual; no SELECT directo de tablas
operativas ni apertura al titular de nonces/raw/salt por conocer un UUID.

Ubicación propuesta: `supabase/functions/_shared/blockchain/domain/` para DTO y
contrato TypeScript puro, `.../data/evm_registry.ts` para ABI/RPC; coordinador en
`supabase/functions/_shared/blockchain/application/`, worker confiable invocado
explícitamente por operador. No polling prolongado dentro de una petición Edge.
Un comando de `supabase/admin/` iniciará pasadas acotadas del mismo coordinador.
No crear estos archivos en 9A. Flutter mantiene feature-first y repositorios
propios, sin EVM/Web3/secretos en dominio o UI.

```typescript
interface BlockchainRegistry {
  validateDeployment(expected: Deployment): Promise<ChainObservation>;
  prepare(command: RegistryCommand, nonce: bigint, fees: Fees): Promise<PreparedTx>;
  broadcast(prepared: PreparedTx): Promise<{ transactionHash: Bytes32 }>;
  observe(transactionHash: Bytes32): Promise<TransactionObservation>;
  read(certificateKey: Bytes32, block: BlockRef): Promise<RegistryRecord | null>;
  issuer(issuerId: Bytes32, block: BlockRef): Promise<IssuerConfiguration>;
}
// prepare usa un Signer privado inyectado; no devuelve la clave privada.
// setIssuer se prepara solo en sesión operativa con Signer administrador separado.
// RegistryCommand = issue{K,C,I} | revoke{K} | setIssuer{I,signer,canIssue,canRevoke}
// Deployment = chainId, contractAddress, protocolVersion, runtimeCodeHash,
//              deploymentBlock{number,hash}, genesisHash, environmentId
// PreparedTx = hash local, rawSignedTx, chainId, to, signer, nonce,
//              calldataDigest, gasLimit, maxFeePerGas, maxPriorityFeePerGas
// RegistryRecord = K,C,I,registeredAt,revokedAt
// ChainObservation = head{number,hash}, finalized{number,hash}|null, checkedAt
// TransactionObservation = unknown | pending | included{receipt,record,chain}
// receipt = hash,status,from,to,block{number,hash},transactionIndex,logs,gasUsed
```

Bytes32 se valida según sección 3; cantidades EVM bigint en dominio, decimal
string en JSON/SQL (no JS number con pérdida); IDs chain limitados al MVP.
BlockRef siempre número **y hash esperado**, no latest ambiguo: verificar hash
antes/después si el RPC no acepta referencia por hash. `read=null` solo por
exists=false en una lectura canónica exitosa; nunca por timeout.

Errores cerrados: invalid_input, authorization_denied, duplicate_key,
already_revoked, key_conflict, rpc_unavailable, rpc_timeout, insufficient_funds,
nonce_conflict, transaction_reverted, deployment_mismatch, incompatible_evidence,
reorg, divergence, opening_unavailable. Reverts se traducen desde ABI; datos RPC
crudos no llegan a cliente/logs. prepare/broadcast no garantizan éxito; hash local
ya permite reconciliar respuesta perdida. observe unknown no equivale a dropped.
El coordinador resuelve idempotencia con read/receipts/eventos; el contrato
rechaza duplicados incluso idénticos. Esta interfaz no sustituye autorización SQL.

## 6. Persistencia propuesta para migración nueva 9C

Todas las tablas siguientes en `certichain_private`, no expuesto a PostgREST;
RLS habilitada sin políticas cliente, REVOKE PUBLIC/anon/authenticated/service_role.
Acceso técnico solo por RPC SECURITY DEFINER estrechas, search_path vacío y
tablas cualificadas, EXECUTE service_role. Sin nuevo SELECT público ni DML en
certificates para clientes. Constraints/triggers deben impedir cambiar identidad
del anclaje después de crear; no reutilizar nombres antiguos blockchain_records.

| Tabla propuesta | Campos y reglas principales |
|---|---|
| blockchain_deployments | id UUID; environment_id; network anvil/sepolia; chain_id bigint>0; contract_address bytea(20); protocol_version=1; genesis/runtime hashes bytea(32); deployment_block/hash; enabled; política de confirmaciones/finalidad; UNIQUE(environment_id,chain_id,contract_address), un despliegue habilitado por entorno |
| blockchain_issuers | id UUID; deployment_id FK; institution_id FK RESTRICT; issuer_id bytea(32) no cero; signer bytea(20); desired_can_issue/revoke; observed_can_issue/revoke, observed_signer, observed_block/hash; configuración/version durable y estado de sync; UNIQUE(deployment_id,institution_id), UNIQUE(deployment_id,issuer_id); correspondencia institución↔I inmutable |
| certificate_anchors | id UUID; certificate_id, issuance_operation_id, institution_id FK; deployment_id/issuer_binding_id FK; credential_code_snapshot, certificate_key, document_sha256, salt, commitment (32 bytes); created_at; UNIQUE(certificate_id,deployment_id), UNIQUE(deployment_id,certificate_key) |
| blockchain_operations | id UUID; anchor_id nullable para admin, issuer_binding_id; kind issue/revoke/set_issuer; requested_by/authorized_by FK perfil privados; idempotency_key UUID; payload_digest bytea(32); estado durable; lease_token/until, generation bigint, next_attempt_at; last_error cerrado; canonical_attempt_id; confirmations; finality unknown/not_applicable/finalized; checked_at/head/finalized refs; created/updated_at |
| blockchain_transaction_attempts | id UUID; operation_id FK; attempt_number; signer, nonce numeric(78,0)>=0; transaction_hash bytea(32); raw_signed_tx restringida; calldata_digest; fees/gas enteros; replaces_attempt_id; estado prepared/submitted/pending/included/reverted/replaced/orphaned/unknown; submitted_at; receipt_status; block_number/hash/index; validated_log_index; observed_at; UNIQUE(operation_id,attempt_number), UNIQUE(deployment_id,transaction_hash) mediante relación deployment protegida |
| blockchain_signer_nonces | deployment_id, signer PK; next_nonce numeric(78,0); active_operation_id; lease/fencing generation; un solo nonce lógico sin resolver por firmante en MVP |

9C añadirá UNIQUE(id,institution_id,issuance_operation_id) a certificates y
UNIQUE(id,institution_id,certificate_id) a certificate_issuance_operations, sin
reescribir filas. FK de anchor (certificate_id,institution_id,issuance_operation_id)
→ certificates(id,institution_id,issuance_operation_id) y
(issuance_operation_id,institution_id,certificate_id)
→ certificate_issuance_operations(id,institution_id,certificate_id).
La identidad actor/titular/hash continúa protegida por las FK compuestas actuales;
no duplicar datos del titular en anchor. RPC verifica completed/coherencia/hash.
Binding añade UNIQUE(id,institution_id,deployment_id); anchor lo referencia por
esas tres columnas. No usar una FK simple que permita cruzar emisor y deployment.
`bytea(32)`/`bytea(20)` en esta tabla son notación de longitud, no sintaxis SQL:
el tipo es bytea, con CHECK octet_length=32/20;
hashes/direcciones nunca texto arbitrario. Comprobar K/C desde la entrada
backend y congelar U/I/H/S; la futura migración no deriva valores para históricos.

Operaciones administrativas conservan target_signer/can_issue/can_revoke y
config_version como snapshot inmutable, no reconstruyen calldata desde una
configuración deseada posteriormente sobrescrita. Operaciones issue/revoke
obtienen K/C/I del anchor inmutable. authorized_by puede cambiar solo mediante
RPC de reautorización que añade historial privado append-only de actor, rol y
fecha; máximo 64 entradas por operación, después revisión operativa. Intentos
guardan authorized_by de la firma. No se borra al actor original requested_by.

Issue/revoke: UNIQUE parcial (anchor_id,kind); set_issuer: UNIQUE(issuer_binding_id,
config_version). UNIQUE(issuer_binding_id,kind,idempotency_key) para solicitud y
payload_digest inmutable: clave repetida/contenido distinto es conflicto.
Una nueva tx por sustitución pertenece a la **misma operación lógica** y anchor,
no crea certificado, salt ni clave nuevos. Nonce reservado único por
(deployment,signer,nonce) a nivel operación; varios attempts con ese nonce solo
se permiten como replacements de esa operación. FK canonical_attempt exige
pertenencia a la operación. Revoke puede encolarse mientras issue está en vuelo,
pero solo se prepara/envía después de issue observado; no permite inventar
una emisión distinta para anclar una revocación.

Índices: operaciones (state,next_attempt_at) para cola, (lease_until) para
vencidas, anchors(certificate_id), intentos(operation_id,attempt_number),
intentos(deployment_id,signer,nonce), issuer sync pendiente. Estado/lease por
CHECK: no lease sin token, confirmed necesita receipt canónico exitoso y evento
validado; finalized solo Sepolia con bloque finalized; no estado final por envío.
Guardar observaciones de receipt en `receipt_observations` JSONB append-only del
intento, con formato cerrado {status,block_number,block_hash,transaction_index,
validated_log_index,observed_at,canonical}; máximo 64 observaciones, después
revisión operativa. Marcar orphaned mediante nueva observación que referencia el
hash anterior, sin borrar historia. Una reinclusión del mismo tx añade observación,
sin crear otro intento firmado; los campos canónicos de la fila reflejan la última
observación validada. En esa notación canonical admite true/false/unknown, sin
inferir false de timeout RPC. El estado orphaned del intento se usa cuando no
existe nueva inclusión válida. No se crea otra tabla de receipts en el MVP.
Añadir observación solo si cambia inclusión o canonicidad, no por cada pasada;
checked_at/confirmations de la operación se actualizan sin ampliar ese historial.

Retención MVP: anchors, salt, operaciones, binding e historial de evidencia se
conservan mientras se conserve el certificado; sin cascadas destructivas ni
limpieza automática. Backups con el mismo acceso privado y prueba de restauración
9C. Raw signed tx se conserva hasta finalidad Sepolia, o cierre local explícito
de Anvil, y se purga 7 días después; metadatos/receipts mínimos permanecen. Una
tx firmada es retransmisible: no logs/artefactos públicos. Motivo de revocación
queda en registro privado fase 10, no payload on-chain. Política legal de datos
personales y borrado requerirá decisión antes de producción.

Cuatro dimensiones independientes:

| Dimensión | Fuente y significado |
|---|---|
| certificate.status | active/revoked; expired derivado; estado del registro CertiChain |
| issuance.status | completed significa publicación SQL coherente con PDF, sin EVM |
| anchor/operation.state | requested/prepared/submitted/included/confirmed/reorged/blocked/failed/divergence; sin anchor equivale a off_chain_only |
| file_integrity | match/integrity_mismatch/unavailable, sobre la copia; no cambia estado de certificado |

Transiciones lógicas: requested→prepared→submitted→included→confirmed;
prepared/submitted pueden volver a observarse sin crear otra operación. Included/
confirmed→reorged si bloque huérfano; reorged→included por reinclusión validada o
→prepared para reenvío/replacement autorizado. Error transitorio conserva estado
y last_error; falta de permiso/fondos/configuración→blocked; revert terminal→failed;
conflicto/incompatibilidad→divergence. Blocked/failed solo vuelven a requested
por reautorización explícita sobre identidad inmutable, tras reconciliar todos
los intentos; divergence requiere resolución operativa, nunca retry silencioso.
Finality es dimensión adicional, no sinónimo de completed o confirmed. No añadir
anchoring/anchor_failed al enum certificate_status. Los consumidores antiguos
siguen leyendo exactamente active/revoked y v1.

## 7. Recorrido, transacciones SQL y firma

Publicación 7B coherente → solicitud explícita durable → revalidación → preparación
firmada durable → envío → receipt → confirmaciones → evidencia → reconciliación.
Para el MVP la solicitud de anclaje es un endpoint autenticado **separado** futuro,
por certificate_id: no se presupone que completed encole blockchain. Se usa para
nuevos certificados y, solo por acción autorizada explícita, para un publicado
anterior elegible. Históricos sin operación/hash/PDF coherentes siguen excluidos;
necesitarían revisión/migración específica distinta, nunca backfill silencioso.

1. **T0 actual:** publicación/completed en una transacción, sin modificaciones 9A.
2. **T1 futura:** Auth real; institución FOR UPDATE → emisión/certificado → binding
   → anchor/operación. Verificar owner/admin/issuer, verified, completed/coherencia,
   active (caducado no se ancla en demo), datos inmutables y despliegue. Leer y
   verificar PDF fuera del lock; revalidar snapshot/hash al insertar solicitud.
   Generar S/C una vez; UNIQUE devuelve misma operación bajo concurrencia.
   Persistir authorized_by y requested. Fallo revierte solicitud, conserva T0.
3. **T2:** mismo orden padre primero para claim y revalidación. Lease 120 s, token
   nuevo/generation incrementada; renovar cada 30 s, llamadas RPC límite 10 s.
   Otro worker obtiene busy; vencido solo retoma con CAS/token actual. Revisar
   deployment y read(K) fuera de SQL antes de decidir enviar.
4. Si read encuentra C/I iguales, recuperar evidencia issue original mediante
   evento/receipt desde bloque de despliegue (páginas <=2000 bloques), validar y
   reconciliar. Si difiere, divergence; no escribir. Un registro ya revocado
   exige conciliar revocación, no devolver emisión activa ficticia.
5. **T3:** serializar fila nonce del EOA; no otro nonce sin resolver para este
   firmante. Comparar getTransactionCount pending/latest con reservas conocidas.
   Obtener fees/estimateGas/simulación fuera de SQL; revalidar permisos y lease
   antes de firmar. Firmar EIP-1559 con chain ID/dirección fijados; persistir raw,
   hash local, nonce y payload en transacción antes de broadcast. Si falla commit,
   no enviar. No usar eth_sendTransaction ni cuentas desbloqueadas del RPC.
6. Fuera de SQL: enviar **los mismos bytes firmados** con sendRawTransaction.
   **T4:** CAS persiste submitted/hash o respuesta incierta. Crash tras T3/T4 se
   resuelve por hash local, tx, receipt, nonce y read(K), nunca otra emisión.
7. Pasadas acotadas cada 5 s local /15 s Sepolia, deadline 30 s por pasada: validar
   receipt status=1, from/to, chain/contract/version, selector/calldata, evento
   del contrato exacto K/C/I/signer y timestamp, log index, bloque canónico y
   estado en ese bloque. Revoke debe coincidir con I/C previos. Receipt exitoso
   sin evento/estado compatible es incompatible_evidence, nunca confirmed.
8. **T5:** persistir observación included; contar y promover confirmed/finality
   según sección 2. No mantener locks durante RPC. Reconciliación continúa hasta
   finalidad y en lectura posterior; error nunca borra PDF/certificado/completed.

Los locks SQL no impiden una escritura EVM ni hacen atómicos PostgreSQL/Storage/
EVM. Existe ventana entre revalidación y broadcast/minado. La autorización se
garantiza en cada transacción backend; un cambio posterior no cancela bytes
firmados. La retirada on-chain es efectiva según el orden canónico de ejecución.
Un proceso con lease vencido no cambia BD; podría retransmitir bytes ya firmados:
serán mismo nonce/payload y se reconcilian. El MVP usa un worker firmante activo;
no promete fencing criptográfico de EOA con leases SQL.

Nonces: cuentas exclusivamente usadas por este worker; admin separado no consume
sus nonces. Reservar desde max(pending RPC, siguiente reservado) solo tras
resolver reservas previas; no reciclar nonce por timeout. Pending >5 minutos:
operador/worker revalida, permite hasta 3 replacements con mismo nonce/to/data/
value=0 y ambas fees aumentadas al menos 20%, dentro del presupuesto configurado.
Si el proveedor exige más o se supera presupuesto, blocked y operador. No tx
de cancelación automática. Nonce consumido por tx desconocida: detener firmante,
localizar tx y reconciliar; no saltar el hueco creando otro certificado.
Errores transitorios usan next_attempt_at 15/30/60 s, después máximo 5 min;
reintentos solo worker, sin bucle indefinido de petición HTTP. Failed no se
reabre automáticamente: nueva autorización explícita sobre la misma operación
conserva identidad y añade intento si el fallo era subsanable.

## 8. Fallos y recuperación normativa

Resultado visible futuro se refiere al anclaje; v1/estado off-chain se conservan.

| Caso | Estado durable | Recuperación / reintento | Resultado visible |
|---|---|---|---|
| RPC caído/lento antes de firma | requested + rpc_unavailable/timeout, next_attempt_at | reintento acotado/revalidado; sin tx nueva hasta inspección | pendiente o evidencia temporalmente no comprobable |
| Falta de fondos/fees fuera de presupuesto | blocked + insufficient_funds | operador financia solo ETH de prueba, reautoriza; misma operación | anclaje bloqueado, certificado off-chain conservado |
| Revert incluido | intento reverted, operación failed, receipt canónico | clasificar permiso/duplicado; duplicado idéntico recupera tx original; diferencia divergence; otros fallos requieren corrección/reautorización | fallo de anclaje, no PDF alterado |
| Respuesta perdida al enviar | prepared/submitted + intento unknown | hash calculado antes de enviar; consultar y retransmitir mismos bytes si no hay inclusión; no declarar dropped por un null RPC | pendiente/incierto |
| Respuesta perdida tras confirmar/commit | estado anterior o confirmed durable | observar receipt/read y repetir T5 con CAS; sin nueva solicitud | evidencia recuperada con fecha de observación |
| Tx pendiente | submitted, intento pending, nonce reservado | esperar; replacement acotado según sección 7; revalidar permisos | pendiente |
| Tx sustituida | antiguo replaced, nuevo intento ligado, mismo nonce | buscar todos los hashes; aceptar solo inclusión válida del payload lógico; el viejo puede ganar | mismo anclaje pendiente/confirmado |
| Tx no encontrada/descartada | unknown, nonce retenido | consultar nonce/cadena, rebroadcast mismos bytes; nonce libre no prueba que no reaparecerá | incierto; nunca not_found del certificado |
| Reintentos concurrentes | operación única, lease/CAS, busy para segundo | recuperar dueño vencido; identity conflict si payload cambia; sin salt nuevo | progreso de misma solicitud |
| Reinicio | filas prepared/submitted/included durables | retomar leases vencidos, raw/hash/nonce y observaciones; verificar deployment | recuperación sin duplicación |
| Receipt/evento incompatible | divergence + incompatible_evidence, receipt conservado | detener esa operación, operador inspecciona ABI/to/log/calldata; no promover ni sobrescribir | discrepancia de evidencia |
| Red/contrato/reset incorrectos | blocked + deployment_mismatch | detener firmante y corregir manifiesto explícitamente; no copiar evidencia entre entornos | no comprobable/error de configuración |
| Reorg antes de finalidad | reorged, receipt orphaned, cero confirmaciones | buscar reinclusión; si ausente revalidar y reenviar mismos datos; no perder observación anterior | evidencia anterior invalidada, pendiente |
| Reorg después de finalidad | divergence, escrituras del deployment detenidas | investigación del operador/proveedor; no reintento automático | discrepancia crítica, sin finalidad vigente |
| Membresía retirada/suspensión | blocked authorization_denied si no enviado | nuevo actor autorizado puede reautorizar misma operación con auditoría; no firma con permiso obsoleto | anclaje bloqueado; v1 puede issuer_unavailable |
| Permiso cambiado con tx ya enviada | submitted + autorización modificada registrada | observar inclusión/revert; no asegurar cancelación; reconciliar resultado real | pendiente hasta evidencia, advertir origen/fecha |
| BD sin receipt pero cadena con mismo K/C/I | requested/submitted hasta comprobación | recuperar evento original/receipt, validar bloque/confirmaciones y completar T5; no issue repetido | confirmado solo al recuperar evidencia |
| BD confirmed, cadena ausente/diferente | reorged si orphan confirmado; en otro caso divergence | invalidar evidencia, distinguir RPC técnico de ausencia canónica; operador si conflicto | pendiente/discrepancia, no valid on-chain |
| Salt perdido/PDF almacenado distinto | blocked opening_unavailable o divergence | restaurar backup/bytes originales; no C nuevo ni replace PDF | apertura/integridad no disponible; registro externo sigue observable |

Revocación externa por EOA autorizada detectada al leer: persistir evidencia
revoked, divergence si BD active; fase 10 debe reflejar revocación bajo RPC técnica
auditada. Hasta resolver, v2 no presenta conjunto coherente válido. No ignorar
la discrepancia porque v1 siga active; v1 mantiene su significado de registro SQL.

## 9. Conectividad y secretos (plan 9C)

Anvil en red Docker propia, servicio `anvil:8545` para worker/backend en esa red.
Loopback del contenedor no es el host. Si Edge runtime se mantiene en red Supabase,
conectar explícitamente el worker a ambas redes; alternativa local Docker Desktop
`host.docker.internal` solo con puerto del host publicado en 127.0.0.1. Verificar
resolución/alcance en aceptación; no asumir que 127.0.0.1 dentro de Edge sirve.
Anvil escucha en interfaz interna necesaria del contenedor; host binding
127.0.0.1:8545, sin proxy público ni 0.0.0.0 del host. Sus métodos admin/unlocked
solo en pruebas aisladas. Flutter nunca recibe URL RPC privilegiada.

Cuentas Anvil efímeras y conocidas solo para desarrollo, nunca fondos reales.
Admin y operativo distintos; las claves privadas se inyectan por entorno secreto
backend/CI, sin defaults de demo en producto. Sepolia usa EOA exclusivos de demo,
RPC TLS con credenciales del servidor y fondos testnet; no claves mainnet.
Variables futuras: EVM_RPC_URL, EVM_CHAIN_ID, EVM_REGISTRY_ADDRESS,
EVM_SIGNER_PRIVATE_KEY, manifiesto/version y presupuesto; administrador solo en
sesión operativa de configuración, no en worker ordinario. No se añaden .env
ni valores de claves en 9A. KMS/multisig/custodia avanzada se evalúan antes de
producción, fuera del MVP actual.

## 10. Verificación pública posterior (9D)

Preservar código, enlaces `/#/verify/<credential_code>` y QR actuales, así como
verify-certificate v1 y compare-certificate-hash v1/RPC. Ampliación mediante
endpoint separado **verify-certificate-v2**, schema_version='2', con envelope:
`registry` contiene v1 literal, `blockchain` contiene evidencia mínima y
`checked_at`/`source` propios. Integridad sigue respuesta independiente de
comparación; apertura autorizada es otro endpoint. No introducir campos extras
en v1 ni convertir result='valid' en una garantía on-chain.

Proyección prevista blockchain: state off_chain_only/pending/included/confirmed/
reorged/unavailable/divergence; finality unknown/not_applicable/finalized;
chain_id decimal string, contract_address, protocol_version, certificate_key,
issuer_id, commitment y revoked bool solo cuando exista observación válida;
transaction_hash, block_number decimal string, block_hash, confirmations,
checked_at UTC, source='backend_rpc' o 'persisted_receipt'. En ausencia de
anclaje no inventar transacción/bloque. Error RPC deja unavailable junto a
last_evidence fechado, sin hacerlo actual; not_found v1 no revela evidencia de
certificados que no cumplan elegibilidad pública. Revocación posterior añade
evidencia issue y revoke separada, no reemplaza el tx original de issue.

Esta ampliación de campos opacos es permiso público **futuro**, sin H/S, datos
del titular, ruta, PDF ni motivo. Comprobaciones, ABI y dirección verificable en
explorador permiten contrastar K/C/I/evento/estado/bloque y contar confirmaciones.
Fuente backend_rpc depende del proveedor RPC; el explorador es contraste externo,
no fuente de autorización humana ni prueba del PDF sin apertura. Anvil no tiene
explorador público; evidencia se contrasta en RPC local de pruebas.

Presentación separada: «Registro CertiChain: válido/revocado/...», «Blockchain:
pendiente/confirmado/finalizado/no comprobable», «Mi copia: coincide/no coincide/
no comparada», cada una con fecha/origen. `issued_at` SQL y registeredAt EVM
son fechas distintas. RPC caído no equivale a not_found, revocación ni
integrity_mismatch. Un certificado off-chain válido conserva esa condición sin
anunciar evidencia suficiente on-chain.

## 11. Revocación fase 10 y criterios de siguientes fases

9B implementa revoke y sus pruebas; 9C admite el comando durable en el puerto,
pero no habilita flujo de producto de revocación. Fase 10 añade solicitud Auth
owner/admin, motivo privado, operación idempotente y RPC de transición SQL.
Política: publicar `certificate.status=revoked` inmediatamente en la transacción
autorizada (seguridad conservadora), mantener completed intacto y encolar revoke
si hay anchor incluido/confirmado o issue en vuelo. Cadena puede quedar pendiente;
mostrar ambos estados sin retrasar la advertencia SQL. Off-chain-only se revoca
sin inventar anclaje; cancelar nuevas firmas issue. Si issue ya firmado llega
tarde, observar y revocar con el mismo I/K; no marcar limpio mientras diverjan.
Reorg de revoke nunca reactiva SQL; reintentar misma revocación. Motivo no pasa
a EVM. El trigger histórico no implementa este protocolo y no se altera en 9A.

- **9B:** Foundry fijado; contrato mínimo/ABI/manifiesto; tests autorización,
  duplicados idénticos/distintos, cross-issuer, doble revoke, rotación/retirada,
  eventos, existencia, no renounce, invariantes/fuzz; Anvil local y gas. No backend.
- **9C:** migración nueva, permisos/FK/locks y preservación histórica; puerto,
  adaptador, worker/firma/nonces, backup/restauración de salt; fault injection
  de todos los casos sección 8, inclusiones/reorg/replacements reales en Anvil.
- **9D:** DTO/cliente v2 cerrado, evidencia/fecha/origen separados, contraste en
  explorador y apertura autenticada; códigos/manual/enlaces/QR existentes.
- **9E:** recorrido local real T0→anclaje→confirmación→verificación/apertura,
  fallos/recuperación y permisos; Sepolia demo solo con despliegue autorizado
  posterior y evidencia propia. Nunca sustituir Anvil por dependencia de testnet.
- **10:** recorrido completo de revocación Auth/SQL/EVM/cliente, suspensión,
  tx tardía y reorg; sin escrituras directas ni reversión de revocación.

Cámara en 9A y siguientes: **SKIP/NOT_RUN**, motivo exacto:
«Omitidas por instrucción del usuario; no hay cámara física disponible».
CERTICHAIN_TEST_CAMERA=0 en harnesses; ninguna prueba de captura, permisos,
ciclo de vida, getUserMedia, vídeo emulado ni probe QR nativo. Conservar
implementación/tests existentes y excluir solo escenarios de cámara si la suite
los mezcla. Códigos, enlaces, QR generado/imagen estática, PDF, Auth, backend,
SQL y blockchain siguen verificables. No reabrir 8D por hardware.

## 12. Validación realizada en 9A

Inspección read-only de HEAD/árbol/remoto, migraciones/backend/Flutter y ADR;
run/intento/jobs CI exactos; fuentes oficiales/versiones/tags/pragmas sin instalar.
Vector SHA-256 recalculado con Node crypto y comprobado independientemente con
.NET SHA256; enlaces Markdown locales y coherencia de nombres/estados revisados;
`git diff --check` y revisión de diff para secretos/datos reales/afirmaciones
de ejecución. Solo documentación: no se ejecutan Flutter/SQL/HTTP/Foundry ni 8D,
no reset, migración, firma, envío EVM, despliegue, commit o push.
Esto no acredita compatibilidad compilada ni integración: corresponden a 9B/9C.

## 13. Archivos entregados

Creaciones documentales:

- [Esta especificación](PHASE9A_BLOCKCHAIN_SPEC.md).
- [ADR-0014](adr/0014-evm-network-toolchain-and-authority.md).
- [ADR-0015](adr/0015-private-commitments-and-durable-anchoring.md).

Documentación existente actualizada para coherencia, estado CI y cámara:

- [AGENTS.md](../AGENTS.md) y [README.md](../README.md).
- [BLOCKCHAIN](BLOCKCHAIN.md), [ARCHITECTURE](ARCHITECTURE.md),
  [DATABASE](DATABASE.md), [SECURITY](SECURITY.md) y [REQUIREMENTS](REQUIREMENTS.md).
- [ROADMAP](ROADMAP.md) e [índice ADR](ADR_README.md).
- [PUBLIC_VERIFICATION](PUBLIC_VERIFICATION.md) y [SECURE_ISSUANCE](SECURE_ISSUANCE.md).
- [TESTING](TESTING.md), [aceptación 8D](PHASE8_ACCEPTANCE.md),
  [checklist 8D](PHASE8_OPERATOR_CHECKLIST.md) y [guion de demo](DEMO_VERIFICATION.md).

18 archivos Markdown en total (3 nuevos, 15 modificados); sin cambios ejecutables.
