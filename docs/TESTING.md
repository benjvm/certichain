# Estrategia y comandos de pruebas

La evidencia vigente, con SHA y enlaces a CI, está en [PHASE10_ACCEPTANCE](PHASE10_ACCEPTANCE.md). Este documento mantiene comandos y criterios reproducibles; los diarios de intentos anteriores se conservan en Git.

## Capas y cobertura

| Área | Qué se comprueba | Fuentes |
|---|---|---|
| Flutter | Dominio, DTO, repositorios, sesión, widgets, navegación y adaptadores | `mobile/test/` |
| SQL/RLS | Grants, aislamiento, administración, integridad, locks y revocación | `supabase/tests/*.test.sql` |
| Backend | Handlers, límites, privacidad, coordinador y lector EVM | `supabase/functions/**/*_test.ts` |
| HTTP real | Auth, Edge, Storage, idempotencia, capacidades y budgets | `supabase/tests/` |
| Solidity | Autorización, duplicados, revocación, eventos, fallos, fuzz e invariantes | `blockchain/test/` |
| Web real | main.dart release HTTPS, servicios reales, QR estático, PDF y cambio de cuenta | `mobile/tool/blockchain_verification_browser.mjs` |
| Recuperación | Firma durable, nonces, reorg, respuesta perdida, fencing y restore | Runners 9C/9E/10 y suites phase10 |

## Exclusión de cámara

Antes de cualquier suite mixta:

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
```

Omitir captura, permisos/ciclo de vida, escáner real, getUserMedia, vídeo emulado y probes QR nativos, incluidos sus dobles. Registrar SKIP/NOT_RUN, nunca PASS, con el motivo exacto:

> Omitidas por instrucción del usuario; no hay cámara física disponible

No omitir una suite completa. Conservar códigos manuales, enlaces, generación/decodificación de QR estático, comparación PDF, Auth, backend, SQL y blockchain. No ejecutar los probes de cámara opt-in para completar los comandos siguientes.

## Flutter

Desde `mobile/`, con las versiones de [DEVELOPMENT](DEVELOPMENT.md):

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter test --platform chrome test/pdf_download_browser_test.dart test/verification_repository_test.dart
```

Generación QR y decoder independiente, con assets ignorados:

```powershell
$env:CERTICHAIN_QR_CAPTURE='build/phase8b-qr.png'
flutter test test/verification_ui_test.dart
npm ci --ignore-scripts --prefix tool
node tool/verify_qr.mjs build/phase8b-qr.png http://localhost:7357/#/verify/e42f105a-a36b-40de-8326-47da5749eae3
node tool/prepare_decoder.mjs --check
```

Los tests semánticos y builds no sustituyen revisión humana, una prueba nativa completa ni cámara física. El nombre de los fixtures históricos no limita el alcance actual de las comprobaciones.

## Regresiones Node y backend

Desde raíz:

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
node --test mobile/tool/browser_harness_test.mjs supabase/tests/edge_runtime_test.mjs supabase/tests/phase10_evidence.test.mjs blockchain/scripts/download.test.mjs blockchain/scripts/harness.test.mjs
npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions supabase/tests/phase10_gateway_policy_test.ts
```

El harness comprueba compromiso de documento CDP tras recarga, exclusión de credenciales públicas, una sola consulta por navegación y rechazo de duplicados tardíos. Chrome se comprueba por proceso/DevTools propio, no por un `sleep` fijo. `browser_harness_smoke.mjs` ofrece un smoke real de Chrome sin cámara:

```powershell
node mobile/tool/browser_harness_smoke.mjs
```

El helper `local_browser_auth.mjs` revalida Auth/SELECT después del build release. Solo `401/PGRST303/JWT issued at future` repite hasta tres GET (500/1000 ms); login, mutaciones, otros rechazos y tráfico del navegador no se reintentan. Los diagnósticos son categorías cerradas sin bodies/tokens/claims. Un deadline semántico identifica el control esperado; comprobar las respuestas anteriores antes de atribuirlo a rendimiento.

Formato/lint/tipos deben seguir los targets exactos del workflow afectado: [database](../.github/workflows/database.yml), [verification](../.github/workflows/verification.yml) o [revocation](../.github/workflows/revocation.yml). El lint opcional de todo el harness Node incluye hallazgos preexistentes; no atribuirle un PASS por haber verificado solo el helper.

## Contrato y artefactos

```powershell
node blockchain/scripts/bootstrap.mjs
node blockchain/scripts/validate.mjs
node blockchain/scripts/artifacts.mjs --check
node blockchain/scripts/backend-abi.mjs --check
```

`validate.mjs` ejecuta formato, build normal, tests, fuzz, invariantes, cobertura, snapshot de gas, vector compartido y smoke Anvil real. Usa herramientas aisladas y checksums fijados; no necesita el `forge` global. [Referencia de comandos](../blockchain/README.md).

## SQL, HTTP y aceptación integral

Usar un stack desechable nuevo, nunca una base habitual con datos. Los runners preparan su proyecto fuera del checkout, prueban SQL antes de fixtures mutables y limpian sus recursos. Ejecutarlos **secuencialmente**:

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1
# Regresión independiente de emisión/anclaje y ledger:
./supabase/tests/run_phase9c.ps1
# Compatibilidad del recorrido anterior y restore:
./supabase/tests/run_phase9e.ps1
```

`-BackendOnly` evita atribuir Flutter a una prueba solo HTTP/SQL/Anvil. La variante `-VisibleBrowser` del runner 10 muestra el mismo viaje automático. El proyecto fresco de CI puede usar `supabase test db --local` y `supabase db lint --local --schema public,certichain_private --level warning --fail-on warning`; no copiar comandos de reset al stack habitual.

Los harnesses HTTP individuales de emisión, Storage, PDF, verificación pública, comparación y concurrencia se ejecutan en el orden y aislamiento del workflow database. Para diagnosticar un caso aislado, preparar primero un stack con `prepare_disposable_local.ps1`; usar su copia de los harnesses y después `stop_disposable_local.ps1 -Root` con la ruta exacta. `CERTICHAIN_TEST_DISPOSABLE=1` por sí solo no autoriza un proyecto cualquiera.

## Evidencia y definición de terminado

Cada pasada integral identifica run_id, SHA/dirty, modo, versiones y fecha. Los resúmenes iniciales son NOT_RUN y se finalizan después de cleanup. Un error temprano, browser/preflight de otro run, fecha incoherente o cleanup fallido impide PASS. Backend-only no reutiliza un PASS Web anterior.

Interpretar por separado `result`, `flutter`, `stack_cleanup` y diagnóstico estricto de gateway. La [excepción JWT](SECURITY.md#excepción-del-gateway-jwt) no transforma la ausencia de no-store en una reparación del proveedor. Nunca publicar informes con PII, PDF/apertura, hash/salt privados, dumps, URLs firmadas, claves o raw transactions.

Un cambio termina con comportamiento y errores relevantes cubiertos, checks del área ejecutados, documentación actualizada y límites no verificados explícitos. Para cambios únicamente documentales: comprobar enlaces y anchors, rutas/comandos contra el código y `git diff --check`; no presentar como nueva ejecución de producto una consulta a CI existente.
