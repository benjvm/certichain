# Aceptación de revocación — Fase 10

15/10/2026. Base/HEAD inicial y remoto main reconsultados:
`bb2a93c61950f258136bc88d4b9ad44b46848fc5`, árbol inicial limpio. Cambios locales
sin commit/push/merge/despliegue remoto ni datos reales. **Revocación completa aceptada para demo Web local**, con los límites enumerados. CI de fase 10 NOT_OBSERVED
hasta observar el SHA que contenga estos cambios. Los cuatro success de fase 9
(38645390011/38645389979/38645389971/38645389759) acreditan solo la base.

## Entrega verificable 10A–10E

| Incremento | Implementación |
|---|---|
| 10A | Migración nueva 20261015100000: decisión y alias privados, guard irreversible/identidad, autorización owner/admin verified/suspended, transición SQL inmediata, cancelación unsigned y outbox por todos los anchors |
| 10B | revoke-certificate, revocation-progress, reauthorize-revocation; Auth real, JWT, contrato cerrado acotado, idempotencia y auditoría; no-store y denegaciones uniformes |
| 10C | Coordinador, autorización SQL, persistencia/recuperación de revoke; canRevoke, eventos y C/I canónicos; issue tardío esperado, nonces/reverts/rotación/reorg sin reactivar SQL |
| 10D | Feature revocation/domain/data/presentation; motivo privado/confirmación, recuperación manual y barreras de sesión; wallet/detalle y público v3 con fechas y evidencia issue/revoke separadas |
| 10E | Runner propio run_phase10.ps1, SQL/preservación antes de fixtures, Auth/Storage/Edge/Anvil reales y main.dart release HTTPS; pruebas de fallos, regresiones y revocation.yml congelado |

Migración pública nueva 20261015110000 añade snapshot v3 en una sentencia.
V1/v2 cerrados conservados, sin salts/actor/motivo público ni nuevo enum público.
Contrato/ABI/build 9B y dependencias de producto intactos. [ADR-0018](adr/0018-irreversible-revocation-and-public-v3.md)
y [REVOCATION](REVOCATION.md) detallan política, campos, errores y pasos MANUALES.

## Evidencia ejecutada (actualizable al terminar la pasada)

Windows x64, PowerShell, Node 24.14.0 (PATH de tarea, sin cambiar instalación),
Supabase CLI 2.117.0, Deno 2.2.12, Docker 29.8.2, Foundry 1.8.5/Solidity 0.8.37,
Flutter 3.47.4/Dart 3.13.3 revisión 9584c6713b324636289d067944a46fd6b49df14b.

| Ejecución observada | Resultado |
|---|---|
| SQL/RLS con migraciones nuevas y regresiones | PASS: 925 comprobaciones, sin relajar aserciones |
| Lint public/certichain_private | PASS sin errores |
| Preservación de migración sobre históricos activos/revocados | PASS en transacción rollback-only propia, sin inventar auditoría/identidad/elegibilidad |
| Deno funciones completas | PASS: 115 tests; tipos/lint y formato se verifican separadamente |
| Node browser/Edge harness | PASS: 17; SKIP cámara con motivo exacto y fixture Unix en Windows |
| Flutter phase10 dominio/adaptadores/widgets | PASS: 13; analyze sin incidencias en última ejecución |
| Flutter suite completa, cámara=0 | PASS: 241, 12 exclusiones existentes (cámara/opt-in local); formato de 141 archivos sin cambios y analyze sin incidencias |
| Foundry contrato intacto | PASS: 28, incluidos fuzz e invariantes 128×64; fmt --check |
| Regresión real 9C sobre migraciones finales | PASS: 163 checks, incluidos tres replacements y ganador antiguo, ledger perdido, reorg, rotación/revert y reset; SQL/lint previos y cleanup PASS |
| Última aceptación integral Web | **PASS**: 182 checks backend/SQL/HTTP/Anvil/restore y 177 aserciones Web, Chrome 155.0.8059.41; cleanup propio PASS |
| Última backend-only con dos deployments reales | **PASS**: 189 checks, mismas regresiones SQL/preservación/lint y cleanup; Flutter NOT_RUN, sin reemplazar full.json |
| Flutter regresiones phase9d/verificación | PASS: campaña focalizada 76 incluida fase10 inicial |
| Flutter regresiones instituciones/wallet/detalle/emisión | PASS: 70 incluidas seis pruebas fase10; análisis anterior tenía dos avisos de llaves, corregidos y reanalizados |
| Backend real inicial | PASS: 129 checks; no acredita Flutter ni nuevas ampliaciones posteriores |
| Recorrido Web real de segunda pasada | PASS: 173 aserciones, incluida SQL→revoke EVM→evidencia anónima |
| Resultado integral de esa pasada | FAIL después de navegador: deadline temporal del adaptador reutilizado por una inyección de fallo. Corregido aislamiento del harness; exige nueva pasada completa |
| Actionlint y sintaxis PowerShell | PASS local; no equivalen a Actions |

