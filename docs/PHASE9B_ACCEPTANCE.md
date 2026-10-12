# Aceptación fase 9B — CertificateRegistry v1

Fecha: 12/10/2026. **Implementación y validación local completadas; CI remoto de
estos cambios no observado.** Base: main/HEAD
`b6051bc1c0489d84204ee1aae14e3feb7edf30e2`, árbol limpio al comenzar. No commits,
push, merge, despliegue remoto ni cambios en Supabase/Flutter. 9A/ADR-0014/0015
se conservan como documentos normativos e históricos: no fue necesario ajustar
el protocolo ni las versiones.

## Entrega y versiones

Contrato en `blockchain/src/CertificateRegistry.sol`; Foundry config/remappings,
lock de herramientas/dependencias, unit/fuzz, handler/modelo e invariantes,
escenarios de gas, fixture compartido, bootstrap/verificación, generador ABI,
manifiesto/validador, despliegue/smoke RPC y workflow independiente. No plantillas
Counter, repositorios Git anidados, dependencias de producto nuevas o secretos.

| Herramienta | Versión exacta / commit | Resultado |
|---|---|---|
| Solidity | 0.8.37 / f401782df49be312ea4ef52a2d467cf5183b5906 | Compilación nativa PASS |
| Foundry | 1.8.5 / 51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f | Forge/Cast/Anvil PASS |
| OpenZeppelin | 5.7.0 / cab19933c33c2ad1d4c7a84864a3601dddfd16f3 | Ownable/Ownable2Step compilados |
| forge-std | 1.17.0 / f3dae6e6ee381f25eb6a246f7da9b85c91a68219 | Unit/fuzz/invariantes PASS |

Tags comprobados con git ls-remote; binarios Windows descargados y verificados
contra checksums oficiales. Lock incluye además assets/checksums oficiales
Linux x64 para CI. Compilación y ejecución Linux de 9B aún no observadas.
Checksums completos y procedencia: [toolchain.lock.json](../blockchain/toolchain.lock.json)
y [README operativo](../blockchain/README.md). Archives de dependencias fijados por
commit y digest calculado, no supuestas firmas del publicador.

Settings: solc/pragma 0.8.37, Cancun, optimizer=true/200, via_ir=false;
Anvil también fija hardfork Cancun.
Compatibilidad propuesta en 9A demostrada compilando esas versiones en Windows.
Foundry tiene dynamic_test_linking=true por defecto: la traza inicial transformó
new en deployCode y el constructor esperado como revert terminó prematuramente
un test compuesto. Se fija false y se separa el caso de constructor cero.
La nueva traza/cobertura y el gas de creación acreditan el recorrido completo;
no se cuenta la cobertura inicial como aceptación final. No es cambio de protocolo
ni del build de producción. Aviso 2018 conocido: renounce conserva nonpayable.

## Matriz requisito → prueba → resultado

