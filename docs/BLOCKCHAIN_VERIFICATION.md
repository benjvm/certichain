# Verificación blockchain y apertura — Fase 9D

Aceptación ampliada 9E: [PHASE9E_ACCEPTANCE](PHASE9E_ACCEPTANCE.md),
[DEMO_BLOCKCHAIN_LOCAL](DEMO_BLOCKCHAIN_LOCAL.md),
`./supabase/tests/run_phase9e.ps1` (completa) o `-BackendOnly` (sin Flutter).
Misma app main.dart/contratos v1/v2/apertura Auth. Añade evidencia de recuperación
ledger/Storage, archivos, cambio de cuenta, presupuesto y reset sin nuevo producto.
CI 9D integrada success observada para 7737d303…; CI del árbol 9E NOT_OBSERVED.

9A sección 3 define exactamente SHA-256/U/K/I/H/S/C; contrato, ABI y vector 9B
no cambian. [ADR-0017](adr/0017-public-blockchain-evidence-and-private-opening.md)
separa evidencia pública, documento y apertura. Ninguna comprobación acredita
identidad del presentador, verdad académica o validez legal. Supabase atribuye
institución/metadatos; el RPC backend observa la cadena.

## POST verify-certificate-v2

`/functions/v1/verify-certificate-v2`, JSON UTF-8 <=2048 bytes, exclusivamente
`{"credential_code":"UUID"}`. No sesión/JWT/apikey/cookies. `verify_jwt=false`
solo para este nuevo endpoint público; los públicos v1 conservan su configuración.
UUID ASCII con guiones, 36 caracteres, caso equivalente normalizado; sin coerción.
Duplicados, incluidas claves escapadas equivalentes, y campos extra se rechazan.

HTTP 200: envelope cerrado `schema_version:"2"`, `registry`, `blockchain`.
`registry` contiene **literalmente** v1, con sus campos y prioridad existentes.
No se hace otra consulta verify-certificate para construirlo. `not_found` devuelve
exactamente `{"schema_version":"2","registry":{"schema_version":"1","result":"not_found"},"blockchain":null}`.
Ausencia/incompleto/legado/no elegible son uniformes; no consultan EVM por ese
código ni revelan operaciones. Publicación completed coherente sin anchor del
entorno configurado conserva valid/revoked/expired/issuer_unavailable y devuelve
blockchain off_chain_only; no se atribuyen transacciones ni bloques.

La migración `20261013110000_blockchain_verification_opening.sql` añade únicamente
`lookup_public_certificate_v2(text,text)` y
`authorize_certificate_opening(uuid,uuid,text)`. Una sentencia SQL obtiene el
registro y snapshot de deployment/binding/anchor/issue/receipt coherentes. Se
repite la elegibilidad literal del helper 8C (completed, IDs, institución, titular,
actor, hashes y ruta), sin cambiar v1. El entorno lo aporta backend, no cliente.
El snapshot es técnico y nunca se devuelve entero; no es blockchain_job.
Deshabilitar un deployment no borra su anchor/apertura: se prefiere el anchor del
deployment habilitado del entorno, o el original más reciente si no existe otro.
Tras reset, el lector rechaza aquel deployment al contrastar identidad real;
no lo convierte en off_chain_only ni usa un manifiesto histórico como cadena viva.

### Blockchain: campos cerrados

Todas las respuestas blockchain tienen `state`, `finality`, `checked_at`, `source`.
Observación completa añade `chain_id`, `contract_address`, `protocol_version`,
`certificate_key`, `issuer_id`, `commitment`, `revoked`, `transaction_hash`,
`block_number`, `block_hash`, `confirmations`; la observación actual añade
`registered_at` del timestamp EVM de la emisión. Nunca se rellena un dato ausente.
chain_id/block_number/confirmations son **decimal strings**, sin redondeo JS.
protocol_version es integer 1. Bytes32 son `0x`+64 hex minúsculos y dirección
`0x`+40. Fechas UTC ISO/RFC3339, hasta seis decimales en origen SQL.

| state | Significado |
|---|---|
| off_chain_only | Publicación elegible; sin anchor de ese entorno. Fecha/origen de la lectura SQL |
| pending | Anchor solicitado; lectura canónica sin registro o sin evidencia de inclusión suficiente. No afirma progreso del worker |
| included | Receipt/evento/estado/bloque canónicos; umbral aún no alcanzado |
| confirmed | Evidencia actual comprobada y confirmaciones suficientes (Anvil 1, Sepolia 12) |
| reorged | Bloque antes validado ya no canónico, demostrado por lectura satisfactoria; nunca solo timeout/null |
| unavailable | Registro SQL obtenido; comprobación EVM no disponible/incompleta |
| divergence | Deployment/evidencia/estado incompatibles, revocación SQL/EVM distinta o discrepancia operativa persistida |

