# Demo reproducible blockchain local — Fases 9 y 10

## Demo de revocación completa 10E — 18/10/2026

[Matriz, versiones y dictamen vigente](PHASE10_ACCEPTANCE.md). Reutiliza los
prerrequisitos/aislamiento siguientes y el entrypoint de producto main.dart.
Los apartados de 9E inferiores son historia de aquella fase, no límites actuales
del flujo de revocación ni resultados nuevos. Operación remota es exclusivamente
manual según [REVOCATION](REVOCATION.md).

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1 -VisibleBrowser
# Misma aceptación sin ventana visible:
./supabase/tests/run_phase10.ps1
```

Guion breve (no pulsar simultáneamente durante la automatización):

1. Owner sintético verified emite el PDF privado. Titular abre wallet/detalle,
   obtiene PDF/apertura y genera QR/enlace público. Worker confirma el issue real.
2. En Certificados emitidos, abrir Revocación / consultar estado, introducir
   motivo privado, cancelar una vez y confirmar explícitamente. El harness descarta
   la respuesta 202 real: mostrar incertidumbre y recuperar con la misma clave.
3. Wallet/detalle indica Revocado y fecha SQL. Público conserva SQL revocado
   mientras worker está pendiente y también con RPC temporalmente indisponible.
4. Reanudar RPC/worker y actualizar manualmente: evidencia issue original y
   transacción revoke distintas; Anvil sin finalidad PoS. Comparación PDF/apertura
   original/alterada nunca se presenta como vigencia. Motivo solo institucional.
5. Retener respuesta privada, logout/cambio de cuenta y liberarla tarde: los datos
   no reaparecen. El runner limpia exclusivamente sus recursos y finaliza informes.

Revisar mobile/build/phase10-evidence/{run,preflight,result,full,browser}.json:
mismo run_id/SHA/dirty, fechas de esta pasada, resultado final y stack_cleanup.
history/<nuevo-run_id>/ conserva informes anteriores; un navegador antiguo no
acredita el actual. -BackendOnly no demuestra Web. No publicar dumps, PDF,
aperturas, salts, tokens, raw transactions o capturas privadas. Sin cámara;
QR de imagen estática sí. Los pasos manuales de backup/migración/configuración/
publicación/worker/recuperación se enlazan, no se ejecutan remotamente.

## Incremento local de revocación — 15/10/2026

[REVOCATION](REVOCATION.md) define los endpoints Auth, motivo/auditoría privados,
SQL irreversible, worker durable y evidencia pública v3 con issue/revoke separados.
V1/v2 y compare conservan contrato; la app usa v3. Resultados ejecutados y
dictamen vigente: [PHASE10_ACCEPTANCE](PHASE10_ACCEPTANCE.md). Los apartados
que describen revocación futura conservan el contexto histórico de sus fases.
La demo se reproduce con `./supabase/tests/run_phase10.ps1`; sin despliegue remoto,
Sepolia ni corrección Android atribuida. Cámara=0 con la exclusión persistente.

## Base de fase 9 reconsultada — 15/10/2026

main/HEAD revisados: `bb2a93c61950f258136bc88d4b9ad44b46848fc5`.
API GitHub: cuatro workflows completed/success, intento 1, para ese SHA:
[Database permissions 38645390011](https://github.com/benjvm/certichain/actions/runs/38645390011),
[Blockchain verification client 38645389979](https://github.com/benjvm/certichain/actions/runs/38645389979),
[Private durable anchoring 38645389971](https://github.com/benjvm/certichain/actions/runs/38645389971),
[Blockchain registry 38645389759](https://github.com/benjvm/certichain/actions/runs/38645389759).
Actualiza el NOT_OBSERVED histórico del árbol 9E/base; se conserva el registro
anterior más abajo. No acredita los cambios locales de fase 10: su CI sigue
**NOT_OBSERVED**. Android archivos conserva la incidencia 9E; plataformas,
Sepolia y accesibilidad humana no se elevan a PASS por estos runs.


Esta demo usa main.dart de producción, Web release por HTTPS y Auth, Supabase,
Storage, Edge y Anvil reales. El worker durable corre en el host confiable fuera
de Edge. No cámara ni testnet. No equivale a lanzamiento público ni revocación
de producto. Resultados y límites: [PHASE9E_ACCEPTANCE](PHASE9E_ACCEPTANCE.md).

## Prerrequisitos y preparación del operador

1. Revisar HEAD y cambios con `git rev-parse HEAD` y `git status --short`.
2. Docker operativo con contenedores Linux; puertos 55321/55322 y HTTPS 7360
   disponibles. No parar procesos/stack ajenos para liberar puertos.
3. Node **24.14.0** en PATH (ver .node-version); Supabase CLI **2.117.0** instalada
   o resoluble por el wrapper. Deno **2.2.12** vía npx fijado.
4. Flutter **3.47.4**, Dart **3.13.3**, revisión
   `9584c6713b324636289d067944a46fd6b49df14b`. No actualizar SDK/locks para la demo.
5. Chrome instalado o CHROME_EXECUTABLE apuntando al ejecutable local. OpenSSL:
   en Windows se reutiliza el de Git; OPENSSL_EXECUTABLE permite ruta explícita.
6. Resolver dependencias congeladas si el checkout es nuevo:

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
Push-Location mobile
try {
  flutter pub get --enforce-lockfile
  if ($LASTEXITCODE -ne 0) { throw 'Flutter lock failed' }
  Push-Location tool
  try {
    npm ci --ignore-scripts
    if ($LASTEXITCODE -ne 0) { throw 'Node lock failed' }
    node prepare_decoder.mjs --check
    if ($LASTEXITCODE -ne 0) { throw 'Decoder drift' }
  } finally { Pop-Location }
} finally { Pop-Location }
```