Se conservan intentos en mobile/build/phase10-evidence/attempts.ndjson. Primera
pasada Web falló buscando etiqueta/hash en un mismo texto seleccionable; se
separó el rótulo visible conforme al panel existente. Un fixture SQL inicial
cambió estado institucional sin claims de plataforma: falló; corregido usando
la autorización existente. Un fmt encontró os error 1224 y se repite al liberar
el archivo. Ninguno de esos intentos se transforma retroactivamente en PASS.

## Matriz de aceptación real

phase10_checks cubre owner/admin, verified/suspended, issuer/titular/ajeno/
plataforma/anon/pending/rejected, idempotencia/concurrencia/respuesta perdida,
off-chain/cancelación unsigned, firmas issue tardías, canIssue=false/canRevoke=true,
baja de miembro y reautorización auditada, RPC detenido, reorg real issue/revoke,
preservación de PDF/apertura, históricos y ausencia de motivo público.

phase10_faults cubre crashes de revoke antes de persistir firma, después de
persistir/broadcast/receipt, proceso CLI nuevo, CAS vencido, firma durable después
de perder membresía, saldo, nonce desconocido sin saltos, deployment disabled y
writes_stopped, permiso retirado, revert consumido, rotación con otra EOA y receipt
issue incompatible con revoke. phase10_deployments comprueba contrato nuevo real mientras hay issue firmado en el
anterior deshabilitado, sin redirigir firmas ni crear salts. phase10_concurrency añade barreras SQL reales para
ambos órdenes de revocación/baja de miembro. La pasada completa ejecutó checks/faults/concurrency. La pasada backend-only
posterior ejecutó además la prueba de dos deployments reales: PASS sin atribuirla
al Web previo.

El navegador reutiliza el arranque Chrome/readiness/CDP aislado de fase 9. Cuenta
v1/v2/v3/compare por pathname y POST; comprueba una consulta pública al arrancar/
recargar, incluidos duplicados tardíos y mezclados. Mantiene QR de imagen estática,
comparación PDF/apertura local, Auth, Storage y respuesta real retenida tras logout.
Worker externo al cliente; claves solo en host. No capturas de apertura ni
secretos/PDF/H/S/raw/JWT/capacidades/dumps en los resúmenes.