finality unknown/not_applicable/finalized es independiente. Anvil jamás finalized.
Sepolia finalized exige referencia finalized canónica que cubra la inclusión;
no se demuestra consenso PoS con Anvil. Si falta finalized, conservar unknown.

source backend_rpc: observación real fechada del backend lector; persisted_receipt:
evidencia anterior validada y fechada cuando se observó; unavailable: la consulta
actual no pudo comprobar EVM. off_chain_only usa certichain_registry porque no
hubo observación EVM. pending observado sin inclusión usa backend_rpc.
`checked_at` de unavailable/reorg/divergence registra el intento actual, no inventa
fecha de inclusión ni actualiza un receipt. `last_evidence`, cuando existe, contiene
solo la observación mínima persistida, con source=persisted_receipt y su fecha
original. **Siempre anterior**, también si otro campo actual está confirmado.
El receipt de issue acredita revoked=false en aquel bloque, no ausencia de una
revocación posterior. Tras reorg su estado anterior se etiqueta reorged y no se
presumen confirmaciones/finalidad vigentes. No se exponen snapshots completos.

### Lectura y límites

PublicEvmReader reutiliza EvmRegistry **sin privateKey**, acepta exclusivamente
eth_chainId, eth_getBlockByNumber, eth_getCode, eth_call,
eth_getTransactionReceipt, eth_getTransactionByHash y eth_getLogs. No prepare,
signer, transmisión, nonce, cola, reconciliación ni cambios privados. Valida
deployment/genesis/bloque/runtime exacto/protocolVersion de 9B; K/C/I, receipt,
calldata, evento/timestamp, estado a inclusión y head, canonicidad antes/después.
Recuperación lectora de evento limitada a cuatro páginas de 2000 bloques; si
no basta, unavailable, sin lanzar worker ni inferir ausencia.

Deadline total 12 s por petición (presupuesto, lectura entrada, SQL/Auth y EVM),
sin ampliarlo por cada RPC. RPC individual <=10 s restante. `Server-Timing`
expone duración total medida en v2, sin código/PII/logs. Entrada <=2 KiB, SQL/Auth
<=16 KiB, RPC <=64 KiB; JSON UTF-8 fatal, profundidad <=16 y <=4096 nodos,
duplicados rechazados, tamaños/tipos/hex/fechas/enteros comprobados. Logs RPC
máximo 64 y cuatro topics. Respuestas inválidas no se coercionan. Flutter
abort/15 s/8 KiB público; privado abort/30 s/16 KiB. No redirects públicos.

Cada POST v2 consume **una vez** `consume_public_verification_budget()` antes de
validar, compartido con verify/compare v1: global atómico 60 POST/60 s. Entradas
inválidas consumen; OPTIONS no. 429 rate_limited incluye Retry-After entero.
No polling/reintentos automáticos. El cooldown Flutter se comparte entre las
rutas públicas y lectura del titular. 400 invalid_input, 413 payload_too_large,
405 method_not_allowed, 503 temporary_failure cerrados/no-store. SQL/registro
fallido siempre 503; fallo EVM con registro válido permite 200 parcial unavailable.

## POST certificate-opening

Endpoint separado con verify_jwt=true y Auth `/user` real. Entrada cerrada
`{"certificate_id":"UUID"}`, UTF-8 <=2048 bytes. El entorno/red/contrato/binding
proceden de SQL/configuración. Titular propio mantiene acceso incluso si emisor
suspended; owner/admin/issuer **actual** de emisora verified también. Plataforma
sin titularidad/membresía no recibe privilegio implícito. Otro titular/institución,
anónimo, publicación incoherente, código/binding/deployment cruzados quedan
denegados. Recalcula en SQL H/K/C usando I/S privados y publicación exacta.

HTTP 200 cerrado: protocol_version integer 1, credential_code, issuer_id,
document_sha256 (`0x`+64 hex), salt (`0x`+64 hex), chain_id decimal string y
contract_address. Sin raw tx, nonces, claves, job, URL/PDF Storage o datos del
titular. 401 unauthenticated; 404 opening_unavailable uniforme (ausente/ajeno/
incoherente/sin anchor); 400/413/405/503 como arriba. Todas las respuestas no-store;
sin cuerpo/errores upstream en logs.

