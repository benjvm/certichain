# ADR-0014: Red EVM, herramientas y autoridad del registro MVP

- Status: accepted (diseño 9A, implementación pendiente)
- Date: 2026-10-12

## Contexto

La emisión 7B publica active/completed sin blockchain; 8A–8D verifican el registro
Supabase. No existe código en blockchain/. Se necesita fijar un protocolo que
9B pueda implementar sin incorporar custodia de alumnos ni varias toolchains.
La autorización real usa institution_members owner/admin/issuer y estado verified.
Una dirección de servicio compartida no acredita a cada institución por sí sola.

## Decisión

Anvil 31337 para pruebas deterministas y Sepolia 11155111 para una única demo
pública. La recomendación oficial vigente identifica Sepolia para aplicaciones;
Hoodi para validadores. Foundry exclusivamente, sin Hardhat paralelo.
Versiones propuestas fijadas para 9B, verificadas en releases/repositorios oficiales:

| Herramienta | Versión / commit del tag | Publicación |
|---|---|---|
| Solidity | 0.8.37 / f401782df49be312ea4ef52a2d467cf5183b5906 | 2026-09-10 |
| Foundry | v1.8.5 / 51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f | 2026-10-05 |
| OpenZeppelin Contracts | v5.7.0 / cab19933c33c2ad1d4c7a84864a3601dddfd16f3 | 2026-07-29 |

Pragma exacto 0.8.37; EVM cancun, optimizer 200, via_ir=false. Ownable/Ownable2Step
de ese tag admiten ^0.8.20; la combinación propuesta cumple ese rango. Compilar,
verificar binarios/checksums y fijar dependencias pertenece a 9B. No se instalan
herramientas en 9A ni se afirma una compatibilidad ejecutada.

Contrato sin proxy, con administrador Ownable2Step, renounce deshabilitado y
registro immutable salvo revocación. Separar EOA administrador y EOA operativo;
plataforma Auth no hereda administración EVM. I opaco estable por institución,
signer(I) y permisos canIssue/canRevoke independientes. MVP permite un EOA
backend compartido configurado explícitamente por I. Backend autoriza humanos;
contrato autoriza ese EOA para I. Alumno sin wallet.

Suspensión bloquea emisión backend y solicita canIssue=false/canRevoke=true;
owner/admin de emisora verified o suspended pueden solicitar revocación en fase
10. Rotación cambia signer sin cambiar I ni los certificados. Retirada completa
bloquea ambas escrituras, conserva lectura. No administración EVM desde Flutter.

Inclusión, confirmaciones y finalidad separados: Anvil 1 confirmación, finalidad
not_applicable; Sepolia 12 confirmaciones, finalidad solo por bloque finalized
canónico. Reorg invalida evidencia; cambio de finalidad observada detiene escrituras.
Los timestamps EVM registran anclaje/revocación, no fechas académicas SQL.
Especificación implementable y matriz de permisos en
[PHASE9A_BLOCKCHAIN_SPEC.md](../PHASE9A_BLOCKCHAIN_SPEC.md).

## Alternativas consideradas

- Hoodi/Ephemery: orientadas a infraestructura de validadores o resets frecuentes;
  Sepolia encaja mejor en aplicación/contrato. Mainnet añade costes sin valor de demo.
- Hardhat más Foundry: duplica configuración/dependencias sin caso de uso.
- Proxies/AccessControl genérico: más superficies administrativas que las necesarias;
  Ownable2Step más configuración por I cubre administración/rotación concretas.
- Cuenta EVM por institución: mejor separación de claves, pero multiplica custodia,
  financiación y gestión de nonces. No necesaria para demostrar este MVP.
- Wallet del alumno, NFT o tokens: no resuelven emisión académica ni privacidad.
- Contar bloques como finalidad: simple, pero confunde probabilidad de reorg y
  finalidad PoS. Se conserva la diferencia explícita.

## Consecuencias

Menos herramientas y contrato pequeño, con confianza explícita en plataforma y
firmante para atribuir instituciones. Compromiso del firmante afecta a todos sus I;
permiso en BD y cadena puede divergir durante una actualización. Sin proxy, un
cambio de protocolo exige nuevo contrato/versionado y decisión explícita sobre
los registros antiguos. Testnet no asegura conservación perpetua ni identidad.

## Validación

9A: tags consultados con git ls-remote, releases/pragmas y recomendación de red
revisados. 9B: compilación fijada, autorización/cross-issuer, rotación/retirada,
no renounce, eventos, duplicados, fuzz/invariantes y Anvil. 9C: RPC correcto,
nonces, reorg y finalidad; no simular aceptación de testnet con resultados locales.

## Fuentes oficiales consultadas el 2026-10-12

- [Ethereum: redes](https://ethereum.org/en/developers/docs/networks/).
- [Ethereum JSON-RPC: receipts y referencias finalized/safe](https://ethereum.org/en/developers/docs/apis/json-rpc/).
- [Foundry v1.8.5](https://github.com/foundry-rs/foundry/releases/tag/v1.8.5).
- [Solidity 0.8.37](https://github.com/argotorg/solidity/releases/tag/v0.8.37).
- [Configuración del compilador](https://docs.soliditylang.org/en/v0.8.37/using-the-compiler.html).
- [OpenZeppelin v5.7.0](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.7.0).
- [Ownable2Step fijado](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.7.0/contracts/access/Ownable2Step.sol).