| Requisito | Evidencia ejecutada | Resultado local |
|---|---|---|
| Constructor no cero, owner y versión uint16(1) | testConstructorRejectsZero; testConstructorVersionAndPublicAbsence; versión/owner RPC | PASS; error OZ preservado |
| Existencia explícita, ausencia/cero y lectura pública | tests de ausencia; assertRecord; handler/modelo; RPC exists/getCertificate | PASS; ausente CertificateNotFound |
| Configuración onlyOwner y entradas cero | testConfigurationValidationAndOwnerErrors | PASS; error OZ antes de validación de entrada |
| Eventos ABI exactos y no-op sin evento | testExactConfigurationEventAndNoop; testSyntheticIssueRevokeEventsAndPublicReading; RPC topics/data | PASS |
| K/C/I no cero → autoridad → unicidad → timestamp | testIssueValidationOrderAndNoRejectedMutation | PASS; orden y estado tras rechazo |
| Todo duplicado, también idéntico, distinto C/I o revocado | testEveryDuplicateIncludingRevokedAndDifferentIssuer; revert y receipt RPC | PASS; sin upsert |
| Revoke K → existencia → autoridad I almacenado → no revocado → timestamp | testRevokeValidationOrderAndRejectedState; RPC | PASS; no acepta I externo |
| Permisos independientes y administrador sin privilegio operativo implícito | testPermissionsIndependentSuspensionAndWithdrawal; testAdministrationDoesNotGrantOperationButCanBeConfigured | PASS; admin puede configurarse como signer explícitamente |
| Timestamps 0, máximo uint64 y overflow | testTimestampZeroMaximumAndOverflow; testRevokeInvalidTimestampLeavesRecordUnchanged; fuzz overflow/round-trip | PASS; validación antes de conversión |
| Revocación irreversible conserva C/I/registeredAt | assertRecord unit/RPC; modelo auxiliar | PASS |
| Rotación, retirada total, suspensión canIssue=false/canRevoke=true | tests de permisos/rotación; configuración handler; RPC | PASS; nuevo signer revoca registros anteriores |
| Dos emisores con signers distintos, y dirección compartida | testDistinctAndSharedCrossIssuerAuthority | PASS; compartido opera por ambos I configurados |
| Transferencia, aceptación, cancelación cero y sustitución de pending owner | testTwoStepAdministrationAcceptanceCancellationAndReplacement | PASS; semántica OZ |
| Renounce deshabilitado y caller ajeno | testRenounceDisabledAndInheritedUnauthorizedError | PASS; RenounceDisabled/OwnableUnauthorizedAccount |
| Rechazos no crean, borran o alteran registros; configurar no altera certificados | tests unit + handler checkModel tras cada acción | PASS |
| Llamadas normales con fondos rechazadas, sin receive/fallback payable | testNormalCallsRejectFunds; ABI exporter; receipt real RPC | PASS; no se promete bloquear ETH forzado |
| Vector exacto SHA-256 y encoding binario 9A | Node crypto + .NET SHA256; fixture leído por unit/RPC | PASS; PDF 330 bytes, preimágenes 46/162 |
| Fuzz significativo de K/C/I, permisos, caller y tiempos | cuatro testFuzz*, 512 runs cada uno | PASS |
| Invariantes con operaciones válidas y modelo | RegistryHandler, dos invariantes, 128×64; fail_on_revert=true | PASS; 8.192 llamadas, sin revert inesperado |
| Despliegue local real, loopback/31337, cuentas distintas | local-anvil.mjs y receipts públicos | PASS |
| Runtime Keccak desde eth_getCode, ABI normal y manifiesto completo | artifacts.mjs --check; verifyManifest dentro del smoke | PASS |
| Reset invalida identidad previa; limpieza de proceso propio | anvil_reset real + verifyManifest rechazado; cleanup.json | PASS |
| Checkout sin herramientas/dependencias | clon temporal externo del HEAD base + fuentes nuevas, bootstrap y validate | PASS; sin reutilizar .tools/lib/out |
| CI independiente/fijada, checks anteriores intactos | actionlint 1.7.12, comparación con HEAD | Preparada/validación local PASS; remoto NOT_OBSERVED |
| Cámara excluida | CERTICHAIN_TEST_CAMERA=0 en scripts/job | NOT_RUN: «Omitidas por instrucción del usuario; no hay cámara física disponible» |

El contrato autoriza direcciones técnicas, no usuarios Auth ni instituciones
humanas. Una dirección configurada en varios I puede operar en todos ellos;
no se atribuye aislamiento humano al contrato.

## Plataforma, comandos y alcance medido

Windows x64, PowerShell 7.6.5, Node 22.14.0 existente; Foundry y solc nativos
aislados bajo blockchain/.tools. No WSL, cámara, Supabase, Flutter, testnet o claves
reales. CI prepara Ubuntu 24.04/Node 24.14.0 ya fijado en el repositorio.

Desde raíz, comandos realmente ejecutados:

