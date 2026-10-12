# Diseño blockchain — decisión 9A

Estado al 12/10/2026: **protocolo especificado, sin contrato ejecutable ni integración**.
Fuente normativa: [PHASE9A_BLOCKCHAIN_SPEC.md](PHASE9A_BLOCKCHAIN_SPEC.md).
La emisión y verificación actuales continúan off-chain.

## Aportación y límites

El futuro registro publicará un compromiso estable y su revocación, asociados
a un emisor opaco autorizado. Permite contrastar evidencia fuera de Supabase.
No comprueba identidad, titularidad del presentador, acreditación institucional
ni verdad académica. La atribución institución↔emisor y los permisos humanos
siguen confiando en backend/plataforma; el alumno no necesita wallet.

## Decisiones adoptadas

- Anvil 31337 local; Ethereum Sepolia 11155111 para una sola demo testnet.
- Solidity 0.8.37, Foundry v1.8.5 y OpenZeppelin Contracts v5.7.0 propuestos y
  fijados para 9B; commits/fuentes en
  [ADR-0014](adr/0014-evm-network-toolchain-and-authority.md). Sin instalaciones 9A.
- Contrato mínimo sin proxies, NFT, tokens, transferencias, pagos ni multichain.
- Administrador Ownable2Step separado del firmante operativo backend. Configurar
  signer y permisos issue/revoke por issuerId opaco estable. Cuenta operativa
  compartida permitida en demo, con su límite de confianza explícito.
- Emisión exige owner/admin/issuer real y institución verified. Revocación
  futura owner/admin de emisora verified o suspended; no DML de cliente.
- Anvil confirma con 1 bloque y no acredita finalidad PoS. Sepolia confirma
  con 12 y solo finaliza contra bloque finalized canónico. Reorg invalida evidencia.

## Privacidad y datos mínimos

H=SHA-256 de los bytes exactos del PDF final permanece privado. Se reemplaza la
propuesta antigua de publicar documentHash por **compromiso C con salt privado**.
Ocultar H del API no bastaría si apareciese en cadena. K se deriva de credential_code
UUID binario, con separación de dominio; I identifica opacamente al emisor.
Encoding literal, tamaños, vector hexadecimal comprobado, persistencia/recuperación
de salt y acceso a apertura en la sección 3 de la especificación y
[ADR-0015](adr/0015-private-commitments-and-durable-anchoring.md).

Estado/eventos/calldata: K/C/I, direcciones técnicas, permisos, versión y tiempos
de bloque. Nunca H/salt, nombres, correo, DNI, titular, título legible, rutas,
URLs privadas, PDF ni motivo interno. Identificadores opacos y fechas siguen
correlacionables. Sin apertura un tercero no puede comparar su PDF con C de
forma independiente; la comparación candidata actual depende de Supabase.

## Interfaz, persistencia y recuperación

CertificateRegistry v1: issue(K,C,I), revoke(K), exists(K), getCertificate(K),
setIssuer(I,signer,canIssue,canRevoke), getIssuer(I), protocolVersion().
Duplicados idénticos también revierten; backend reconcilia inclusión original
para idempotencia. Misma K con otro C/I es divergence, nunca upsert.
Revocación irreversible; rotar signer no altera I ni certificados.

BlockchainRegistry es un puerto backend aún no implementado: validación de
despliegue, preparación firmada, envío, observación y lectura a bloque canónico.
Solicitud explícita después de publicación SQL; tablas privadas futuras separan
anchor, operación lógica y múltiples intentos/replacements. completed continúa
significando publicación off-chain; certificate.status sigue active/revoked.
No atomicidad PostgreSQL/EVM, locks durante RPC ni backfill automático.

## Entregas pendientes

9B contrato/tests Foundry/Anvil; 9C migración, adaptador, firma, nonces y
reconciliación; 9D cliente/evidencia v2/apertura autorizada; 9E aceptación local;
10 revocación completa. DTO/RPC v1, credential_code, QR y PDF actuales intactos.
La especificación incluye matriz de errores/recuperación y criterios de prueba;
ninguno se presenta como ejecutado en 9A.