Bootstrap Foundry, checksums/versions, build normal, ABI, TLS efímero, usuarios
sintéticos, institución verified, deployment nuevo y binding I/signer son
**automáticos** dentro del runner. No introducir cuentas, PDFs o claves reales.
No proporcionar secretos EVM a Flutter ni publicarlos en terminal o capturas.
El runner completo y CI resuelven pub/npm con locks congelados y comprueban el
decoder; el build real usa --no-pub para conservar esa resolución. Backend-only
no instala dependencias Flutter/decoder ni acredita sus plataformas.

## Ejecución y recorrido visible

```powershell
# Desde raíz: automático y navegador propio visible para seguir el recorrido.
./supabase/tests/run_phase9e.ps1 -VisibleBrowser
# Aceptación reproducible sin ventana:
./supabase/tests/run_phase9e.ps1
# Únicamente backend: NO es aceptación Web.
./supabase/tests/run_phase9e.ps1 -BackendOnly
```

La automatización realiza las interacciones siguientes con controles de la UI
real. El operador observa, evitando pulsaciones simultáneas durante la pasada:

1. Institución autorizada: Espacio institucional → Emitir certificado → datos
   de titular sintético → seleccionar PDF original → confirmar publicación.
2. Certificados emitidos → Solicitar anclaje / consultar operación → confirmar.
   Ver requested pendiente; publicación SQL y evidencia EVM son independientes.
3. Worker host persiste/firma/envía y reconcilia. Actualizar estado manualmente
   desde UI → confirmed. No polling ni repetición automática de escritura.
4. Titular: detalle → Mostrar QR y enlace → Copiar enlace. QR contiene solo URL
   pública/código; decodificación automática de imagen estática, sin cámara.
5. Blockchain → Consultar evidencia → Obtener apertura → Exportar apertura JSON.
   Son acciones explícitas. El PDF se conserva y la apertura es privada.
6. Tercero en otro contexto sin sesión: abrir enlace → una consulta v2 → Comprobar
   con apertura → importar exportación → seleccionar original: match local.
7. Reimportar → seleccionar copia alterada: PDF no coincidente. No se sube PDF,
   apertura ni salt al verificador. Match no acredita identidad/verdad académica.

La ventana visible es una ayuda de demostración, no una acreditación automática
de accesibilidad humana. Sin dispositivo conectado, Android queda NOT_RUN;
compilar APK o widgets no sustituye su selector nativo. La exportación sintética
del harness se retira al acabar; copias realizadas voluntariamente fuera del
harness quedan bajo control del usuario y no se borran por cerrar sesión.

