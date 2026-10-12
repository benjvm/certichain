# ADR-0015: Compromiso documental privado y anclaje durable separado

- Status: accepted (diseño 9A, implementación pendiente)
- Date: 2026-10-12

## Contexto

BLOCKCHAIN proponía publicar documentHash mientras ADR-0011/0013 y el DTO v1
ocultan el hash esperado. Una cadena pública expone también calldata y eventos:
ocultarlo únicamente del API no lo mantendría privado. Además, completed actual
significa publicación SQL/PDF coherente; no existe atomicidad PostgreSQL/EVM.

## Decisión

Conservar H=SHA256(bytes exactos PDF) privado. Publicar K derivado del UUID binario
credential_code con dominio propio, I opaco de institución y
C=SHA256(dominio || K || I || H || salt aleatorio de 32 bytes).
Formatos exactos y vector sintético comprobado están en
[PHASE9A_BLOCKCHAIN_SPEC.md](../PHASE9A_BLOCKCHAIN_SPEC.md), sección 3.
No revelar H/salt en cadena ni en API pública. Generar salt CSPRNG una vez,
persistir antes de firmar, reutilizar en recuperación/replacements/reorg y proteger
backups. Apertura por acceso autenticado equivalente a 7C; titular puede compartirla.
Sin apertura no hay comparación documental independiente contra el compromiso:
la comparación candidata v1 sigue confiando en Supabase.

Persistencia nueva 9C en esquema privado: deployments, issuer bindings, anchors,
operaciones lógicas, intentos firmados/observaciones de receipt y nonces. Identidad
de anchor inmutable, salt/K/C estables, una operación issue/revoke por anchor.
Un replacement es otro intento de la misma operación, no otro certificado.
Puerto BlockchainRegistry solo backend. Guardar hash/raw de tx antes de enviarla,
reconciliar evidencia canónica antes de confirmar; no SQL abierto durante RPC.

Mantener certificate.status active/revoked, issuance.completed, anclaje e integridad
de copia independientes. Solicitud autenticada de anclaje explícita después de
publicación; sin backfill. Contrato rechaza todo duplicado; backend recupera una
inclusión idéntica mediante lectura/evento/receipt, no confunde revert con éxito.
Revocación futura SQL inmediata e irreversible con evidencia EVM separada y
durable: no esperar a RPC para advertir revocación off-chain.

## Alternativas consideradas

- H público: facilita comparar cualquier copia contra cadena sin apertura, pero
  permite reconocer documentos conocidos y correlacionar sus hashes de forma
  permanente. Contradice el propósito de minimizar exposición del hash esperado.
- H público solo en eventos: no resuelve privacidad, siguen siendo públicos.
- Compromiso sin salt: quien tenga un PDF candidato puede recalcularlo; no oculta.
- Salt publicado o derivado de UUID: tampoco ofrece ocultación del documento.
- Cifrar PDF/publicar URL: añade exposición/custodia y no es necesario para registro.
- ZK u otros protocolos de apertura selectiva: complejidad injustificada para demo.
- Cambiar active a anchoring y completed a confirmed: rompería consumidores y
  mezclaría registros operativos con evidencia distribuida aún pendiente.
- Una fila por tx como certificado: duplica identidad bajo replacements/reintentos.
- Transacción distribuida ficticia o lock SQL durante RPC: no garantiza commit EVM
  y perjudica disponibilidad. Outbox durable/reconciliación hace explícitos los fallos.

## Consecuencias

Menos correlación documental pública, a cambio de persistir/proteger salt y limitar
la verificación independiente a terceros que reciban apertura. K e I siguen
correlacionables; no se promete anonimato. Pérdida de salt no permite recrear
apertura cambiando C bajo K existente. Infraestructura y operador deben recuperar
respuestas perdidas, reorg y discrepancias sin borrar evidencia ni repetir emisión.
BD sigue confiable para membresías, titular, verdad académica y mapping I↔institución.
9D versionará evidencia pública; no cambia silenciosamente el DTO v1.

## Validación

9A recalcula vector con Node crypto y .NET; contrasta migraciones y contrato v1.
9C deberá probar concurrencia, restauración de salt, nonce/replacements, crashes,
receipt/evento incompatible y matriz de fallos, con RLS/grants y preservación de
históricos. 9D comprobará apertura con bytes y cálculo independiente. No se
atribuyen pruebas Foundry/EVM ejecutadas a esta decisión documental.

## Fuentes oficiales consultadas el 2026-10-12

- [SHA-256, NIST FIPS 180-4](https://doi.org/10.6028/NIST.FIPS.180-4).
- [UUID binario y orden de bytes, RFC 9562](https://www.rfc-editor.org/rfc/rfc9562.html).
- [Web Crypto getRandomValues](https://www.w3.org/TR/WebCryptoAPI/#Crypto-method-getRandomValues).
- [ABI Solidity](https://docs.soliditylang.org/en/v0.8.37/abi-spec.html).
- [Ethereum JSON-RPC](https://ethereum.org/en/developers/docs/apis/json-rpc/).
- [Transacciones Ethereum y nonce](https://ethereum.org/en/developers/docs/transactions/).
- [Sobre y firma EIP-1559](https://eips.ethereum.org/EIPS/eip-1559).
- [PostgreSQL: transacciones](https://www.postgresql.org/docs/17/tutorial-transactions.html).

ADR-0011/0013 siguen vigentes para el API actual. Este ADR reemplaza la propuesta
conceptual antigua de H público y blockchain_records, no su historia ni código.