## Reproducción y límites

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1
# Solo backend, no acredita Flutter:
./supabase/tests/run_phase10.ps1 -BackendOnly
```

SQL y preservación preceden fixtures mutables. Cada runner usa stack Supabase,
Anvil, red, procesos, perfiles Chrome y temporales propios. finally detiene solo
esos recursos; el entorno habitual no se resetea. Las pasadas completas
anteriores y la última satisfactoria limpiaron sus stacks/directorios. El stack backend inicial también
se detuvo y retiró. Cleanup de las pasadas finales Web y backend-only: PASS; stacks, Anvil, redes y
temporales propios retirados, con entorno habitual preservado.

Android archivos conserva la incidencia 9E (última aceptación nativa estable FAIL);
no se atribuye corrección. Android app completa, iOS, Safari, Firefox, Sepolia/
finalidad PoS y accesibilidad humana NOT_RUN sin evidencia propia. Anvil usa
not_applicable. No lanzamiento público ni custodia/restore remoto acreditados.
Cámara, incluidos dobles de permisos/captura/ciclo de vida, **SKIP/NOT_RUN**:
«Omitidas por instrucción del usuario; no hay cámara física disponible».

La pasada integral satisfactoria identifica HEAD bb2a93c6… y dirty=true, inicio
2026-10-15T18:31:58.486Z. full.json conserva 182 checks y browser.json 177
aserciones; una publicación, un anchor, una revocación, dos aperturas y siete
POST públicos. Página anónima: v1=0/v2=0/v3=6/compare=0. La siguiente pasada
backend-only no reemplaza esa evidencia Web. Backend-only posterior: inicio
2026-10-15T18:37:27.886Z, 189 checks, PASS, stack_cleanup=PASS. El navegador
final se evaluó a las 18:34:59.362Z (20:34:59 en Madrid).

**Dictamen: revocación completa aceptada para demo Web local.** No equivale a
lanzamiento público. CI del SHA futuro, Android archivos/app completa, iOS,
Safari/Firefox, Sepolia/finalidad PoS y accesibilidad humana conservan sus límites.

## Archivos y comandos de validación

Nuevos: ambas migraciones indicadas; functions/revoke-certificate,
revocation-progress, reauthorize-revocation y verify-certificate-v3; feature Flutter
revocation y parser/panel público; phase10_checks/faults/concurrency/deployments/
acceptance, revocation.test.sql, verify_revocation_migration.ps1, run_phase10.ps1;
phase10_test y phase10_adapters_test; revocation.yml; REVOCATION y ADR-0018.
Integración en main/app/workspace/wallet, coordinador/adaptador/puerto, handler v2
con selector explícito v3, harness y contadores, configuración y documentos
ROADMAP/SECURITY/TESTING/SECURE_ISSUANCE/PUBLIC_VERIFICATION/BLOCKCHAIN_OPERATIONS/
BLOCKCHAIN_VERIFICATION/DEMO_BLOCKCHAIN_LOCAL; historia 9E preservada.

Comandos realmente ejecutados desde raíz (Flutter desde mobile):

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1
./supabase/tests/run_phase10.ps1 -BackendOnly
./supabase/tests/run_phase9c.ps1
npx --yes deno@2.2.12 fmt --check supabase/functions supabase/tests/phase10_acceptance.ts supabase/tests/phase10_checks.ts supabase/tests/phase10_faults.ts supabase/tests/phase10_concurrency.ts supabase/tests/phase10_deployments.ts
npx --yes deno@2.2.12 lint supabase/functions supabase/tests/phase10_acceptance.ts supabase/tests/phase10_checks.ts supabase/tests/phase10_faults.ts supabase/tests/phase10_concurrency.ts supabase/tests/phase10_deployments.ts
npx --yes deno@2.2.12 check --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts supabase/tests/phase10_acceptance.ts supabase/functions/verify-certificate-v3/index.ts supabase/functions/revoke-certificate/index.ts supabase/functions/revocation-progress/index.ts supabase/functions/reauthorize-revocation/index.ts
npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions
node --test mobile/tool/browser_harness_test.mjs supabase/tests/edge_runtime_test.mjs
node blockchain/scripts/forge.mjs fmt --check
node blockchain/scripts/forge.mjs test
# Desde mobile:
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

Además: actionlint 1.7.12 de los cinco workflows, parser PowerShell de los dos
scripts nuevos, enlaces Markdown locales y git diff --check. Los runners ejecutan
pub/npm congelados, decoder --check, build normal/ABI congelado, SQL, preservación,
lint y aceptación. No se han actualizado SDKs/locks/dependencias ni migraciones
compartidas. La incidencia de formato 1224 se resolvió y el último check pasó.
