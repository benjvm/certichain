# Estrategia de pruebas

## Pirámide

- Muchas pruebas unitarias para entidades, casos de uso, mapeos y estados.
- Pruebas de integración para PostgreSQL/RLS, Storage, Edge Functions y adaptadores.
- Pocas pruebas end-to-end sobre los recorridos críticos.
- Pruebas específicas del contrato con Foundry.

## Flutter

Ejecutar como mínimo:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Casos prioritarios:

- redirección según sesión y estado de perfil;
- lista separada por usuario e institución;
- mapeo de fallos de red a errores de dominio;
- estados loading/empty/error/success;
- QR inválido, desconocido, válido, expirado y revocado;
- accesibilidad básica de pantallas principales.

## Capturas y regresiones de Flutter 4D

`mobile/test/certificate_detail_test.dart` carga los assets Inter e iconos Material
y recorre Inicio, wallet, detalle y perfil. Comprueba estados, navegación, reanudación,
respuestas sustituidas y cambio de sesión. Los adaptadores se prueban mediante
el SDK real y un servidor HTTP loopback, sin afirmar que se ha probado RLS real.

Para exportar las capturas sintéticas, desde `mobile/` en PowerShell:

```powershell
$env:CERTICHAIN_CAPTURE_DIR = Join-Path (Get-Location) 'build\phase4d-review'
flutter test test/certificate_detail_test.dart
Remove-Item Env:CERTICHAIN_CAPTURE_DIR
```

Se generan vistas superiores e inferiores a 390×844, 360×800 y 320×568; a 390 y
320 también con texto ×2. No se incluyen fixtures de estas capturas en producción.
Las capturas y las pruebas de layout no sustituyen una revisión en dispositivo.

## Base de datos y RLS

Probar con identidades y roles API distintos, nunca usar `service_role` para
demostrar restricciones de `authenticated`:

- estudiante A no puede leer el PDF o fila de B;
- una institución no lee ni revoca certificados de otra;
- ningún cliente emite ni revoca por INSERT/UPDATE, incluidos `issuer`, `admin`,
  `owner` y `platform_admin`, con institución `pending`, `verified` o `suspended`;
- anónimo no obtiene filas privadas (el DTO público sigue pendiente);
- preservar SELECT del titular, membresía institucional y administrador global;
- rechazar upsert, borrado y TRUNCATE, sin alterar certificados existentes.

El enum real de membresías solo incluye `owner`, `admin`, `issuer`; `viewer`
es una propuesta futura. 7A prueba Storage, formato y reservas persistentes;
validación estructural PDF, concurrencia del endpoint, verificación pública y
backend de emisión/revocación corresponden a incrementos posteriores.

`supabase db reset` debe reconstruir el esquema completo y cargar seeds sin intervención manual.

### Integración de autorización — Fase 5

`supabase/tests/certificate_authorization.test.sql` aporta 203 comprobaciones
pgTAP con ocho identidades Auth sintéticas, cinco instituciones, trece
membresías y seis certificados. El setup confiable solo crea fixtures; las
operaciones que prueban restricciones usan `SET LOCAL ROLE authenticated` o
`anon`, con `request.jwt.claims` y `request.jwt.claim.sub` coherentes. El helper
temporal es `SECURITY INVOKER` y comprueba `current_user` y `auth.uid()`.
Las funciones y fixtures de prueba desaparecen mediante ROLLBACK; no son RPC
ni datos de producción.

Se prueban los tres roles institucionales en los cuatro estados reales
(`pending`, `verified`, `suspended`, `rejected`), dos titulares, administrador
global, `owner` ajeno e `institution_admin` sin membresía. Cada contexto
comprueba lectura exacta, INSERT, revocación, modificación de metadatos, upsert,
DELETE y TRUNCATE. Tras cada contexto se compara **la fila completa de todos
los certificados**, incluidos PDF/hash, fechas y estado, con su snapshot.

Las consultas de wallet/detalle replican la selección mínima y el LEFT JOIN
opcional de 4D: un emisor invisible no elimina el certificado, y un ID ajeno
permanece inaccesible incluso sin filtro de titular. `anon` no obtiene filas
de ninguna de las cuatro tablas y tampoco puede hacer TRUNCATE CASCADE.
Las lecturas administrativas de instituciones y membresías se conservan.

Una prueba adicional concede INSERT/UPDATE únicamente dentro de la transacción
de test y confirma que, aun con ese grant, la ausencia de políticas de escritura
deniega INSERT y hace que UPDATE afecte cero filas, incluso al `platform_admin`.
El grant se retira antes de continuar y nunca modifica la seguridad persistente.
Esto verifica ambas barreras: grants y RLS, además de inspeccionar el catálogo.