```powershell
node blockchain/scripts/bootstrap.mjs
node blockchain/scripts/fixture.mjs --check
pwsh -NoProfile -File blockchain/scripts/verify-fixture.ps1
node blockchain/scripts/forge.mjs fmt --check
node blockchain/scripts/forge.mjs build --force
node blockchain/scripts/forge.mjs test
node blockchain/scripts/forge.mjs test --match-contract CertificateRegistryGasTest --gas-report
node blockchain/scripts/forge.mjs snapshot --match-contract CertificateRegistryGasTest --check
node blockchain/scripts/validate.mjs
node blockchain/scripts/artifacts.mjs --check
node blockchain/scripts/local-anvil.mjs
git diff --check
```

validate ejecuta también cobertura summary/LCOV, dos tests Node de guards RPC y
aritmética, y reconstruye normalmente antes de exportar/desplegar. Deno 2.2.12
existente usado exclusivamente para formato de herramientas; no se cambian
dependencias Deno/Node. actionlint 1.7.12 descargado/verificado con checksum
oficial para validar el workflow. La resolución y la validación completas se
repitieron en un clon temporal fuera del repositorio, sin herramientas/lib/out.

Foundry reporta **28 casos PASS**: 21 unit/fuzz (cuatro propiedades ×512), seis
escenarios deterministas de gas y un grupo que comprueba dos invariantes.
No se interpreta ese número como una medida de cobertura funcional. Seed
`0x9b20261012`, invariantes 128 runs/depth 64. En la campaña observada: configure
2.039, issue 1.973, revoke 2.114, unauthorized 2.066 llamadas; ningún revert del
handler/discard. Los reverts esperados del contrato se comprueban dentro del handler.
Modelo acotado a 16 K y dos I con firmantes distintos/compartido/retirado/ajeno;
presencia, C/I/registeredAt y revokedAt se contrastan tras cada operación.

Cobertura real del **código propio**, excluyendo tests y dependencias:

| Métrica Foundry | Resultado |
|---|---|
| Líneas | 47/47 — 100% |
| Sentencias | 63/63 — 100% |
| Ramas reportadas | 11/11 — 100% |
| Funciones | 10/10 — 100% |

LCOV conserva los hits por línea/rama. Están ejercitados los rechazos de entrada,
permisos, duplicado, ausencia, segunda revocación y timestamps, junto a rutas
válidas/no-op. El denominador de ramas no cuenta individualmente todas las
subcondiciones de cortocircuito. No cubre formalmente estados ilimitados, errores
del EVM/compilador, custodia comprometida, autorización humana o integración futura.
Coverage desactiva optimizer/viaIR para instrumentar; nunca se usa ese build para
ABI, gas aceptado o despliegue. El primer intento falló creando LCOV porque no
existía el directorio; validate lo crea y las ejecuciones finales terminan exit 0.

Gas snapshot normal (incluye overhead del escenario/harness, no precio de ETH):

| Escenario | Gas snapshot |
|---|---|
| Deploy | 674.597 |
| Configure | 54.519 |
| Issue | 101.998 |
| Read | 10.987 |
| Revoke | 37.717 |
| Rotate | 37.428 |

El gas report normal registra coste de despliegue 641.522 y tamaño de creación
2.885 bytes (runtime 2.580). getCertificate 7.070; issue min/max 21.484/93.868;
revoke 33.720; setIssuer min/max 32.099/49.211. El setup de dos escenarios pausa
la medición de gas y el promedio de issue incluye esas llamadas preparatorias;
no se presenta como coste universal de emisión. Receipts Anvil aportan gasUsed
de transacciones reales y varían con calldata/cuentas. `.gas-snapshot` versionado
se verifica sin tolerancia, solo sobre los seis escenarios deterministas.
En el último smoke Cancun, gasUsed real: despliegue 641.522, configuración
49.775, issue 94.972, rotación 32.675 y revoke 34.092; valores observados, no tarifas.

## Evidencia Anvil y artefactos

