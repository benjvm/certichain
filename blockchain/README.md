# CertificateRegistry v1 — fase 9B

Backend local 9C: [operación](../docs/BLOCKCHAIN_OPERATIONS.md) y
[aceptación](../docs/PHASE9C_ACCEPTANCE.md). El smoke de este README sigue siendo
descartable y sus manifests históricos. El nuevo harness despliega otra cadena
viva propia; firma raw en backend antes de enviar. Módulo ABI/runtime generado:
`node blockchain/scripts/backend-abi.mjs` y `--check` para detectar drift.

Implementación local del [protocolo normativo 9A](../docs/PHASE9A_BLOCKCHAIN_SPEC.md),
base `b6051bc1c0489d84204ee1aae14e3feb7edf30e2`. No integra Supabase ni Flutter.
Resultados y matriz de aceptación: [PHASE9B_ACCEPTANCE](../docs/PHASE9B_ACCEPTANCE.md).

El contrato guarda K/C/I y fechas de bloque, autoriza al firmante actualmente
configurado por emisor y conserva una revocación irreversible. Un compromiso
arbitrario **no demuestra correspondencia con un PDF**, verdad académica,
identidad humana ni acreditación de la institución. Para comparar un PDF se
necesita la apertura privada definida en 9A. H y salt no entran al contrato.

## Preparación desde un checkout sin dependencias

Desde la raíz del repositorio, en Windows x64 o Linux x64:

```powershell
node blockchain/scripts/bootstrap.mjs
node blockchain/scripts/validate.mjs
```

Prerrequisitos: Git, `tar`, Node >=22, PowerShell 7 con .NET >=6 (`pwsh`) y acceso
HTTPS a GitHub/releases/codeload. CI usa la versión Node ya fijada por el proyecto,
24.14.0; la validación Windows usó el Node disponible 22.14.0. No se cambia ningún
lockfile o SDK de Flutter, Supabase, Node o Deno. No se usó WSL; la única distribución
detectada era docker-desktop. No se necesita Docker para estas pruebas.

`bootstrap.mjs` comprueba los commits de los tags, compara los SHA-256 oficiales
de Foundry/solc y verifica los archivos descargados antes de instalar. Los archivos
de dependencias se descargan por commit y se comprueban contra sus SHA-256
congelados. Extrae fuentes sin `.git`, submódulos ni repositorios anidados en `lib/`.
En una instalación existente compara contenido antes de reutilizar: una dependencia
o binario alterado hace fallar el comando. No reemplaza herramientas globales.
Descargas verificadas quedan en `.tools/downloads`; temporales propios nuevos se
eliminan con comprobación de su ruta. `lib/` y `.tools/` se excluyen de Git.

| Dependencia | Versión | Commit |
|---|---|---|
| Foundry (Forge/Cast/Anvil) | 1.8.5 | 51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f |
| Solidity | 0.8.37 | f401782df49be312ea4ef52a2d467cf5183b5906 |
| OpenZeppelin Contracts | 5.7.0 | cab19933c33c2ad1d4c7a84864a3601dddfd16f3 |
| forge-std | 1.17.0 | f3dae6e6ee381f25eb6a246f7da9b85c91a68219 |

URLs y checksums completos: [toolchain.lock.json](toolchain.lock.json).
Los checksums de binarios proceden de los `.sha256` de Foundry y del campo `digest`
de assets de la release oficial de Solidity. Los SHA-256 de archivos codeload de
dependencias fueron calculados sobre esas descargas; no se presentan como una
firma del publicador. Cada tag se vuelve a comprobar contra su commit.

OpenZeppelin aporta exclusivamente Ownable/Ownable2Step y su Context: evita
mantener administración propia. forge-std aporta Test/Vm/StdInvariant al harness,
sin dependencia en el contrato desplegado. La alternativa sería desarrollar
controles administrativos y helpers de prueba propios. Actualizaciones futuras
requieren revisar fuentes, avisos de seguridad, pins, compilación y pruebas;
no se resuelven versiones flotantes, nightly ni latest.