`supabase/tests/profile_provisioning.test.sql` mantiene sus 39 pruebas y no
necesitó cambios del harness de roles. Ninguna migración histórica fue editada.

### Reconstrucción y comprobación local reproducible

Desde la raíz, con Docker y la CLI local disponibles:

```powershell
npx --no-install supabase db reset --local
npx --no-install supabase test db --local
npx --no-install supabase db lint --local --schema 'public,certichain_private' --level warning --fail-on warning
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_certificate_migration.ps1
git diff --check
```

Si el stack está detenido, arrancar antes con `supabase start`. Las comillas
del argumento de schemas son necesarias en PowerShell para pasar la lista
separada por comas como un solo argumento. No usar `--linked` ni URL remota.
`-ExecutionPolicy Bypass` se limita al proceso que ejecuta el script de prueba;
no cambia la política persistente del equipo.

El script de preservación reconstruye los grants y las dos políticas históricas
de escritura **solo en una transacción local**, reutiliza los fixtures SQL y
aplica la migración nueva con datos presentes. Compara exactamente las cuatro
tablas con snapshots y verifica el cierre de escrituras. Hace ROLLBACK incluso
de la restauración temporal de permisos. Los errores SQL abortan el proceso.
La CLI monta archivos de prueba aislados: no se usa `\ir` hacia migraciones
desde pgTAP porque no están disponibles en ese contenedor de ejecución.

Resultado real el 28/09/2026, Supabase CLI 2.117.0 y PostgreSQL local 17:

| Comando/comprobación | Resultado |
|---|---|
| `npx --no-install supabase --version` | 2.117.0; stack local ya arrancado |
| `npx --no-install supabase migration new close_direct_certificate_writes` | Creó la migración nueva |
| `npx --no-install supabase db reset --local` | Exit 0; cuatro migraciones aplicadas. Aviso: `seed.sql` no existe, no se cargaron seeds |
| `npx --no-install supabase test db --local` | Exit 0; 2 archivos, 242 pruebas PASS (203 autorización + 39 perfiles) |
| `npx --no-install supabase db lint --local --level warning` | Exit 0, pero informa errores/avisos de la extensión pgTAP en `extensions`, como tablas temporales inexistentes fuera de la sesión de test. No es un lint global limpio |
| `npx --no-install supabase db lint --local --schema 'public,certichain_private' --level warning --fail-on warning` | Exit 0; ambos esquemas del proyecto sin incidencias |
| `powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_certificate_migration.ps1` | Exit 0; migración sobre permisos históricos y seis certificados, cuatro tablas conservadas exactamente |
| Inspección local de `pg_policies`, ACL, funciones y roles mediante `docker exec … psql` | Solo SELECT en certificados; `authenticated` tiene SELECT; `anon` carece de grants; sin grants de columna ni roles heredados que reabran escrituras |
| `git diff --check` | Sin errores de whitespace; Git avisa de normalización LF/CRLF |

La ejecución inicial del script con `powershell -NoProfile -File …` fue
rechazada por la política de ejecución del equipo; se verificó con el comando
por proceso indicado arriba. Un primer test intentó incluir la migración con
`\ir` y falló por el montaje aislado de la CLI; el test entregado no depende
de esa inclusión. No hubo fallos persistentes del harness pgTAP al cambiar roles.

No se aplicaron cambios remotos ni se usó `--linked`. Las pruebas ejercitan
roles/claims en SQL, no un JWT firmado por el endpoint HTTP ni la traducción de
errores de PostgREST. No se ejecutaron Flutter ni Foundry: no se modificaron sus
áreas. No hay formateador SQL configurado; se revisó el formato siguiendo las
migraciones existentes y se validaron sintaxis/esquema mediante reset y lint.

### Administración y concurrencia — Fase 6

`supabase/tests/institution_administration.test.sql` añade **187 comprobaciones**
con identidades sintéticas y roles efectivos authenticated/anon. Conservamos las
203 comprobaciones de certificados y las 39 de perfiles (**429 en total**);
en perfiles solo se actualiza el mensaje esperado del trigger de rol y un
comentario, sin eliminar comportamientos probados. Migraciones históricas intactas.

Cobertura nueva:

- Bootstrap inicial y adicional por SQL confiable: confirmación, contador,
  identidad/perfil existentes, destinatario único, idempotencia y grants privados.
- Ausencia de promoción por metadatos, UPDATE propio o incluso UPDATE de roles
  por platform_admin en el rol API; ausencia de RPC público de escalada.
- Alta pending con primer owner; validación, duplicados y rollback del primer
  INSERT cuando un trigger de prueba hace fallar el segundo. Constraint diferible
  impide que SQL confiable cree una institución sin owner.