Cada smoke observado realiza 22 comprobaciones nominales y valida además receipts,
logs, estado y errores ABI. **16 receipts canónicos: ocho exitosos, ocho revertidos**.
Las ocho transacciones rechazadas son deliberadas y sus receipts status=0 no
se cuentan como escrituras exitosas. Códigos/topics/data y estado se comparan
contra valores esperados, no solo contra un exit 0 del comando.

La última evidencia local está en `blockchain/evidence/validation.json`, logs,
`blockchain/evidence/anvil/{manifest,receipts,smoke,cleanup}.json` y
`blockchain/coverage/lcov.info`. Cada ejecución conserva su directorio único en
deployments/. No se versionan outputs completos ni secretos; CI subirá evidencia
sanitizada del checkout que ejecute. HEAD/workingTreeDirty distinguen esta
validación sobre cambios sin commit de cualquier ejecución futura de Actions.

ABI generado estable: [CertificateRegistry.v1.abi.json](../blockchain/artifacts/CertificateRegistry.v1.abi.json).
Referencia normal: [build-reference.json](../blockchain/artifacts/build-reference.json).
Ejemplo exclusivamente sintético:
[manifest.synthetic.example.json](../blockchain/artifacts/manifest.synthetic.example.json).
Runtime Keccak-256 normal observado:
`0xa42546b2c85a5cac10660b194927686cf1147797b68088dc441fc50299f6da00`.
El manifiesto real incorpora chain ID, dirección, protocolVersion, ese hash del
eth_getCode exacto, transacción/bloque/hash de despliegue, genesis/environmentId,
versiones y fuentes/settings. Su referencia queda invalidada por el reset final
y la parada del Anvil: no es una configuración viva para el worker de 9C.

## CI, limitaciones y dictamen

[blockchain.yml](../.github/workflows/blockchain.yml) añade un job independiente
para PR y push a main. Checkout/setup-node/upload-artifact por SHA comprobados;
Foundry/solc oficiales y dependencias congeladas, fmt, build, unit/fuzz/invariantes,
coverage, gas/snapshot, smoke real/limpieza, artifacts --check, diff de outputs
versionados y whitespace. No continue-on-error. Los checks existentes permanecen
idénticos; CERTICHAIN_TEST_CAMERA=0 y motivo NOT_RUN se conservan.

**CI remoto NOT_OBSERVED**: no existe un commit nuevo publicado por este encargo.
El operador debe revisar/commit/push y observar el workflow del SHA resultante,
incluida la plataforma Linux. Ningún PASS previo de database/flutter/android
acredita blockchain ni estos cambios. No se ejecutaron regresiones de esas áreas
porque no se modificaron. No se despliega Sepolia ni se afirma finalidad PoS.

La revisión automática rechazó la eliminación recursiva del clon temporal propio
con `blocked by policy`, sin un motivo adicional. No se intentó eludir ese bloqueo.
Queda para limpieza manual, únicamente ese clon externo:
`C:\Users\bensa\AppData\Local\Temp\certichain-9b-clean-78bcb46e3f664352a1a10536fe5f0483`.
Su validation.json/tests.log/coverage.log se conservaron en
`blockchain/evidence/clean-checkout/`. No contiene claves ni dumps de Anvil.
La parada del ChildProcess Anvil de ambas validaciones sí pasó y se acredita
con cleanup.json; este pendiente de archivos temporales no es un fallo del contrato.

**Dictamen: apto para iniciar la implementación local de 9C.** Contrato conforme
a 9A, pruebas pertinentes, compatibilidad fijada, Anvil real y artefactos
reproducibles comprobados en Windows. Publicación y CI Linux del SHA exacto quedan
como acción del operador, claramente separadas de la aceptación local.
9C/9D/9E/10 no se adelantan: no adaptador/worker, migración, endpoint de anclaje,
DTO público v2, backfill ni Flutter. Revoke probado en contrato no habilita
revocación desde la app. El commitment acredita registro/autoridad técnica y
estado; comprobar un PDF exige apertura y no demuestra verdad académica.