RPC SECURITY DEFINER/search_path vacío, referencias cualificadas y EXECUTE
service_role. Sin SELECT/DML cliente en tablas privadas ni cambios de RLS.
El endpoint no descarga Storage: abre el compromiso persistido de la publicación
coherente. La copia aportada por el verificador se comprueba localmente; la descarga
privada del PDF conserva el chequeo separado certificate-pdf de 7C.

## Flutter y comprobación local

Espacio institucional: anclar certificado publicado elegible, confirmar solicitud,
recibo mínimo antes de POST, 202/200 operation_id/status reales, recuperar misma
key, actualizar manualmente, reautorizar blocked/failed explícitamente. Divergence
requiere operador. Recibos en preferencias por usuario/institución/certificado,
máximo 20/7 días: IDs/key/status/fecha, nunca apertura/H/S/PDF. Si se pierde un
recibo, backend sigue recuperando el anchor único; la app no garantiza retención
de preferencias. Sin worker activo queda solicitado. No repetir emisión/PDF.

Titular: evidencia mediante código propio + v2 pública, **nunca anchor-progress**.
La apertura solo se obtiene por botón. Copiar/exportar únicamente por otra acción,
con explicación de compartir H/salt. Memoria ligada a ruta/identidad/token;
salida/logout/expiración/cambio descartan referencias y respuestas tardías.
La app no promete borrar copias/clipboard externos. No apertura en QR, enlace,
analytics, preferencias, caché persistente ni capturas de aceptación.

Verificación: Registro CertiChain, Blockchain, Mi copia y Validez de la apertura
son bloques independientes. «Comprobar con apertura» importa/pega JSON <=2 KiB,
selecciona PDF >0 y <=8 MiB con el adaptador existente, calcula H/K/C exactamente
según 9A/fixture protocol-v1. No sube PDF/apertura/salt. PDF no coincidente,
apertura inválida (código/red/contrato/I/K/C), y evidencia actual no comprobable
son distintos. La coincidencia solo se acredita contra observación actual
included/confirmed; receipt anterior queda no comprobable actualmente. No cambia
caducidad/revocación ni acredita identidad. Código en enlaces/QR permanece igual.

Comparación candidata v1 sigue enviando solo código/hash y devuelve su propio
snapshot de registro. Tras comparar no se mezcla blockchain de otra consulta como
actual: se identifica como anterior con fecha intacta. Un fallo de refresco conserva
el resultado anterior, nunca aparenta confirmación desde v1 como fallback.
Explorador construido solo para chain 11155111, host sepolia.etherscan.io y hash
validado; enlace seleccionable para contraste adicional. Anvil sin explorador.
No URL arbitraria del DTO, Web3, firma o secretos en Flutter.

## Configuración y reproducción

Backend Edge añade **EVM_RPC_URL solo para lectura**, además de EVM_ENVIRONMENT_ID.
No EVM_SIGNER_PRIVATE_KEY/EVM_ADMIN_PRIVATE_KEY en Edge ni Flutter. El worker host
conserva su entorno privado 9C. En Docker, conectar Edge a la red privada Anvil y
usar http://anvil:8545; no asumir que loopback de Edge es el host. Registrar un
deployment vivo nuevo; manifests históricos/sintéticos 9B no sirven. Configuración
administrativa/worker en [BLOCKCHAIN_OPERATIONS](BLOCKCHAIN_OPERATIONS.md).

Desde raíz, con herramientas congeladas y Docker disponibles:

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
node blockchain/scripts/bootstrap.mjs
node blockchain/scripts/forge.mjs build --force
node blockchain/scripts/backend-abi.mjs --check
./supabase/tests/run_phase9d.ps1
# Variante HTTP/SQL real sin navegador, no acredita el recorrido Flutter:
./supabase/tests/run_phase9d.ps1 -BackendOnly
```

Runner crea proyecto nuevo fuera del repositorio, SQL antes de fixtures mutables,
Anvil/Edge/red propios y frontend main.dart release HTTPS. El harness confiable
ejecuta el worker; Flutter jamás lo hace. finally limpia solo recursos propios.
Inputs/exportaciones sintéticos temporales no se copian a artefactos; result.json
solo guarda revisión/dirty/fecha/contadores/etapas/cámara. Comandos de formato,
análisis/regresiones/resultados y CI exacto en [PHASE9D_ACCEPTANCE](PHASE9D_ACCEPTANCE.md).

9E amplía aceptación local (estado en su documento); 10 pendiente. Sin backfill,
cron remoto, Sepolia, wallet/NFT/token o revocación
de producto. Cámara SKIP/NOT_RUN:
«Omitidas por instrucción del usuario; no hay cámara física disponible».