- Datos por owner/admin; membresías solo owner/plataforma; denegación de issuer,
  titular, owner ajeno y global institution_admin sin membresía.
- Estados reales y transiciones de revisión; todos los estados conservan
  administración autorizada y rechazan emisión/revocación directa.
- Último owner bajo degradación, baja y cascadas de perfiles/Auth; identidad de
  membresía inmutable y cierre de DELETE/TRUNCATE institucional incluso en SQL
  confiable, también TRUNCATE CASCADE desde perfiles.
- Catálogo de grants/RLS y regrant temporal de DML para probar la segunda barrera.
  Los 203 tests previos mantienen lecturas de wallet/detalle 4D y comparan filas
  completas tras operaciones de certificados rechazadas.

`supabase/tests/institution_concurrency.mjs` usa Node.js 22 (solo biblioteca
estándar) y Docker. Hace pg_dump **solo del esquema** real de public/auth/
certichain_private, lo reconstruye en una base `phase6_test_<aleatorio>` del
contenedor local y crea allí fixtures sintéticos. No copia datos ni compromete
fixtures en la base de aplicación. El finally elimina únicamente esa base
temporal; un fallo de SQL/expectativa/limpieza devuelve exit distinto de cero.
El acceso supabase_admin se limita a crear/restaurar/eliminar la base temporal;
las operaciones API se ejecutan como authenticated, nunca service_role.

Ejecuta los archivos operativos reales de bootstrap/demo, comprueba confirmación
del objetivo y rollback de la demo. Después abre dos conexiones psql, mantiene
la primera transacción abierta y **comprueba un lock wait real** de la segunda
en pg_stat_activity antes de permitir COMMIT. Prueba ocho escenarios:

| Escenario | Aislamiento | Segunda operación |
|---|---|---|
| Dos bajas por RPC | READ COMMITTED | Rechazada 23514, queda un owner |
| Dos degradaciones por RPC | READ COMMITTED | Rechazada 23514, queda un owner |
| Baja + degradación | READ COMMITTED | Rechazada 23514, queda un owner |
| Dos bajas con snapshot previo | REPEATABLE READ | Aborta 40001, queda un owner |
| Dos degradaciones con snapshot previo | SERIALIZABLE | Aborta 40001, queda un owner |
| Owner degradado mientras espera para añadir un miembro | READ COMMITTED | Rechazada 42501, permisos revalidados |
| Dos cascadas de Auth | READ COMMITTED | Rechazada 23514, queda un owner |
| Dos cascadas con snapshot previo | REPEATABLE READ | Aborta 40001, queda un owner |

Comandos desde la raíz (Docker local y CLI 2.117.0). Si la CLI no está instalada,
usar `npx --yes supabase@2.117.0` en lugar de `npx --no-install supabase`:

```powershell
npx --no-install supabase start
npx --no-install supabase db reset --local
npx --no-install supabase test db --local
node supabase/tests/institution_concurrency.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_certificate_migration.ps1
npx --no-install supabase db lint --local --schema 'public,certichain_private' --level warning --fail-on warning
node --check supabase/tests/institution_concurrency.mjs
git diff --check
```

Resultados realmente ejecutados el 28/09/2026 (CLI 2.117.0, PostgreSQL 17.6,
Node 22.14.0, Docker local):

| Comando | Resultado local |
|---|---|
| `supabase db reset --local` | Exit 0, cinco migraciones aplicadas; aviso de seed.sql ausente, sin fixtures de producción |
| `supabase test db --local` | Exit 0; 3 archivos, **429 tests PASS** (242 previos + 187 nuevos) |
| `node supabase/tests/institution_concurrency.mjs` | Exit 0; scripts operativos y **8 escenarios PASS**, solapamiento comprobado y base temporal eliminada |
| Script de preservación fase 5 | Exit 0; seis certificados y las cuatro tablas conservadas exactamente sobre permisos históricos |
| Lint public/certichain_private con fail-on warning | Exit 0; sin incidencias de esquemas propios |
| `node --check` y `git diff --check` | Exit 0; sintaxis válida y sin errores de whitespace |

Durante el desarrollo se corrigió el harness concurrente para envolver los
claims SET LOCAL en BEGIN/COMMIT y mostrar la etapa issuer en la demo. Las pruebas
de TRUNCATE vacían primero los eventos diferidos de constraints; de otro modo
PostgreSQL rechaza antes la sentencia con 55006 y no ejercita la guarda nueva. La entrega
final se verifica después de esas correcciones; no se cuenta un intento fallido
como prueba superada. No hay formateador SQL configurado: formato revisado según
las migraciones existentes y sintaxis verificada con reset, pgTAP y lint.