## Fallos recuperables automáticos

- Worker ausente: pendiente, registro público usable; ejecución explícita del
  worker y Actualizar estado recuperan. Reintento/concurrencia usan misma operación.
- Interrupción después de broadcast: worker nuevo consulta hash persistido y
  confirma sin firmar otro intento. Lease vencido/CAS antiguo rechazados.
- Anvil pausado: registro SQL vigente, evidencia unavailable y last_evidence con
  fecha original. Reanudar y Actualizar comprobación recuperan evidencia actual.
- Snapshot/revert real: reorged; worker reincluye mismo compromiso. Anvil nunca
  demuestra finalidad PoS. Reset final: divergence, sin off_chain_only ni firma
  contra contrato distinto. Ningún manifiesto antiguo vuelve a ser vivo.
- JSON inválido/>2 KiB, PDF vacío/>8 MiB y cancelación: estado recuperable; nueva
  selección explícita. PDF original/alterado permanecen locales.
- Agotamiento compartido real: 429 con Retry-After. Vencer el contador no consulta;
  Actualizar comprobación es la acción necesaria de recuperación.
- Respuesta privada retenida: logout/login A→B antes de entregarla; no reaparece.
- Restore PG a BD nueva y Storage a bucket privado nuevo: recuperar bytes y
  comprobar H/K/I/C/S/anclaje; retirada/restauración solo del objeto sintético
  propio demuestra fallo y recuperación de descarga/apertura autorizadas.

El revoke técnico final del fixture comprueba divergence con SQL activo; **no**
es un botón ni flujo de revocación de producto. Fase 10 permanece pendiente.

## Evidencias, limpieza y acciones manuales

El operador revisa mobile/build/phase9e-evidence/{preflight,result,browser}.json:
HEAD/dirty/fecha/versiones, modo full/backend-only y escenarios realmente
ejecutados. Solo una pasada full satisfactoria acredita Flutter. No publicar
temporales, dumps, aperturas, PDFs, credenciales, raw transactions o capturas
privadas; el workflow sube únicamente los tres JSON sanitizados.

Finally restaura variables, cierra navegador/perfil/TLS/archivos sintéticos,
Anvil/red/Edge propios, bucket/BD de restore y stack descartable. No reset del
habitual. Si falla limpieza, conservar la ruta exacta indicada; corregir únicamente
ese recurso propio, nunca usar prune o borrados generales. El wrapper muestra
`PASS own disposable stack stopped and directory removed` solo tras completarla.

Pendientes **manuales**, sin PASS automático: accesibilidad con lector de pantalla,
archivos en Android/iOS, Firefox/Safari y testnet. Cámara SKIP/NOT_RUN:
«Omitidas por instrucción del usuario; no hay cámara física disponible».
CI nuevo NOT_OBSERVED hasta publicar y observar el SHA correspondiente; esta tarea
no autoriza commit/push ni despliegue remoto.

Si existe un AVD Android instalado (en este host, Pixel_2), desde raíz:
`./mobile/tool/run_phase9e_native.ps1 -TemplateAvd Pixel_2`.
El runner copia únicamente configuración, crea userdata/AVD y servidor ADB
propios, desactiva ambas cámaras y prueba los adaptadores reales de JSON/PDF con
el vector público sintético 9B. No modifica ni arranca el AVD habitual. Esta
prueba nativa complementaria no acredita un recorrido Auth/Anvil en main.dart
Android ni convierte evidencia sintética en evidencia canónica real. Resultados
separados en mobile/build/phase9e-evidence/android.json.

Sepolia solo cuando el operador tenga autorización de despliegue y configuración
válida: revisar 9A/ADR-0014 y BLOCKCHAIN_OPERATIONS, registrar manifiesto nuevo
verificado, configurar signers backend por secretos, ejecutar solicitud/worker,
comprobar doce confirmaciones y finalized canónico por separado, evidencia y
limpieza propios. Sin esa autorización/configuración: **NOT_RUN**, sin comandos
de despliegue ejecutados ni Anvil presentado como sustituto PoS.
