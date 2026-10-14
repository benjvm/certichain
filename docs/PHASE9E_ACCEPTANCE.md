# Aceptación del recorrido local — Fase 9E

Fecha: 14/10/2026. **Fase 9 cerrada para demo Web local, con limitaciones enumeradas**.
Aceptación completa ejecutada satisfactoriamente; no lanzamiento público ni testnet.
HEAD inicial `17c80df21ccdabd034c916252e4992ff3106800e`, árbol limpio.
HEAD permanece intacto; las pruebas nuevas identifican fuentes locales dirty.
Sin commit, push, merge, despliegue remoto ni datos reales.

## Base integrada y alcance

Referencia remota consultada por API GitHub el 14/10/2026:
`7737d303d6e3aa956481cbb7ca7cc2884426d7d8`. Los cuatro runs, sus jobs y
pasos pertinentes están completed/success, intento 1:

| Workflow | Ejecución de la base |
|---|---|
| Blockchain verification client | [38542815011](https://github.com/benjvm/certichain/actions/runs/38542815011) |
| Private durable anchoring | [38542814969](https://github.com/benjvm/certichain/actions/runs/38542814969) |
| Database permissions | [38542814699](https://github.com/benjvm/certichain/actions/runs/38542814699) |
| Blockchain registry | [38542814693](https://github.com/benjvm/certichain/actions/runs/38542814693) |

Se hizo fetch de main sin cambiar HEAD ni rama. El checkout inicial no contenía
el fix remoto: se incorporan exactamente sus fuentes del harness público,
helper de contadores, regresiones Node y control de formato de database.yml;
se conserva su documentación histórica en TESTING. No se relajan aserciones.
Contrato, ABI, locks, funciones de producto, migraciones y Flutter de producto
coinciden con la base integrada. No se añade una decisión estructural ni ADR.
Esos runs acreditan 9B–9D y componentes intactos; **CI 9E NOT_OBSERVED**.

## Matriz de aceptación

| Requisito | Evidencia anterior válida | Brecha y comprobación 9E |
|---|---|---|
| Publicación UI → Anvil → v2 → apertura → PDF | Recorrido real 9D | Volver a ejecutar main.dart release HTTPS desde entrada 9E, resumen propio |
| Worker externo, claves fuera del cliente | 9C/9D, build sin secretos | Mismo coordinador durable en host, deployment firmado normal nuevo |
| Respuesta perdida, concurrencia, fencing | Harness 9C; CI 38542814969 | Requests HTTP concurrentes, retry explícito, broadcast real interrumpido, lease vencido y CAS viejo; proceso CLI de producción nuevo confirma leyendo ledger persistido, seguido de anchor-progress |
| Replacements, nonce desconocido, historial incompleto | 9C; CI 38542814969 | Reutilizada: no cambia ese código; no atribuir sus 163 checks a ejecución 9E |
| Caída RPC, registro usable, reorg | HTTP/Anvil y Web 9D | Ejecutar pausa/reanudación y snapshot/revert reales; fecha original last_evidence |
| Reset y contrato equivocado | Backend 9C y SQL/lector 9D | Reset real después del recorrido; divergence, registro preservado y ninguna firma nueva |
| Apertura Auth y titular con emisor suspendido | 9D HTTP/SQL | Reejecutar; completar progreso ajeno, retirado, suspendido y miembro de otra institución |
| Renovación/logout/navegación/dispose | SDK, controladores y widgets 9D | Revalidación focalizada; respuesta real retenida entregada tras logout y login A→B |
| 429, global y Retry-After | HTTP 9D y renovación real 8D | v1/v2/compare comparten agotamiento; 429 real en UI, expiry sin POST automático, recuperación manual |
| DTO, JSON, archivos y privacidad | Parsers/widgets 9D | Selector Web real: export/import, cancelaciones, JSON inválido/>2 KiB, PDF vacío/>8 MiB, original/alterado; no upload |
| QR/enlace | 8B/8D; CI 38542814699 | QR de producción decodificado como imagen estática; clipboard solo enlace/código |
| Restore privado | pg_dump/pg_restore 9C, pérdida ledger real | Nuevo destino PG y bucket privado sintéticos; recuperar bytes exactos y comprobar H/K/I/C/S y estado canónico; fallo/recuperación de certificate-pdf |
| Plataformas, testnet y accesibilidad | Limitaciones explícitas 9D | Registrar separadamente; cámara omitida, sin atribuir ejecución nativa a widgets/build |

## Implementación y reproducción

`supabase/tests/run_phase9e.ps1` reutiliza prepare/stop_disposable_local de 9D.
Antes de arrancar valida Node 24.14.0, CLI 2.117.0, Deno 2.2.12, Foundry 1.8.5,
Solidity 0.8.37, Docker operativo y Flutter 3.47.4/Dart 3.13.3 con revisión exacta
9584c6713b324636289d067944a46fd6b49df14b. Bootstrap y wrapper Forge propios,
sin forge global ni actualización automática del SDK. BackendOnly no exige Flutter.
Build normal/artefactos/ABI comprobados antes de deployment.

SQL/RLS y lint se ejecutan antes de fixtures mutables en proyecto certichain_8d_UUID
nuevo, fuera del checkout, con puertos 55321/55322. Anvil firmado y red propios,
solo loopback al host; Edge usa anvil:8545 en esa red. Worker confiable externo a
Edge, no firma en Flutter. Se conservan permisos, v1/v2 y apertura Auth.

El módulo exportado runVerificationAcceptance comparte la lógica 9D/9E.
phase9e_checks añade exclusivamente comprobaciones de recuperación/permisos.
El navegador ejecuta los adaptadores de producción y no una pantalla de demo.
Contadores CDP por página reconocen POST v1/v2/compare, excluyen OPTIONS y
comprueban una sola v2 en arranque/recarga, incluidos duplicados tardíos.

```powershell
# Desde raíz, herramientas fijadas en PATH:
./supabase/tests/run_phase9e.ps1
# Mismo recorrido automático mostrando el navegador propio:
./supabase/tests/run_phase9e.ps1 -VisibleBrowser
# Solo infraestructura/HTTP/Anvil/restore: NO acredita Flutter:
./supabase/tests/run_phase9e.ps1 -BackendOnly
```

Equivalente CI: verification.yml mantiene SQL, Flutter, Deno y acciones fijadas,
preflight y ejecuta `phase9e_acceptance.ts` con las mismas funciones de aceptación.
El stack CI es exclusivo del runner fresco; stop siempre, sin continue-on-error.
No hay backfill, cron remoto, wallet EVM del alumno, NFT ni fase 10.
Revoke técnico del fixture únicamente prueba divergence, nunca revocación de producto.

## Evidencia y resultados

Outputs ignorados: mobile/build/phase9e-evidence/{preflight,result,browser,full,
backend-only,android}.json y attempts.ndjson. full conserva la pasada Web aunque
result pase a identificar una ejecución backend-only posterior.
Identifican HEAD, dirty, fecha UTC, versiones, modo, escenarios y contadores.
No guardan capturas de aperturas, PDFs, H/S, JWT, claves, dumps, URLs firmadas,
raw transactions ni PII. Archivos y exportación sintéticos permanecen solo en
temporales propios, retirados en finally. Copias exportadas por un usuario fuera
del harness quedan bajo su control; logout no promete borrarlas.

| Comprobación nueva ejecutada | Resultado |
|---|---|
| Preflight, build normal, artefactos y ABI | PASS |
| SQL/RLS y lint de esquemas propios | PASS, 860 comprobaciones y sin errores de schema |
| dart format, flutter analyze | PASS, sin cambios/incidencias |
| Flutter focalizado phase9d/verification_ui/verification_repository | PASS, 70 pruebas sin cámara |
| Node browser_harness_test + edge_runtime_test | PASS, 15; 1 SKIP de cámara con motivo exacto |
| Aceptación 9E completa | **PASS**, exit 0: 58 checks HTTP/Anvil/restore y 180 aserciones Web; main.dart release HTTPS, Chrome 155.0.8059.41, proceso CLI nuevo y cleanup PASS |
| Aceptación 9E backend-only | **PASS**, exit 0: 58 checks reales, SQL/lint, proceso CLI nuevo y cleanup. Flutter **NOT_RUN**; backend-only.json identifica fecha/HEAD/dirty. Intentos fallidos anteriores conservados |
| Restore PostgreSQL/Storage y acceso documental recuperado | PASS ejecutado en siguientes intentos, incluyendo H/K/I/C/S/anclaje y denegaciones cliente |
| Android nativo run_phase9e_native.ps1 | **FAIL última pasada**, intermitencia del driver/diálogo tras cancelar. Una pasada anterior sí completó export/import/cancel/match/mismatch reales; no se eleva a aceptación nativa estable |
| Deno tests v2/anchor handlers | PASS, 24 tests; no cambios en funciones de producto |
| Deno fmt/lint/check frozen, actionlint y sintaxis PowerShell | PASS local; no ejecutan Actions |
| flutter pub get --enforce-lockfile; npm ci --ignore-scripts --prefix tool; decoder --check | PASS; locks intactos, mismas dependencias |
| main.dart release --no-pub --no-web-resources-cdn | PASS compilación adicional; no sustituye el recorrido integral ejecutado |

Se conservan los intentos fallidos; solo una ejecución completa final satisfactoria
puede acreditar el cierre. No se fija un número de pruebas como condición de éxito.

Pasada Web final aceptada: evaluated_at `2026-10-14T18:28:58.142Z`, HEAD 17c80df… y dirty=true.
Contadores finales: una publicación, una solicitud de anclaje, dos obtenciones de
apertura explícitas, siete POST públicos; en la página anónima v1=0/v2=6/compare=0.
Una v2 por arranque/recarga, 429 sin petición al vencer, comprobación local sin POST.
Reorg/reset, permisos, restore y respuesta real retenida A→B pasan.

Historia de desarrollo: lectura del restore ejecutada con postgres tras --no-owner
era incorrecta; se usa supabase_admin en la copia. El decoder npm no se carga en
Deno: se ejecuta Node fijado, pasando la imagen pública por stdin en memoria.
Una lectura institucional Web dio 401 en un intento anterior; no se reprodujo en
las pasadas posteriores, sin cambiar Flutter/permisos ni relajar aserciones.
DOM.setFileInputFiles([]) de CDP no cancela un selector vacío: se usa el botón real
Cancelar comprobación, comprobando retirada del input. No se acredita un diálogo
OS Web con esa acción. Los selectores/lectura/exportación son adaptadores reales.
Un formato durante compilación encontró os error 1224 y se repitió sin lock.
El comando verify_qr.mjs sin argumentos falló y no cuenta como PASS; la imagen de
producción sí se decodificó con el enlace exacto durante la pasada completa.
Un renombrado del harness alteró por error los flags -f de pg_dump/rm; las pasadas
afectadas fallaron sin contar restore como PASS. Corregidos literalmente ambos
flags, la pasada completa final vuelve a demostrar restore y reinicio CLI.
Android conserva los deadlines de su driver y una pasada previa completa, sin
convertir el último FAIL en PASS ni atribuir la causa a producto sin demostrarla.

## Recuperación demostrable y límites

Restore usa pg_dump custom con umask 077 en el contenedor PostgreSQL propio y
pg_restore hacia otra BD sintética; compara identidad, operaciones e intentos
privados en memoria. Storage tiene copia de bytes independiente, recuperada por
API en bucket privado nuevo, nunca mediante copia/borrado de volúmenes reales.
Comprueba denegaciones cliente, SHA-256 exacto, K/I/S/C restaurados y registro EVM.
Solo el objeto sintético emitido en ese stack se retira/restituye para comprobar
404 y recuperación del acceso autorizado. Finally elimina bucket/BD/dump propios.

Restaurar bytes/ledger exactos en el entorno original conserva certificado,
apertura e identidad. Crear otra cadena/deployment NO reconstruye el anclaje
anterior: exige registro/configuración explícitos y aceptación nueva.
No reconstruye firmas ni consumos de nonce con ledger incompleto: se conserva
el bloqueo demostrado por 9C. No usar un receipt como permiso para saltar nonces.

| Plataforma o comprobación manual | Estado | Evidencia/motivo |
|---|---|---|
| Web Chrome release HTTPS | PASS | full.json y browser.json, main.dart real con backend/Anvil reales |
| Android adaptadores de archivos | FAIL aceptación estable | Una pasada anterior PASS completa con vector sintético 9B; última pasada FAIL tras cancelación. AVD/ADB propios y limpieza final PASS; android.json. Pendiente de diagnóstico/revisión manual |
| Android app completa Auth/Anvil | NOT_RUN | El entrypoint nativo es probe de adaptadores; build/widgets no sustituyen aceptación completa main.dart Android |
| iOS | NOT_RUN | Host Windows, sin dispositivo/macOS |
| Firefox/Safari | NOT_RUN | Aceptación automatizada usa Chrome; no se ha ejecutado esos navegadores |
| Sepolia y finality PoS | NOT_RUN | Sin despliegue autorizado/configuración; Anvil es not_applicable |
| Accesibilidad humana | NOT_RUN | Layout/semántica automáticos no son revisión humana |
| Cámara, también dobles | SKIP/NOT_RUN | Omitidas por instrucción del usuario; no hay cámara física disponible |

Migraciones nuevas: ninguna. No se editan migraciones compartidas. Entorno
habitual preservado; limpieza de stacks Supabase/Anvil propios completada. Un
temporal Android del primer intento queda para limpieza manual:
`C:\Users\bensa\AppData\Local\Temp\certichain-9e-native-fdcad127-9bd6-4555-94c8-c50c881486cb`.
El primer borrado encontró un archivo qcow2 aún ocupado al terminar el proceso;
el intento de limpieza posterior fue rechazado por revisión automática con
`blocked by policy`. No se elude ese bloqueo ni se hacen borrados generales.
CI del árbol
nuevo NOT_OBSERVED. **Dictamen: apto para iniciar Fase 10 en Web/local**: publicación,
anclaje, lectura separada, apertura e integridad y recuperación esenciales tienen
evidencia ejecutada satisfactoria. La revocación de producto sigue sin implementar.
Antes de aceptar Android se debe resolver su intermitencia de archivos; plataformas,
testnet/finalidad PoS, accesibilidad humana y protección contra abuso siguen
pendientes para lanzamiento público. No se promete restore remoto ni custodia de
producción. El temporal Android retenido por política es una limitación operativa
enumerada y no contiene datos reales; los procesos propios ya están detenidos.

Guion visible, comandos y pendientes manuales: [DEMO_BLOCKCHAIN_LOCAL](DEMO_BLOCKCHAIN_LOCAL.md).
