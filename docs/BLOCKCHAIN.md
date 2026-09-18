# Diseño blockchain

## Propósito

Blockchain demuestra que una huella concreta fue registrada por un emisor autorizado y permite publicar su revocación. No sustituye la base de datos, el almacenamiento, la identidad ni el control de acceso.

## Datos on-chain mínimos

- `certificateKey`: `bytes32` derivado de un identificador público con separación de dominio.
- `documentHash`: SHA-256 del PDF, representado como `bytes32`.
- `issuer`: dirección autorizada que ejecuta la operación.
- `issuedAt`: timestamp de bloque.
- `revoked`: booleano o timestamp de revocación.

No almacenar nombre, email, DNI, título legible, institución legible, URL, CID ni PDF.

## Interfaz conceptual

```solidity
interface ICertificateRegistry {
    function issue(bytes32 certificateKey, bytes32 documentHash) external;
    function revoke(bytes32 certificateKey) external;
    function getCertificate(bytes32 certificateKey)
        external
        view
        returns (bytes32 documentHash, address issuer, uint64 issuedAt, bool revoked);
}
```

Eventos:

```solidity
event CertificateIssued(bytes32 indexed certificateKey, bytes32 documentHash, address indexed issuer);
event CertificateRevoked(bytes32 indexed certificateKey, address indexed issuer);
```

## Autorización

El MVP puede usar roles administrados mediante OpenZeppelin AccessControl. Solo `ISSUER_ROLE` emite; la revocación debe comprobar además que quien solicita representa al emisor original, o delegarse a un servicio con una política explícita. Cualquier cambio de modelo exige ADR.

## Red y herramientas

- Desarrollo: Anvil local.
- Demo: una testnet EVM elegida mediante ADR; Sepolia es candidata, no una decisión irreversible.
- Tooling: Foundry para compilación, pruebas, cobertura y scripts.
- Contratos de utilidad: OpenZeppelin fijado a una versión concreta.

## Confirmaciones y fallos

Una transacción enviada no equivale a emisión confirmada. El backend conserva estados `pending`, `confirmed` o `failed`, espera el número configurado de confirmaciones y puede reconciliar eventos. Los reintentos usan `certificateKey` estable para impedir emisiones duplicadas.

## Hashing

- Algoritmo documental: SHA-256.
- Entrada: bytes exactos del archivo persistido.
- Salida: 32 bytes; no aplicar hash a Base64, ruta o metadatos JSON.
- Si se firma o normaliza el PDF, hacerlo antes del hash final.
- Una copia alterada produce otro hash y debe devolver `integrity_mismatch`.

## Pruebas mínimas

- Emisor autorizado puede emitir.
- Cuenta no autorizada no puede emitir ni revocar.
- No se permite duplicar `certificateKey`.
- El evento contiene los valores esperados.
- Revocación cambia el estado y no puede deshacerse.
- Un emisor no revoca credenciales ajenas según la política elegida.
- Fuzz tests para claves y hashes arbitrarios.

## Gestión de claves

Las claves privadas nunca están en Flutter, Git, migraciones, logs o documentación. En local se usan cuentas efímeras de Anvil; en testnet, secretos del backend/CI. Antes de producción se evaluará una wallet de servicio con rotación, multisig o KMS.