## Build y comprobaciones individuales

El wrapper llama a los binarios aislados y fija el solc verificado. Es especialmente
necesario en este equipo: el `forge.bat` global pertenece a PHP/Herd.

```powershell
node blockchain/scripts/forge.mjs fmt --check
node blockchain/scripts/forge.mjs build --force
node blockchain/scripts/forge.mjs test
node blockchain/scripts/forge.mjs test --match-contract CertificateRegistryGasTest --gas-report
node blockchain/scripts/forge.mjs snapshot --match-contract CertificateRegistryGasTest --check
node blockchain/scripts/validate.mjs
```

`foundry.toml`: pragma/solc 0.8.37, Cancun, optimizer=true, 200 runs, via_ir=false.
Se fija además `dynamic_test_linking=false`: Foundry 1.8.5 transforma `new` en
deployCode por defecto; desactivarlo conserva CREATE y su gas, y evita que un
constructor esperado como revert termine prematuramente una prueba más larga.
El administrador cero se prueba en un caso separado. No cambia el protocolo ni
los settings de producción de ADR-0014. El aviso del compilador de que renounce
podría ser view es conocido: conserva la mutabilidad nonpayable de Ownable en el ABI.

Cuatro propiedades fuzz de 512 runs, seed `0x9b20261012`. Dos invariantes compartidas
en un handler con 128 runs/depth 64 (8.192 llamadas por campaña). Dos emisores,
cuatro tipos de firmante y 16 claves acotan el modelo. Emisiones/revocaciones
válidas se alcanzan desde setup y durante secuencias; los errores esperados se
comparan byte a byte. `fail_on_revert=true`; fallos inesperados no se ocultan.

El snapshot versionado contiene seis escenarios deterministas, no medianas de
fuzz. Para una modificación deliberada, reconstruir normalmente antes de generar:

```powershell
node blockchain/scripts/forge.mjs build --force
node blockchain/scripts/forge.mjs snapshot --match-contract CertificateRegistryGasTest --snap .gas-snapshot
```

Cobertura (crear primero el directorio `blockchain/coverage`):

```powershell
node blockchain/scripts/forge.mjs coverage --exclude-tests --report summary --report lcov --report-file coverage/lcov.info
```

`validate.mjs` prepara ese directorio, registra comandos/resultados/plataforma,
ejecuta todas las comprobaciones y escribe `evidence/validation.json` y logs.
Coverage desactiva optimización para medir; sus outputs no se despliegan.
Los exporters reconstruyen con `build --force` y verifican los settings normales.
No se afirma que cobertura del contrato propio incluya todo OpenZeppelin ni que
100% de las ramas reportadas pruebe todas las combinaciones posibles.

## Vector compartido con 9C

[fixtures/protocol-v1.json](fixtures/protocol-v1.json) y
[fixtures/synthetic.pdf](fixtures/synthetic.pdf) conservan el vector exacto de 9A,
PDF de 330 bytes, preimágenes de 46/162 bytes, SHA-256 y UUID en orden de red.
H y salt de este fixture son únicamente valores sintéticos fuera de cadena.
Tests Solidity y smoke solo leen/envían K/C/I.

```powershell
node blockchain/scripts/fixture.mjs --check
pwsh -NoProfile -File blockchain/scripts/verify-fixture.ps1
```

Node crypto recalcula H/K/C desde `pdfFixture()` existente; PowerShell/.NET es la
verificación independiente. Para regenerar usar `fixture.mjs` sin `--check`.
No reescribir PDF, encoding ni JSON a mano. No se utiliza Keccak para K/C.

## Despliegue y smoke RPC real, exclusivamente local

```powershell
node blockchain/scripts/local-anvil.mjs
```