La [ejecución 36491581655](https://github.com/benjvm/certichain/actions/runs/36491581655)
de GitHub Actions terminó correctamente para Fase 6. El CI posterior de 7A
se detalla en 7B. No se ha aplicado migración remota ni ejecutado
bootstrap sobre personas reales. Las comprobaciones manuales de identidad,
proyecto y sesión JWT HTTP firmada están en
[INSTITUTION_ADMINISTRATION.md](INSTITUTION_ADMINISTRATION.md). Los tests SQL
ejercitan claims y roles, no el login HTTP ni mensajes traducidos de PostgREST.
No se ejecutan Flutter/Foundry porque no cambian sus áreas. Tampoco se afirman
pruebas de PDF, Storage, emisión, revocación, verificación pública o blockchain.

### Workflow real de base de datos

`.github/workflows/database.yml` se dispara en cada pull request y push a main.
Usa ubuntu-24.04, permisos contents:read, checkout sin persistir credenciales,
Supabase local y CLI fijada a 2.117.0. No exige SUPABASE_ACCESS_TOKEN, project ref,
service_role remoto ni secrets del repositorio; no enlaza un proyecto remoto.
Ejecuta start, reset, las 500 pruebas SQL (468 de 7A, 25 de 7B y 7 de 7C), formato/lint/
tipos/tests de funciones, HTTP de emisión/recuperación y Storage, concurrencia,
ambos scripts de preservación histórica y
lint de public/certichain_private con `--fail-on warning`, y detiene el stack
en always(). No usa continue-on-error ni silencia fallos con `|| true`.

Referencias verificadas en repositorios oficiales con `git ls-remote`:
[checkout v4.3.1](https://github.com/actions/checkout/releases/tag/v4.3.1)
(`34e114876b0b11c390a56381ad16ebd13914f8d5`),
[setup-cli v1.7.3](https://github.com/supabase/setup-cli/releases/tag/v1.7.3)
(`1dedf2c611547ede7232d26866dd3c56ab903bbb`) y
[CLI v2.117.0](https://github.com/supabase/cli/releases/tag/v2.117.0).
Estos uses se fijan al SHA completo; 7B añade setup-node fijado también por SHA.
Contrato de comandos:
[testing y linting de Supabase](https://supabase.com/docs/guides/local-development/cli/testing-and-linting).

Se excluye extensions del lint porque contiene pgTAP externo, con los avisos
documentados en fase 5. Los dos esquemas propios se comprueban enteros: no se
filtran errores del proyecto ni se rebaja su umbral. La ejecución de Fase 6
consta arriba; la ejecución posterior de 7A y su fallo de harness constan en el apartado 7B.

### Incremento 7A — datos y Storage

`supabase/tests/private_issuance.test.sql` añade 39 comprobaciones de
restricciones de hash/vínculos/estados, ámbitos de clave, conservación de filas
históricas sin PDF y con hash desconocido, revocación histórica, inmutabilidad,
grants/RLS y denegación con roles API efectivos. Las pruebas transaccionales
usan identidades sintéticas y no dejan datos en la base local.

`supabase/tests/private_storage.mjs` usa exclusivamente el API HTTP local de
Storage. Obtiene claves de desarrollo de `supabase status` en memoria, valida
un JWT sintético con el Data API, crea un objeto fixture mediante la API de
Storage, comprueba que anon y authenticated no pueden leer, listar, subir,
reemplazar ni borrar, verifica los bytes conservados y elimina el fixture por
la API en `finally`. Prueba MIME no PDF, tamaño de 8 MiB + 1 byte y colisión
con upsert deshabilitado. No manipula `storage.objects` por SQL ni necesita
proyecto o secretos remotos.

`supabase/tests/verify_private_issuance_migration.ps1` retrocede solo el
esquema de 7A dentro de una transacción local, inserta dos certificados
históricos sintéticos (sin PDF y con hash antiguo desconocido), reaplica la
migración y compara las filas sin la nueva columna. Después prueba su
revocación y hace ROLLBACK. El script previo de preservación de Fase 5 sigue
ejecutándose sin cambios.

Desde la raíz, con el stack local:

```powershell
npx --no-install supabase db reset --local
npx --no-install supabase test db --local
node supabase/tests/private_storage.mjs
node supabase/tests/institution_concurrency.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_certificate_migration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_private_issuance_migration.ps1
npx --no-install supabase db lint --local --schema 'public,certichain_private' --level warning --fail-on warning
node --check supabase/tests/private_storage.mjs
git diff --check
```

El reset comprueba además que la definición del bucket sobrevive a la
reconstrucción. Los tests SQL no prueban por sí solos el acceso HTTP a objetos;
por eso el workflow ejecuta también el script Storage. 7B deberá añadir
pruebas de parser PDF, autorización y bloqueo transaccional, reintentos
simultáneos, respuesta perdida y caídas entre subida y commit.

Resultado local del 30/09/2026, CLI 2.117.0:

| Comprobación | Resultado |
|---|---|
| `db reset --local` | Exit 0; seis migraciones y bucket recreado con límite 8 MiB/PDF privado |
| `test db --local` | Exit 0; **468/468 PASS** (429 anteriores + 39 de 7A) |
| `private_storage.mjs` | Exit 0; JWT local aceptado y denegaciones HTTP/bytes conservados, MIME y tamaño comprobados |
| `institution_concurrency.mjs` | Exit 0; ocho escenarios concurrentes PASS |
| Ambos scripts de preservación | Exit 0; datos históricos sin modificación y revocación posterior posible |
| `db lint --local --schema 'public,certichain_private' --level warning --fail-on warning` | Exit 0; sin incidencias |
| `node --check` y `git diff --check` | Exit 0; sin errores de sintaxis o whitespace (Git avisa conversión LF/CRLF) |

No se usó proyecto remoto ni secretos reales. La observación posterior del CI
de 7A consta en el apartado 7B. Los tests de 7A no validan un PDF estructuralmente ni
ejercen un endpoint de emisión: ambos pertenecen a 7B.

## Blockchain

Ejecutar:

```bash
forge fmt --check
forge test
```

Cubrir permisos, duplicados, eventos, revocación irreversible, consultas, fuzzing y consumo de gas relevante. Las pruebas de integración deben desplegar en Anvil y no depender de una testnet externa.

## End-to-end crítico

1. Administrador aprueba institución.
2. Institución emite certificado con PDF.
3. Proceso blockchain queda confirmado.
4. Estudiante lo ve y genera QR.
5. Anónimo obtiene resultado válido.
6. Copia modificada falla por integridad.
7. Institución revoca.
8. El mismo QR devuelve revocado.

## CI general previsto

El workflow de base de datos anterior está implementado. El objetivo completo
del proyecto para cada pull request añade además estas áreas cuando se incorporen
sus jobs (no se afirman como implementadas en Fase 6):

- formato y análisis de Dart;
- unit/widget tests de Flutter;
- formato, build y tests de Foundry;
- escaneo de secretos y dependencias.

Las pruebas que requieren credenciales externas se separan y nunca bloquean el desarrollo local sin una alternativa determinista.

## Definición de terminado

Un cambio incluye pruebas del comportamiento nuevo, mantiene los límites de autorización, actualiza fixtures/seeds si corresponde y deja documentado cualquier riesgo o comprobación manual pendiente.


## Incremento 7B — backend y recuperación verificados localmente

Entrega local del 30/09/2026: CLI 2.117.0, PostgreSQL 17.6, Node 22.14.0,
Deno 2.2.12 para formato/tipos/tests, Edge Runtime 1.74.3 compatible con Deno
2.1.4 para el endpoint. No se usa proyecto remoto ni secretos externos.

Archivos y cobertura nueva:

- `functions/issue-certificate/contract_test.ts`: 10 grupos con vectores exactos
  v1 en hex/hashes fijos, UTF-8 multibyte/NFC, UUID, NULL/longitud cero, orden,
  UTC con microsegundos, fechas imposibles, input cerrado, stream sin/mintiendo
  Content-Length, multipart duplicado, PDF corrupto/truncado/cifrado/activo,
  adjuntos, xref/endobj/Root inválidos, codecs/object streams, Flate acotado y 8 MiB.
- `handler_test.ts`: 7 casos con dependencias de red sustituidas; separación
  Auth/técnico, identidad verificada frente a metadata, fallo Auth/reserva,
  respuesta de upload perdida resuelta por lectura, lectura/publicación fallidas,
  respuesta de commit perdida y error interno seguro. Estas son unitarias;
  no sustituyen el endpoint local real.
- `issuance_backend.test.sql`: 25 comprobaciones transaccionales adicionales,
  grants, token/lease/estados, metadatos inmutables, comparación de hash,
  rollback de INSERT si falla completar, revalidación de estado institucional,
  resultado completed protegido, limpieza y guarda de revocación conservada.
  Mantiene íntegramente los 468 tests previos: total 493, cinco archivos.
- `issuance_http.mjs`: 368 aserciones con usuarios sintéticos creados por Auth
  local y login/password reales. Bootstrap SQL de plataforma y RPC reales de
  Fase 6 para owner/institución pending, verified y membresías. Owner/admin/issuer,
  ajeno/sin membresía/plataforma sin membresía, estados pending/rejected/suspended,
  titular inexistente/no elegible, token ausente/inválido/técnico, input prohibido,
  DML/RPC directos y SELECT de perfiles cerrado. PDFs válidos, Flate y corrupción,
  cifrado, adjuntos/acciones, MIME/extensión/tamaño y 8 MiB/+1; lectura de bytes y
  hashes técnicos coherentes con certificado/operación.
- HTTP: misma clave/otro contenido/otro actor, distintas claves con igual PDF,
  ocho solicitudes simultáneas y takeover simultáneo de lease vencido. Cortes
  after_reserve/upload/read/validate, before_publish y after_publish; rollback
  real PostgreSQL por trigger fixture al completar, sin éxito HTTP prematuro.
  Colisión de bytes distintos sin reemplazo, limpieza fallida/reintentada,
  subida tardía a lápida failed y protección efectiva del PDF completed.
  También se verifica baja de membresía después de upload y rechazo al publicar.
- `institution_concurrency.mjs`: conserva las ocho carreras originales y añade
  seis de emisión: reserva/publicación frente a baja y suspensión, además de
  REPEATABLE READ/SERIALIZABLE. Dos sesiones y espera de lock real en
  pg_stat_activity, seguidas de denegación/aborto; ninguna emisión no autorizada.
  La copia temporal contiene esquema sin datos de aplicación y se elimina.

El harness HTTP arranca/termina `supabase functions serve` con verify_jwt=true.
Las claves locales y contraseñas aleatorias viven solo en memoria; el token de
inyección se escribe temporalmente fuera del repo y se elimina. Los hooks solo
se conectan en runtime local explícito, sin DENO_DEPLOYMENT_ID. No hay cuentas
reales ni secretos versionados. El teardown usa API Storage para PDFs y Auth
para identidades. Para retirar exclusivamente fixtures con FK circular/guardas
last-owner, usa una transacción local confiable supabase_admin con locks
exclusivos y triggers temporalmente desactivados en esas tablas; restaura todo
antes de commit. No es una operación de producto ni migración. Tras el test,
consultas locales confirmaron cero usuarios, instituciones y operaciones.

### Comandos reproducibles (solo local)

Con Docker local, CLI 2.117.0 instalada y Node 22.14.0. En desarrollo la CLI puede
estar instalada como paquete npm 2.117.0 accesible desde el repo; los scripts
eligen binario global si existe y, en su defecto, el shim npm sin shell. CI
instala el binario con setup-cli; no depende de npx --no-install para encontrarlo.
No añadir --linked, --no-verify-jwt ni secretos de un proyecto remoto.

```powershell
npx --no-install supabase start
npx --no-install supabase db reset --local
npx --no-install supabase test db --local
npx --yes deno@2.2.12 fmt --check supabase/functions supabase/scripts/local_supabase.mjs supabase/tests/issuance_http.mjs supabase/tests/pdf_fixture.mjs supabase/tests/institution_concurrency.mjs supabase/tests/private_storage.mjs supabase/admin/reconcile_issuance.mjs
npx --yes deno@2.2.12 lint supabase/functions
npx --yes deno@2.2.12 check --frozen --config supabase/functions/deno.json supabase/functions/issue-certificate/index.ts
npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions/issue-certificate
node supabase/tests/issuance_http.mjs
node supabase/tests/private_storage.mjs
node supabase/tests/institution_concurrency.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_certificate_migration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_private_issuance_migration.ps1
npx --no-install supabase db lint --local --schema 'public,certichain_private' --level warning --fail-on warning
node --check supabase/tests/issuance_http.mjs
node --check supabase/admin/reconcile_issuance.mjs
node supabase/admin/reconcile_issuance.mjs --local
git diff --check
```

Si se usa binario global, sustituir npx --no-install supabase por supabase.
Las comprobaciones de formato no reescriben archivos; deno fmt sin --check aplica
el formato. No hay formateador SQL configurado: se conserva el estilo existente,
se reconstruye con reset y se comprueba con pgTAP/lint. SQL tests y preservación
van secuencialmente sobre la BD local; concurrencia usa su propia base temporal.

### Resultados ejecutados

| Comprobación | Resultado local |
|---|---|
| db reset --local | PASS, siete migraciones; bucket PDF privado 8 MiB; sin seeds |
| test db --local | PASS, 493/493, conserva las 468 de 7A |
| deno fmt/lint/check --frozen | PASS en archivos afectados, sin incidencias |
| deno test --frozen | PASS, 17 tests; vectores/hash conocidos y fallos de dependencias |
| issuance_http.mjs | PASS, 368 aserciones con Auth/Edge/Storage reales |
| private_storage.mjs | PASS, barreras anon/authenticated, MIME/tamaño/no upsert y bytes intactos |
| institution_concurrency.mjs | PASS, 14 carreras (8 previas + 6 emisión) con lock waits observados |
| Ambos scripts de preservación histórica | PASS, conserva filas sin PDF/hash antiguo y revocación posterior |
| Lint public,certichain_private | PASS, sin warnings/errors; no se excluye código propio |
| node --check y git diff --check | PASS |
| Reconciliador CLI --local | PASS, cola vacía; limpieza real/fallida/tardía y completed probados por HTTP |

En el runtime local inspeccionado, los workers tienen memoryLimitMb=256,
cpuTimeSoftLimitMs=1000 y cpuTimeHardLimitMs=2000. La emisión HTTP del PDF exacto
de 8 MiB y FlateDecode pasó bajo esa configuración. Los 17 tests Deno terminaron
en aproximadamente 0,75 s; no equivale a CPU/pico de memoria de una carga remota.
No se afirma compatibilidad con todo PDF ni antivirus. Las restricciones de
formato y recursos son parte explícita del contrato de SECURE_ISSUANCE.md.

Durante desarrollo se corrigieron el arranque npm en Windows (argumento env-file
interpretado por npx), el teardown fixture que necesita supabase_admin para FK,
y el uso de 40001 para lease perdido que PostgREST reintentaba hasta timeout.
Se usa PT409 para fencing, y 40001/40P01 siguen siendo errores reales de
concurrencia. Los resultados de arriba son posteriores a las correcciones,
no intentos fallidos contados como éxitos. Flutter/Foundry no cambian y no se
han ejecutado sus pruebas.

### CI observado, separado de local

Se observó mediante API GitHub autenticada en memoria la
[ejecución 36696424479](https://github.com/benjvm/certichain/actions/runs/36696424479)
para commit 7A `9f4bab8b0ea969ccfdeb4f4bd1f9808d155a4ebd`: **failure**. Start,
reset y SQL permission tests pasaron; Private Storage HTTP tests falló con
Local Supabase status unavailable. Los pasos posteriores quedaron skipped.
Causa del harness: npx --no-install no encontraba la CLI instalada por setup-cli.
Se corrige la selección de CLI compartida; no se modifica la migración de 7A.

El workflow actualizado fija Node 22.14.0 (setup-node v4.4.0 al SHA verificado),
CLI 2.117.0 y Deno 2.2.12, usa lock frozen, añade formato/lint/tipos/unitarios,
HTTP Auth/Edge/recuperación y diff check; conserva SQL, Storage, concurrencia,
preservación y lint propio. Todo contra el stack local sin secrets externos.
El 30/09/2026 se observó mediante API GitHub autenticada en memoria el CI del
último commit 7B `b7310c8dafda03bd043876d4ebb51a250be2d6e2`:
[ejecución 36707359039](https://github.com/benjvm/certichain/actions/runs/36707359039),
estado completed, conclusión **success**. Esta observación sustituye la falta
de evidencia de CI registrada al entregar 7B. No constituye CI de los cambios
7C actuales. No se ha publicado ni desplegado a Supabase remoto.

## Incremento 7C — cliente institucional y documento privado

Entorno ejecutado el 30/09/2026: Windows, Flutter estable 3.47.4
(`9584c6713b324636289d067944a46fd6b49df14b`), Dart 3.13.3, Chrome headless
aislado, Node 22.14.0, Supabase CLI 2.117.0 y Deno 2.2.12. Solo stack local.
Los scripts HTTP usan identidades sintéticas, Auth/Edge/Storage reales, secretos
locales en memoria/temporales fuera del repositorio y teardown en finally.

| Comprobación | Resultado local |
|---|---|
| db reset --local | PASS, ocho migraciones; bucket privado sin permisos directos nuevos |
| test db --local | PASS, 500/500; conserva las 493 anteriores y añade 7 |
| Deno formato/lint/check frozen/tests | PASS; 28 pruebas, 17 previas y 11 del endpoint PDF |
| issuance_http.mjs | PASS, 368 aserciones; recuperación, autorización y límites 7B conservados |
| certificate_pdf_http.mjs | PASS, 86 aserciones reales y vencimiento efectivo de capacidad |
| private_storage.mjs | PASS, bucket privado y denegaciones anon/authenticated |
| institution_concurrency.mjs | PASS, 14 carreras (8 previas + 6 de 7B) |
| Preservación histórica, ambos scripts | PASS; conserva certificados legados y revocación histórica |
| db lint public,certichain_private | PASS, sin warnings propios |
| dart format lib test tool / flutter analyze | PASS, formato y análisis estricto sin incidencias |
| flutter test | PASS, 116; 1 omitida opt-in de Auth local, sin acceso remoto |
| Flutter Web build en Chrome loopback | PASS, selector HTML real, cancelación, borde 8 MiB/+1, bytes exactos, Blob/filename, sin navegación y revocación del Blob |
| flutter build web | PASS, main.dart y adaptadores condicionales compilados |
| git diff --check | PASS |

Las 48 pruebas Flutter nuevas se reparten entre dominio/controlador (15),
adaptadores (9) y widgets (24). Incluyen roles owner/admin/issuer y estados,
múltiples instituciones, pérdida de membresía/suspensión abierta, renovación de
sesión y cambio de identidad; copiar/pegar ID; tres pasos/validación/archivo,
doble envío y 200/201; huella NFC/UTC/microsegundos con vector conocido del
backend; bytes inmutables y borde de 8 MiB; clave congelada, lease, conflicto,
failed, respuesta perdida, recibo previo a HTTP, fallo de persistencia,
reinicio/reconstrucción exacta y aislamiento por identidad/institución.

Adaptadores comprueban selección mínima/RLS y filtro institucional explícito,
orden/límite/count, multipart/JWT real del objeto de sesión SDK y errores públicos.
Documento prueba URL nueva por descarga, bytes/MIME/límite, TTL ≤60, rechazo de
URL externa, sesión expirada y ausencia. Selector/guardado nativos prueban API
multiplataforma con sustituto del plugin. Widgets conservan el detalle personal
fuera del contexto emisor y verifican carga/ausencia/401/descargas sucesivas.

certificate_pdf_http.mjs emite por 7B y prueba titular/owner/admin/issuer,
extranjero, otra institución, platform_admin sin membresía, anónimo/token técnico
como sesión, legado y objeto ausente. Baja de issuer y suspensión deniegan URLs
nuevas; titular conserva acceso. Comprueba no-store/CORS, respuesta mínima,
token con exp−iat = 60, bytes exactos y espera hasta caducidad real (64 segundos).
No se imprime la capacidad ni se abre el bucket a usuarios.

Responsive: Datos/Confirmar/éxito y listado/PDF en 390×844, 360×800 y 320×568,
texto ×1/×2, sin overflow con Inter e iconos cargados. Capturas inspeccionadas
de confirmación, formulario pequeño/texto ×2 y listado. Reproducir:

```powershell
cd mobile
$env:CERTICHAIN_CAPTURE_DIR = "$PWD/build/phase7c-review"
flutter test test/institution_ui_test.dart
```

Comprobación Chrome reproducible, usando los adaptadores reales, sin cuentas:

```powershell
flutter build web --no-web-resources-cdn --target=tool/pdf_browser_smoke.dart --output=build/browser-smoke
node tool/pdf_browser_smoke.mjs
```

El runner abre su propio Chrome headless y perfil temporal, sirve exclusivamente
loopback y elimina solo ese perfil al terminar. Inyecta selección sintética mediante
DataTransfer; verifica APIs DOM y bytes, no la interacción humana con el diálogo OS.
El test paralelo `flutter test --platform chrome test/pdf_download_browser_test.dart`
se conserva en CI Linux. En este SDK Windows el runner Flutter convierte la ruta
CanvasKit a separadores Windows y responde 404; esas invocaciones fueron detenidas
y **no se cuentan como PASS**. La comprobación sobre build evita ese problema sin
modificar el SDK. La selección Web usa HTMLInputElement estándar; el selector
inicial del plugin no conectaba sus nodos al DOM bajo este build y se sustituyó
por el adaptador Web explícito. file_picker se actualizó a 13.1.0 para los
adaptadores nativos; decisiones/alternativas en FLUTTER_ARCHITECTURE.md.

CI ampliado conserva el job de base local y añade endpoint PDF; otro job Flutter
fija SDK al commit anterior, pub get --enforce-lockfile, formato/analyze/tests,
tests Chrome y ambos builds. No exige credenciales Supabase remotas. Solo se ha
observado CI exitoso de 7B (enlace anterior); **no se afirma CI de 7C**, cambios
sin push. No se ejecutó despliegue, migración remota ni almacenamiento remoto.

No se probaron dispositivos físicos Android/iOS, builds APK/IPA, diálogos nativos
reales, lectores de pantalla ni el recorrido humano completo con varias cuentas
en un navegador. 7D debe añadir E2E completo, pruebas nativas, carga/abuso,
compatibilidad PDF y endurecimiento operativo. QR, verificación pública,
blockchain, invitaciones por email y revocación no forman parte de 7C.