Este es el script de despliegue operativo: crea su propio Anvil en un puerto
libre de 127.0.0.1, sin fork ni destino aportado por el usuario, comprueba chain ID
31337 y genesis antes de cada escritura, fija hardfork Cancun y usa cuentas de
desarrollo efímeras.
Administrador, firmante inicial y nuevo firmante son distintos. Despliega el
bytecode normal mediante una transacción real de creación; no es una simulación
de Forge ni un mock RPC. Las cuentas desbloqueadas se usan solamente en este
harness local. 9C firmará en backend según 9A y no reutilizará este transporte.

Configura I, emite el vector, consulta, comprueba rechazos, rota, emite con el nuevo
firmante, revoca el registro anterior y vuelve a leer. Compara eventos con topics,
datos y emisor exactos, status/from/to y hash de bloque canónico de cada receipt,
estado y runtime de `eth_getCode`. Prueba duplicado, firmante ajeno/retirado,
segunda revocación, retirada completa y llamada con fondos. Comprueba el
manifiesto en vivo y realiza un reset real de **su** instancia para demostrar
que la referencia anterior queda invalidada. El finally termina únicamente el
ChildProcess creado por el script; no enumera ni mata otras instancias.

No imprime ni persiste claves, mnemonic, logs de cuentas o dumps. El CLI rechaza
argumentos externos; el helper RPC exige literalmente `http://127.0.0.1:PUERTO`.
SIGINT/SIGTERM conducen a la limpieza acotada. Si falla, registra etapa y FAIL;
no convierte un rechazo inesperado o un error de limpieza en PASS.

Cada ejecución escribe `deployments/anvil-<uuid>/{manifest,receipts,smoke}.json`;
la última evidencia sanitizada queda en `evidence/anvil/`, incluido cleanup.json.
Estos directorios se ignoran. La cadena se resetea y descarta: el manifiesto es
**evidencia histórica de esa ejecución**, no un endpoint vivo utilizable por 9C.
Una nueva sesión requiere su nuevo despliegue/manifiesto. No se reutiliza tras reset,
aunque chain ID o dirección coincidan. `verify-manifest.mjs` permite comprobar una
referencia local viva mediante RPC de solo lectura y rechaza ejemplos sintéticos.

## Artefactos para 9C y CI

```powershell
node blockchain/scripts/artifacts.mjs
node blockchain/scripts/artifacts.mjs --check
```

- `artifacts/CertificateRegistry.v1.abi.json`: ABI estable completo, incluidos
  administración y errores heredados. Generado, nunca editado manualmente.
- `artifacts/build-reference.json`: compilador, dependencias, settings, hashes
  Keccak de fuentes/creation/runtime, SHA-256 de configuración/lock/ABI, sin coverage.
- `artifacts/manifest.synthetic.example.json`: ejemplo expresamente sintético,
  dirección/tx/bloque/genesis cero; no acredita un despliegue.
- Manifiesto **real**: chain ID/dirección/versión/runtime Keccak, tx y número/hash
  de bloque de despliegue, genesis/environmentId, versiones y referencias exactas
  de fuentes/settings, HEAD y workingTreeDirty, fecha, finalidad not_applicable.

Se normalizan a LF las fuentes/JSON versionados para reproducibilidad Windows/Linux.
No se comprometen `out/`, `cache/`, `broadcast/` completos. CI es un workflow
independiente [blockchain.yml](../.github/workflows/blockchain.yml), PR y push a main,
acciones por SHA, bootstrap congelado y el mismo validate; comprueba diff de
artefactos y sube solo evidencia sanitizada/LCOV. Los workflows anteriores quedan
intactos. Workflow preparado y validación local no equivalen a CI remoto observado.

La revocación aquí probada no habilita el flujo Auth/SQL/EVM de la app (fase 10).
9C/9D/9E siguen pendientes. Anvil no prueba finalidad PoS ni Sepolia. El rechazo
de llamadas normales con fondos no impide ETH forzado por reglas EVM.

Cámara: CERTICHAIN_TEST_CAMERA=0; **NOT_RUN**:
«Omitidas por instrucción del usuario; no hay cámara física disponible».
