# Estrategia de pruebas

Versiones actuales 8D: Node 24.14.0, Flutter 3.47.4/Dart 3.13.3, CLI 2.117.0 y
Deno 2.2.12. Los resultados/versiones de entregas anteriores se conservan como
evidencia histórica. Para ejecutar ahora, usar [DEMO_VERIFICATION.md](DEMO_VERIFICATION.md)
y la matriz de [PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md).


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
- anónimo no obtiene filas privadas (8A expone exclusivamente el DTO mediante Edge);
- preservar SELECT del titular, membresía institucional y administrador global;
- rechazar upsert, borrado y TRUNCATE, sin alterar certificados existentes.

El enum real de membresías solo incluye `owner`, `admin`, `issuer`; `viewer`
es una propuesta futura. 7A prueba Storage, formato y reservas persistentes;
7B–7D añaden validación PDF, concurrencia y backend de emisión; 8A incorpora
verificación pública. El nuevo flujo de revocación permanece pendiente.

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

`supabase/tests/institution_concurrency.mjs` usa Node.js 24.14.0 (solo biblioteca
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
Ejecuta start, reset, las 557 pruebas SQL (500 de 7A–7C y 57 de 8A), formato/lint/
tipos/tests de funciones, HTTP de emisión/recuperación y Storage, concurrencia,
los tres scripts de preservación histórica y
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
tests Chrome y ambos builds. No exige credenciales Supabase remotas. El 04/10/2026
se consultaron los jobs de la [ejecución 37206437013](https://github.com/benjvm/certichain/actions/runs/37206437013)
mediante el conector GitHub: `database` y `flutter`, completed/**success**, con
todos sus pasos de validación correctos, para el commit 7C publicado
`7830bf56af61344ee7011bac9b594630bea11c00`. Esta evidencia sustituye la falta de CI
registrada al entregar 7C; no acredita cambios posteriores de 7D.
No se ejecutó despliegue, migración remota ni almacenamiento remoto.

No se probaron dispositivos físicos Android/iOS, builds APK/IPA, diálogos nativos
reales, lectores de pantalla ni el recorrido humano completo con varias cuentas
en un navegador. 7D debe añadir E2E completo, pruebas nativas, carga/abuso,
compatibilidad PDF y endurecimiento operativo. QR, verificación pública,
blockchain, invitaciones por email y revocación no forman parte de 7C.

## Incremento 7D — recorrido completo y endurecimiento local

Ejecutado el 04/10/2026 desde main `7830bf56af61344ee7011bac9b594630bea11c00`:
Windows, Flutter/Dart 3.47.4/3.13.3, Node 22.14.0, CLI 2.117.0, Deno 2.2.12,
Chrome headless aislado y Supabase local. No hay migraciones nuevas ni despliegue
remoto. La evidencia de CI de 7C está en el apartado anterior; estos resultados
7D corresponden a ejecución local.

### Cobertura y reproducción

`local_issuance_fixture.mjs` crea usuarios por Auth y obtiene sesiones con password
real, ejecuta `admin/grant_platform_admin.sql` con UUID confirmado/contador y usa
RPC administrativos para instituciones verified/pending/suspended y miembros.
Todo es sintético y solo se acepta API loopback:54321. Arranca su propio
`functions serve` con JWT habilitado. El token de fallos vive en un archivo temporal
fuera del repo; credenciales/JWK permanecen en memoria del runner. El navegador
recibe clave pública, cuentas sintéticas y un JWT vencido de prueba, nunca claves
técnicas ni de firma. La firma original ES256 de Auth se verifica con su clave
del contenedor local antes de cambiar exp y firmar el fixture vencido.

`mobile/tool/secure_issuance_browser.dart` monta **CertiChainApp y adaptadores de
producción**, no mocks. LiveWidgetController pulsa controles y introduce texto
por EditableText; DataTransfer alimenta el selector HTML real. El transporte
observa peticiones y retiene/descarta respuestas reales, sin fabricarlas:

- Estados institucionales bloqueados; ID inexistente, PDF inválido rechazado por
  el parser real y +1 byte sobre 8 MiB bloqueado antes de HTTP, con estados UI.
- Dos pulsaciones, respuesta de publicación descartada y recibo persistido;
  reconstrucción incorrecta bloqueada, reconstrucción exacta obtiene completed
  con la misma clave/ID y elimina el recibo. Una sola fila/operación/objeto final,
  SHA-256 y huella Dart/backend coincidentes, metadatos y wallet del titular correctos.
- INSERT directo en certificates y create/replace/delete Storage denegados para
  emisor, titular y ajeno; filas y bytes posteriores intactos. Un DELETE 200 vacío
  de Storage se evalúa por su efecto real, no como autorización.
- Respuesta de listado retenida al cambiar institución; respuesta del backend
  retenida al cambiar identidad y membresías retenidas al renovar token. No
  reaparecen resultados anteriores. Baja de miembro elimina listado; ajeno no
  recibe detalle/PDF ni acceso institucional.
- Titular ve emisión y legado propio; legado sin PDF tiene estado indisponible.
  Tras suspensión, dos acciones solicitan autorización nueva y guardan Blob con
  bytes exactos, sin navegar ni enviar JWT a la capacidad. Un JWT correctamente
  firmado pero vencido obtiene 401 del gateway y destruye sesión/rutas visibles.

El runner `.mjs` sirve exclusivamente loopback, crea Chrome con perfil temporal,
comprueba estado final en PostgreSQL y Storage y escanea el build por la clave
service_role local. Los fallos de interfaz se diagnostican solo con etiquetas
de prueba, sin cuerpos, capacidades ni credenciales. Espera estados reales de UI,
fin de animación, hit testing y llegada de respuestas; no usa pausas como evidencia
de éxito. Plazo global Web 240 s; cada espera UI/barrera <=25 s.

`issuance_hardening.mjs` conserva la batería HTTP 7B y añade negativos con
institución pending/suspended, sin membresía, plataforma sin membresía y rol global
institution_admin insuficiente, titular inexistente/no holder/no confirmado,
documento inválido, +1 byte y JWT vencido. No existe un rol institucional inferior
a issuer en este esquema; no se inventa uno para la prueba.

Dos barreras de fila institucional detienen cuatro solicitudes cada una: emisión
con la misma clave y takeover tras upload con lease vencido. Se observan **los
cuatro backends esperando lock en pg_stat_activity** antes de liberar. Estado final:
un certificado/operación/objeto por clave, enlaces/actor/titular y hashes correctos;
el takeover conserva ID/huella/bytes y cambia token. Cambiar metadatos o PDF causa
conflicto sin reemplazo. Limpieza fallida mantiene objeto y cleanup_pending;
reintento del reconciliador deja failed, cero certificados y ausencia real del
objeto. Se espera que acaben todas las peticiones antes del teardown.

Compatibilidad sintética: xref clásico PDF 1.4/1.7 con texto Helvetica e Info
Unicode, 100 páginas y Flate de 16 MiB descomprimidos aceptados; 101 páginas,
16 MiB +1 descomprimidos y PDF 2.0 rechazados. La batería 7B conserva cifrado,
acciones/adjuntos, corrupción, codecs/object streams y 8 MiB exactos/+1.
Carga nueva: 12 solicitudes inválidas en lotes de cuatro y ocho válidas de 1 MiB
en dos lotes de cuatro. Presupuesto: <=4 simultáneas, <16 MiB enviados en el
corpus/carga medido y <180 s, timeout HTTP 30 s. No es un rate limiter ni una prueba
de denegación de servicio sostenida, antivirus o compatibilidad universal.

`certificate_pdf_http.mjs` añade firma posterior al iat real (otra URL), y comprueba
que una capacidad ya concedida conserva bytes después de la baja hasta su TTL.
Storage firma a segundos: firmas independientes en el mismo segundo pueden ser
iguales. Se mantienen respuesta mínima, no-store del endpoint, permisos actuales,
TTL real de 60 s y rechazo HTTP tras 64 s. No se promete revocación instantánea.

Teardown: Storage DELETE por API para rutas de operaciones fixture, SQL confiable
local con locks exclusivos/guardas restauradas para retirar solo UUID propios,
Auth DELETE con confirmación de ausencia (también si su respuesta se pierde).
Se comprueban cero certificados, operaciones, objetos, instituciones y usuarios
del fixture. Nunca se modifica storage.objects por SQL. Se retiran token temporal
y perfil Chrome aun si falla la prueba; el reset limpio elimina restos de intentos
de desarrollo anteriores. Los harness de funciones se ejecutan secuencialmente.

Desde la raíz, después de arrancar el stack local:

```powershell
npx --no-install supabase db reset --local
npx --no-install supabase test db --local
npx --yes deno@2.2.12 fmt --check supabase/functions supabase/tests/*.mjs supabase/scripts/local_supabase.mjs supabase/admin/reconcile_issuance.mjs mobile/tool/secure_issuance_browser.mjs
npx --yes deno@2.2.12 lint supabase/functions
npx --yes deno@2.2.12 check --frozen --config supabase/functions/deno.json supabase/functions/issue-certificate/index.ts supabase/functions/certificate-pdf/index.ts
npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions
node supabase/tests/issuance_http.mjs
node supabase/tests/issuance_hardening.mjs
node supabase/tests/private_storage.mjs
node supabase/tests/certificate_pdf_http.mjs
node supabase/tests/institution_concurrency.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_certificate_migration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File supabase/tests/verify_private_issuance_migration.ps1
npx --no-install supabase db lint --local --schema 'public,certichain_private' --level warning --fail-on warning
node supabase/admin/reconcile_issuance.mjs --local
cd mobile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --no-web-resources-cdn --target=tool/secure_issuance_browser.dart --output=build/secure-issuance-e2e
node tool/secure_issuance_browser.mjs
flutter build web
flutter build apk --debug
```

El comando fmt equivalente con lista explícita, sin expansión de wildcard, está
en database.yml y se ejecutó así en Windows. `node --check` en scripts afectados
y `git diff --check` completan la comprobación. No usar --linked ni claves remotas.

### Resultados finales ejecutados

| Comprobación | Evidencia local |
|---|---|
| Reset / SQL | Exit 0, ocho migraciones y **500/500 PASS** |
| Deno formato/lint/check frozen/tests | Exit 0, **28/28**, conserva todos los anteriores |
| Emisión HTTP 7B | Exit 0, **368 aserciones** |
| Hardening 7D | Exit 0, **135 aserciones**, 14 publicaciones/objetos íntegros; 8 457 193 bytes en corpus/carga; 17,2 s; lotes 4×1 MiB: 1,30/1,26 s |
| Storage privado | Exit 0, denegaciones API, límites y bytes intactos |
| PDF HTTP | Exit 0, **92 aserciones**, firma nueva y vencimiento efectivo incluidos |
| Concurrencia institucional/emisión | Exit 0, **14 carreras**, locks observados y denegación/aborto comprobados |
| Preservación histórica (ambos scripts) | Exit 0, filas históricas intactas y revocación histórica posible |
| Lint public,certichain_private / reconciliador | Exit 0, sin incidencias propias / cola vacía |
| Flutter unitarias/adaptadores/widgets | Exit 0, **121 PASS**, una antigua opt-in omitida; cinco regresiones nuevas de sesión |
| Flutter Web E2E | Exit 0, **69 aserciones Flutter +29 host**, backend real, estado final y teardown comprobados |
| Formato/análisis Dart y Web de main | Exit 0, 79 archivos sin cambios de formato, análisis sin incidencias y build Web de producción |
| Probe Chrome anterior de 7C | Exit 0 sobre build real: selector/cancelación, 8 MiB exactos/+1, bytes, Blob, sin navegación y revocación de URL |
| Android build de main | Exit 0, APK debug; adaptadores nativos compilados |
| Android diálogos reales | Exit 0 en Pixel_2, Android API 34; cancelación, selección, guardado y bytes finales exactos |

La regresión de readIssued falló antes de la corrección: devolvía CertificateWallet
después de logout/renovación. También iniciaba HTTP sin sesión y readMemberships
aceptaba la respuesta de un token anterior del mismo usuario. Ahora se compara
identidad/token/caducidad al iniciar y recibir; no cambian SELECT ni permisos.
Los tests anteriores y la UI permanecen; no se añadieron dependencias.

### Android e iOS: alcance efectivo

Se detectó Pixel_2 y se arrancó sin ventana. El probe nativo usa **adapters y
diálogos reales**, sin sustituir file_picker. Es un vector sintético de diez bytes
con extensión .pdf para probar transporte/guardado; no valida estructura PDF ni
reproduce Auth/emisión nativa. UIAutomator pulsa el diálogo del sistema y ADB
extrae el archivo guardado para compararlo. Solo se instala si com.example.mobile
no existía; se elimina ese probe y sus archivos UUID propios al terminar.

Con dispositivo de prueba ya arrancado y desde mobile:

```powershell
flutter build apk --debug --target=tool/pdf_native_smoke.dart
./tool/pdf_native_smoke.ps1 -Serial emulator-5554
```

El script es opt-in local, requiere ADB y sistema en inglés, no forma parte del CI
Linux sin dispositivo. No se comprobaron teléfonos físicos, permisos/diálogos de
otros fabricantes, emisión completa Android, iOS/build IPA/diálogos iOS (sin
macOS/Xcode/dispositivo), lectores de pantalla ni todos los generadores/lectores PDF.
Estas comprobaciones **no se declaran PASS**. La prueba nativa de adaptadores
unitaria con sustituto del plugin se conserva, diferenciada del probe real.

### CI 7D y límites pendientes

database.yml conserva reset, SQL, funciones, HTTP, Storage, PDF/TTL, concurrencia,
preservación y lint; añade hardening y el build/E2E Flutter Web sobre **ese mismo
stack local**. Mantiene el job Flutter separado con pruebas, Chrome y builds
anteriores. Fija el mismo SDK/CLI/Node/Deno y no necesita secretos remotos.
El job database dispone de 40 minutos por la instalación adicional del SDK.

El runner Flutter `--platform chrome` se conserva para CI Linux; no se volvió a
ejecutar en Windows por la limitación CanvasKit descrita en 7C. Chrome sí ejecutó
los builds locales del harness E2E y del probe de adaptadores. No se confunden
esas ejecuciones con una prueba del runner Flutter que no se pudo ejecutar.

El cierre de 7D cuenta con **evidencia previamente observada** en la
[ejecución 37218682263](https://github.com/benjvm/certichain/actions/runs/37218682263),
database y flutter completed/success. La consulta de sus jobs durante 8A confirmó
esos estados; no se ejecutó un nuevo CI ni se atribuye esa ejecución a 8A.
Las capacidades ya entregadas siguen válidas hasta 60 s;
la limpieza sigue siendo operativa explícita y requiere volver a conciliar subidas
tardías. No se añade limitación de tasa distribuida. QR/verificación pública,
blockchain y un nuevo flujo de revocación permanecen fuera de alcance.

## Incremento 8A — backend público del registro

Completado localmente el 04/10/2026 desde HEAD
`dcda200fa9afb5b5e24f2733b91a1bcc8176da32`, repositorio inicialmente limpio.
Se añadieron archivos y una migración; no se retrocedió el checkout ni se
modificaron migraciones compartidas. No hay cambios Flutter ni dependencias nuevas.

Entorno: Windows, Node 22.14.0, Supabase CLI 2.117.0, Deno 2.2.12,
PostgreSQL 17.6 local. Se crearon stacks independientes fuera del repositorio,
con project_id propio y puertos 55320–55329/9083; el habitual certichain siguió
activo en 54321/54322. Start y db reset reconstruyeron nueve migraciones. El
preparador final se ejecutó con -Start y validó reconstrucción/HTTP en otro
proyecto aislado nuevo. No se reseteó ni se aplicó 8A al entorno habitual.

| Comprobación ejecutada | Resultado real local |
|---|---|
| Reconstrucción / reset | PASS, nueve migraciones; seed.sql ausente, sin datos inventados |
| Suite SQL completa | **557 PASS**, conserva 500 y añade 57 de 8A |
| Deno fmt --check / lint / check frozen / test | PASS, **44 tests** (28 anteriores + 16 nuevos); tres entrypoints comprobados |
| public_verification_http.mjs | **296 aserciones PASS**, petición real sin sesión, Authorization ni apikey |
| issuance_http.mjs | **368 aserciones PASS**, Auth/Edge/Storage/recuperación anteriores |
| issuance_hardening.mjs | **135 aserciones PASS**, 14 publicaciones, corpus/carga 8 457 193 bytes, 16,96 s |
| private_storage.mjs | PASS, denegación anon/authenticated, MIME/límite, objeto y bytes conservados |
| certificate_pdf_http.mjs | **92 aserciones PASS**, autorización, firmas independientes y caducidad real de capacidad |
| institution_concurrency.mjs | **14 carreras PASS**, ocho institucionales y seis de emisión |
| Preservación migraciones 5 / 7A / 8A | PASS, los tres scripts; históricos/códigos/datos privados/Storage intactos |
| Lint public,certichain_private | PASS con fail-on warning, sin incidencias propias |
| Reconciliador local | PASS, cola vacía; 0 cleaned/protected/busy/pending |
| Preparador descartable | PASS, -Start real, código de funciones copiado sin cambiar bytes, sin estado CLI privado |
| node --check / git diff --check | PASS |

La suite nueva SQL ejerce grants y roles reales, SELECT técnico, ausencia mínima,
históricos/finalizing/hash incoherente, prioridad y frontera exacta de expiración
con microsegundos. Los vínculos ilegales se rechazan por las guardas existentes;
no se desactivan para crear casos de revocación/caducidad. Los fixtures de fechas
pasadas se insertan en secuencia finalizing → completed con fechas coherentes.
La clasificación usa el mismo helper privado que prueba la igualdad exacta.

El harness HTTP reutiliza el fixture de 7D, pero consulta el endpoint con fetch
sin cabeceras de autenticación. Prueba campo cerrado, UUID/caso/MIME/JSON/tipos,
stream excesivo sin Content-Length, OPTIONS/métodos/CORS/no-store, metadatos
privados ausentes, fechas y todos los resultados. PostgreSQL retiene el lock
de la fila del limitador y se observan **cuatro backends esperando realmente**
antes de liberar: uno obtiene el último cupo y tres 429. Se comprueban 60
concesiones exactas, agotamiento, Retry-After, renovación moviendo el reloj del
fixture y ausencia de evasión por query/cabeceras/cuerpo. No hay pausas largas
para probar ventanas. El test de TTL PDF anterior conserva su espera real.

Revocar temporalmente EXECUTE técnico del lookup y retirar la fila del presupuesto
producen 503 HTTP mínimo; no not_found ni permiso ilimitado. Grants/fila se restauran
en finally. Estos cambios de fixture requieren CERTICHAIN_TEST_DISPOSABLE=1 y API
loopback comprobada; no existen hooks de fallos nuevos en el endpoint público.
Se comparan la fila completa del certificado/legado y bytes privados antes/después;
el teardown existente comprueba ausencia de recursos propios. Los harness serve
son secuenciales. Una primera ejecución de preservación 7A se solapó por error
con emisión y abortó por deadlock; se repitieron los tres scripts secuencialmente
con éxito. Ese intento no se cuenta como PASS.

Durante revisión se detectó que `$` en RegExp JavaScript puede aceptar un salto
final; se añadió longitud exacta 36 tanto en contrato como SQL y regresiones
unitarias/SQL/HTTP. Un cuerpo upstream excesivo se trata como fallo técnico 503,
no como 413 del solicitante. Las últimas cifras corresponden a estas correcciones.

Reproducción y comandos completos en
[PUBLIC_VERIFICATION.md](PUBLIC_VERIFICATION.md). Para calidad de funciones desde
la raíz original, usar los comandos exactos de `.github/workflows/database.yml`:
incluyen el nuevo entrypoint y harness y conservan versiones/SHA fijados,
lock frozen, SQL, emisión, Storage, PDF, preservación, concurrencia y todos los
checks Flutter anteriores. El harness público se añade como paso secuencial en
el stack efímero del runner con la marca descartable explícita. No usa secretos
remotos ni desactiva JWT de otros endpoints.

No se volvió a ejecutar Flutter/E2E Web/nativos en esta entrega porque sus
archivos no cambian; sus checks CI se conservan y la evidencia 7D previamente
observada está documentada arriba. No se atribuye esa ejecución a 8A. No se
ejecutó push, merge, despliegue ni nuevo GitHub Actions. 8B–8D quedan pendientes.
Presupuesto global solo para demo local; verificación normal comprueba evidencia
persistida, no bytes actuales de Storage, identidad del presentador ni blockchain.

## Incremento 8B — interfaz pública, enlaces Web y QR local

Completado localmente el 04/10/2026 sobre el checkout actual que partía limpio de
`e3f42255c459e57e73f16b9677722add7590227e`. Se conserva la evidencia 8A anterior.
El reparto autorizado sitúa pantalla/enlace/QR en 8B, escáner y comparación de
copia en 8C, pruebas integrales/endurecimiento completo en 8D. Estos dos últimos
incrementos permanecen pendientes. No hay nuevas migraciones, cambios del
contrato v1, permisos o límite global 60/60 s. El PDF publicado no se transforma.

Entorno ejecutado: Windows, Flutter 3.47.4/Dart 3.13.3, Node 22.14.0,
Supabase CLI 2.117.0, Deno 2.2.12 y Chrome headless real. Backend en un proyecto
descartable distinto, puerto API 55321, nueve migraciones de fuentes locales.
El stack habitual certichain sigue en 54321; no se reseteó ni se modificaron sus
datos, reloj o presupuesto. Los harness de funciones se ejecutaron secuencialmente.

| Comprobación ejecutada | Resultado local |
|---|---|
| dart format / flutter analyze | PASS, sin incidencias |
| flutter test completo | **157 PASS**, un test opt-in anterior omitido; conserva regresiones Auth, wallet, emisión y PDF |
| Diseño con Inter local | PASS en 320×568, 360×800, 390×844 y 1280×900, escala ×1/×2, scroll y acciones alcanzables |
| QR renderizado, decoder independiente jsqr | PASS, recupera exactamente la URL esperada |
| Harness público Web + adaptadores de producción | **52 aserciones PASS**, 14 POST públicos observados en Chrome real |
| Regresión Web 7D sobre el stack descartable | **69 aserciones Flutter y 29 del host PASS**, Auth/Edge/PostgreSQL/Storage/PDF reales |
| Probe Web anterior de PDF | PASS, selector/cancelación/8 MiB/bytes/Blob/revocación URL, sin navegación |
| Build Web release de main.dart | PASS, sin depender de CDN para recursos Web |
| SQL completo | **557 PASS** |
| Funciones fmt/lint/check frozen/test | PASS, **44 tests**; los tres entrypoints |
| Regresión HTTP pública 8A | **296 aserciones PASS**, también repetida después de ajustar el helper de preparación |
| Lint de public y certichain_private | PASS, sin incidencias |
| Preparador final con -Start en Windows PowerShell 5.1 | PASS, nuevo proyecto; fuentes de funciones/migraciones idénticas, cierre sin backup |

Las pruebas nuevas unitarias usan fakes/MockClient deliberadamente para fechas,
contratos malformados, tamaño, timeout/red/429/503, ausencia de cabeceras privadas,
UUID y base Web; controlador y widgets cubren doble envío, edición, respuestas
fuera de orden, dispose, reintento manual, espera Retry-After, copia semántica,
histórico sin enlace y cambio de cuenta/token/caducidad. El adaptador autenticado
se ejerce con SupabaseClient real y transporte sustituido, verificando proyección
y ambos filtros. Estas pruebas no se presentan como HTTP integral.

El harness nuevo sí monta CertiChainApp y los repositorios de producción con
Auth/Edge/PostgreSQL/Storage reales. Publica un PDF sintético con el endpoint 7B,
consulta como anónimo, prueba ausencia, expiración histórica válida, emisor
suspendido y revocación mediante fixtures SQL autorizados y con constraints.
Un EXECUTE retirado/restaurado en finally provoca 503; la sesión privada sigue
vigente. No hay endpoint público simulado ni cambio de reloj/contador en este
harness. Se comparan los bytes privados originales al terminar.

Chrome captura las cabeceras de red efectivas: cada POST contiene exclusivamente
credential_code, sin Authorization, apikey ni Cookie. El titular obtiene un
código diferente de certificates.id, muestra QR, copia realmente al clipboard y
abre el enlace en otro BrowserContext sin sesión. Un decoder independiente
recupera el enlace del QR pintado por Flutter. Se comprueban entrada directa,
recarga, atrás/adelante, restauración/Auth existente, rebuild sin HTTP adicional,
logout sin recuperar detalle privado, histórico sin QR y exclusión de otro titular.
Las capturas public-390.png/share-390.png fueron inspeccionadas visualmente.

Además sirve un build debug de **main.dart real**, sin SUPABASE_PUBLISHABLE_KEY,
en /production/; la pantalla pública funciona con SUPABASE_URL válido y conserva
código/resultado tras recarga. Se comprueba semántica del resultado y un único
POST por arranque/recarga. Esta prueba se distingue del entrypoint instrumentado.

El runner `flutter test --platform chrome` se intentó en Windows y se interrumpió
al no completar la inicialización de suites; **no se declara PASS**. Se mantiene
en CI Linux, ahora también para el contrato/adaptador público. La limitación de
CanvasKit del SDK Windows ya está registrada en 7C. Los builds/harness Chrome
anteriores sí completaron sus comprobaciones, sin modificar el SDK. Android,
iOS y lectores de pantalla humanos no se ejecutaron en 8B ni se declaran PASS.

El helper compartido espera ahora que issue-certificate responda 400 a un cuerpo
vacío autenticado antes de iniciar fixtures: calienta imports sin reservar,
publicar o consultar el endpoint público. Corrige fallos de arranque frío
observados en los intentos iniciales; no aumenta los timeouts de producción.
El preparador transmite el resolver de CLI por stdin para conservar comillas
con Windows PowerShell 5.1. Solo cambian herramientas de pruebas, no backend.

### Reproducción de las pruebas nuevas

Desde mobile, las pruebas unitarias y el decoder:

```powershell
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
$env:CERTICHAIN_QR_CAPTURE='build/phase8b-qr.png'
flutter test
Push-Location tool
npm ci --ignore-scripts
node verify_qr.mjs ../build/phase8b-qr.png http://localhost:7357/#/verify/e42f105a-a36b-40de-8326-47da5749eae3
Pop-Location
flutter build web --no-web-resources-cdn
```

Preparar/arrancar un **nuevo** stack con prepare_disposable_local.ps1 según
PUBLIC_VERIFICATION.md. No usar el habitual para los siguientes fixtures. Desde
mobile, con el path devuelto por el preparador en la variable de entorno:

```powershell
$env:CERTICHAIN_TEST_DISPOSABLE='1'
$env:CERTICHAIN_TEST_BACKEND_ROOT='C:/ruta/al/stack-descartable'
flutter build web --no-web-resources-cdn --target=tool/public_verification_browser.dart --output=build/public-verification-e2e
flutter build web --debug --no-web-resources-cdn --base-href=/production/ --dart-define=SUPABASE_URL=http://127.0.0.1:55321 --dart-define=PUBLIC_VERIFICATION_BASE_URL=http://127.0.0.1:7357/production/ --output=build/public-verification-main
node tool/public_verification_browser.mjs
```

Requiere npm ci anterior y Chrome instalado (CHROME_EXECUTABLE opcional).
El runner usa puerto fijo 7357, sirve solo loopback, levanta/termina functions
serve y elimina su perfil Chrome/fixtures propios. El stack se detiene con
`supabase stop --no-backup --workdir C:/ruta/al/stack-descartable`; no elimina el
checkout del usuario. En CI el stack efímero original usa 54321: el workflow
conserva todas las comprobaciones previas y configura ese puerto en el build de
main. No se ejecutó un GitHub Actions nuevo, push, merge o despliegue remoto.

Para uso manual con una publicación propia, comandos de Chrome y pasos en
[PUBLIC_VERIFICATION.md](PUBLIC_VERIFICATION.md) y README. La clave local es
publishable/anon, nunca service_role. localhost solo sirve en el mismo equipo;
en esta evidencia histórica de 8B no se entregaban enlaces móviles nativos, escáner ni comparación de archivos; la evidencia 8C figura debajo.


## Incremento 8C y reparación del harness 8B — 05/10/2026

Estado inicial Git limpio, HEAD/main remoto 344b1a2c9ad80f79f8ef1e8ed3d0d74a9d5fd068,
sin commits posteriores relevantes en la referencia remota inspeccionada. Trabajo
solo local, sin push, merge o despliegue. Se leyeron contratos/arquitectura/seguridad
y ADR-0011/0012 antes de cambios. ADR-0013 conserva verify-certificate v1 y añade
comparación candidata independiente; 8D permanece pendiente.

### Bloqueo previo y evidencia del diagnóstico

El usuario informó la ejecución GitHub Actions 37234444550: primero timeout de
Chrome 7D y después Browser expression failed en ready tras reload del anónimo.
El harness descartaba exceptionDetails, consultaba DOM/marker inmediatamente al
acuse de Page.reload y no comprobaba salida/error de Chrome durante el arranque.
Sin acceso a detalles de aquella excepción no se confirma su causa histórica.
El harness anterior de 8B pasó localmente con diagnóstico añadido (52/14); el
fallo original no se reprodujo. No se presenta una hipótesis como diagnóstico.

browser_harness.mjs compartido distingue arranque Chrome, compromiso de documento,
contexto/DOM y marcadores de arranque Flutter. Espera cambio de loader en reload,
crea isolated world en el frame actual y espera documentElement/readyState;
solo reintenta errores CDP -32000 identificados de contexto destruido/no encontrado
o navegación. Las excepciones JavaScript reales fallan sin retry. Reporta tipo,
código, línea/columna/contexto sanitizados, sin mensaje/valor/expresión privada.
Chrome conserva solo categorías allowlist acotadas de stderr, detecta spawn
error/salida temprana y verifica DevTools/socket con deadlines. Sockets pendientes
se rechazan al cerrar; parada de grupo Unix/árbol Windows y espera antes de borrar
perfil propio. La prueba Linux detectó ENOTEMPTY por hijos Chrome aún activos y
se corrigió; repetición final salió 0. Se conservan todas las aserciones 7D/8B.

Otra carrera se reprodujo en el stack local: el probe podía responder desde un
runtime anterior mientras el nuevo functions serve lo sustituía, y la siguiente
emisión fallaba por reset/abort de conexión. local_issuance_fixture observa el
marcador de ESTE proceso antes de calentar y detecta error/salida, sin guardar
stdout sensible. 7D intercepta el file chooser antes de navegar para que Chrome
headless no cancele el selector real automáticamente. Estos son defectos locales
confirmados; no se atribuyen sin evidencia al error histórico de Actions.

### Resultados locales

Windows; Flutter 3.47.4/Dart 3.13.3, Node 22.14.0, Supabase CLI 2.117.0,
Deno 2.2.12, Chrome headless. Dos stacks descartables creados fuera del checkout,
puerto API 55321; el último reconstruido de las diez migraciones finales. El
habitual certichain/54321 no recibió reset ni migración 8C. Un primer intento de
7D apuntó por error al habitual y falló antes de navegar al detectar el puerto
no esperado por el build; los fixtures creados se limpiaron. Se corrigió el
binding del harness y las validaciones siguientes usaron el descartable.

| Comprobación ejecutada | Resultado |
|---|---|
| dart format / flutter analyze | PASS, sin incidencias |
| flutter test completo | **182 PASS**, un opt-in anterior omitido; 25 nuevos casos 8C |
| SQL sobre reconstrucción final | **611 PASS**, 54 nuevos; roles RPC, snapshot privado, estados/ausencia uniforme y permisos |
| Cuatro preservaciones transaccionales + lint public/certichain_private | PASS, datos/códigos/metadata Storage preservados, sin warnings de esquema |
| Deno fmt/lint/check frozen cuatro entrypoints/test | PASS, **65 tests** (44 anteriores +21 comparación) |
| HTTP verify-certificate 8A | **296 aserciones PASS**, endpoint real y límite atómico |
| HTTP compare-certificate-hash | **255 aserciones PASS**, match/mismatch/estados/fallos, cuerpo cerrado y límite compartido con concurrencia |
| HTTP emisión 7B y hardening | **368 y 135 aserciones PASS**, Auth/Edge/Storage, recuperación y PDF |
| Storage privado | PASS, denegaciones anon/authenticated y bytes conservados |
| HTTP PDF autorizado 7C | **92 aserciones PASS**, incluye vencimiento real de capacidad |
| Concurrencia de owner y autorización de emisión | **14 escenarios PASS** |
| Regresión Web 7D | **69 Flutter +29 host PASS**, producción Auth/Edge/Storage/BD/PDF |
| Web público 8B+8C | **74 host PASS**, 16 verify +4 compare POST reales, cámara emulada/decoder/selector reales; scanner con/sin sesión |
| Node smoke CDP fake | **3 PASS**, sincronización y excepciones sanitizadas sin retry real |
| Smoke CDP Chrome Windows y Ubuntu 24.04 | **45 aserciones PASS en cada plataforma**, 20 reload anónimos, DOM/contextos, fallos de lanzamiento y limpieza |
| Build Web release main / instrumentado / main debug sin clave privada | PASS, recursos Web locales |
| APK Android debug | PASS compilación; sin ejecución de cámara en dispositivo |

Ubuntu se ejecutó en Docker, base 24.04 fijada por digest, Node 22.14.0 verificado
por SHA-256 y Chrome 154.0.8037.97. Es smoke real del harness con DOM sintético,
NO un E2E Flutter/backend completo Linux. Docker --rm y perfiles temporales propios.
Un futuro Actions deberá confirmar los recorridos completos Linux conservados.
No se ha observado una nueva ejecución de GitHub Actions de estos cambios.

### Alcance de fakes, cámara y privacidad

phase8c_test usa FakeCamera, picker/repository fakes y MockClient para permisos
negados, ausencia/cámara ocupada, cancelación, detecciones repetidas, permiso
pendiente/dispose, códigos ambiguos/excesivos y URL de confianza. Vectores SHA-256
abc y binarios exactos, cambio de byte y límite 8 MiB; stream nativo acotado,
cancelación entre bloques, reemplazo/código/respuestas fuera de orden y cooldown
compartido incluso durante selección y salida/reapertura. Adaptador de cámara real con controller del plugin sustituido: errores de stream
se traducen sin detalle privado y el stream propio cierra incluso si falla la
liberación nativa. DTO/HTTP cerrado,
exceso/timeout/errores y estado/integridad separados. Widget 320×568/texto ×2
con permiso denegado y alternativa manual accesible; match no oculta revoked.
La captura comparison-revoked-390.png se inspeccionó visualmente.

El E2E público conserva las aserciones 8B: publicación real, QR pintado y decoder
independiente jsqr, titular/clipboard, anónimo, histórico/expirado/emisor/revocado,
503, Auth/historial/recarga y main real sin configuración privada. Añade video Y4M
generado a partir del QR de Flutter, Chrome --use-file-for-fake-video-capture, permisos CDP denied/granted,
getUserMedia y MobileScanner/ZXing locales reales. Comprueba permiso realmente
denegado y reintento explícito en el mismo panel, cámara detenida y confirmación
única; no sustituye el decoder por un fake. File chooser CDP selecciona
el PDF emitido en el adaptador de producción, misma copia renombrada y copia con
un byte cambiado: match, match, integrity_mismatch. Repite match tras revocación
y mantiene revoked. Cancelación, vacío y 8 MiB+1 no envían comparación.

Un proxy loopback pasa ambos endpoints al Edge real. Se precarga Cookie en ese
MISMO origen y se comprueba ausencia efectiva de Cookie/Authorization/apikey tanto
por CDP como servidor; body contiene solo credential_code/document_sha256 y
estos digests se contrastan con bytes exactos. No se almacena ni sube la copia.
Comprueba petición decoder local y falla si la app intenta recursos remotos/CDN.
Cámara emulada, sin cámara física Android/iOS/Web ni interacción humana con el
diálogo OS. iOS no compilado desde Windows; Safari/Firefox/dispositivos físicos
y lectores de pantalla humanos pendientes. No se promete universalidad por el
soporte anunciado del paquete. flutter test --platform chrome conserva la
limitación Windows documentada en 8B; CI Linux mantiene esa prueba sin omitirla.

### Comandos reproducibles de 8C

Desde raíz, preparar stack NUEVO según PUBLIC_VERIFICATION.md. SUPABASE_CLI puede
apuntar al binario CLI 2.117.0 si no está en PATH. Los comandos siguientes exigen
la ruta devuelta, y los HTTP/fixtures se ejecutan SECUENCIALMENTE:

```powershell
$taskStack = & ./supabase/tests/prepare_disposable_local.ps1 -Start
$env:CERTICHAIN_TEST_DISPOSABLE='1'
$env:CERTICHAIN_TEST_BACKEND_ROOT=$taskStack
supabase test db --local --workdir $taskStack
$taskProject=(Select-String -Path (Join-Path $taskStack 'supabase/config.toml') -Pattern '^project_id').Line.Split('"')[1]
./supabase/tests/verify_hash_comparison_migration.ps1 -DatabaseContainer ('supabase_db_'+$taskProject)
supabase db lint --local --workdir $taskStack --schema public,certichain_private --level warning --fail-on warning
Push-Location -LiteralPath $taskStack
node supabase/tests/public_verification_http.mjs
node supabase/tests/hash_comparison_http.mjs
node supabase/tests/issuance_http.mjs
node supabase/tests/issuance_hardening.mjs
node supabase/tests/private_storage.mjs
node supabase/tests/certificate_pdf_http.mjs
node supabase/tests/institution_concurrency.mjs
Pop-Location
npx --yes deno@2.2.12 fmt --check supabase/functions
npx --yes deno@2.2.12 lint supabase/functions
npx --yes deno@2.2.12 check --frozen --config supabase/functions/deno.json supabase/functions/issue-certificate/index.ts supabase/functions/certificate-pdf/index.ts supabase/functions/verify-certificate/index.ts supabase/functions/compare-certificate-hash/index.ts
npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions
node --test mobile/tool/browser_harness_test.mjs
node mobile/tool/browser_harness_smoke.mjs
Push-Location mobile
flutter pub get --enforce-lockfile
Push-Location tool
npm ci --ignore-scripts
node prepare_decoder.mjs
Pop-Location
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --no-web-resources-cdn --target=tool/secure_issuance_browser.dart --output=build/secure-issuance-e2e
node tool/secure_issuance_browser.mjs
flutter build web --no-web-resources-cdn --target=tool/public_verification_browser.dart --output=build/public-verification-e2e
flutter build web --debug --no-web-resources-cdn --base-href=/production/ --dart-define=SUPABASE_URL=http://127.0.0.1:55321 --dart-define=PUBLIC_VERIFICATION_BASE_URL=http://127.0.0.1:7357/production/ --output=build/public-verification-main
node tool/public_verification_browser.mjs
flutter build web --no-web-resources-cdn
flutter build apk --debug
Pop-Location
supabase stop --no-backup --workdir $taskStack
```

En CI el stack efímero usa 54321 y no requiere el backend root alternativo. El
workflow conserva SQL/Deno/HTTP anteriores, carreras y cuatro preservaciones,
Chrome platform tests/PDF adapters y 7D. Añade comparación HTTP y scanner/PDF real,
smoke CDP y preparación decoder, con el SDK/CLI fijados. No se reduce cobertura
para ocultar el fallo 8B. La publicación futura exige nueva migración y desplegar
verify-certificate + compare-certificate-hash (shared handler); comandos preparados
en PUBLIC_VERIFICATION.md, ninguno ejecutado remotamente.

Para smoke Linux aislado, desde raíz con Docker Desktop/Linux:

```powershell
docker build -f mobile/tool/harness-linux.Dockerfile -t certichain-cdp-linux-8c mobile/tool
docker run --rm --shm-size=256m certichain-cdp-linux-8c
```

Chrome se obtiene del canal estable oficial durante build; su versión puede
cambiar, por lo que la observada arriba es evidencia de esta ejecución. Node y
Ubuntu sí están fijados. No expone puertos ni requiere secretos/stack Supabase.

## Cierre local integral 8D (2026-10-05)

Base d31a2735b3c51a651f101da5b764612a45862cac, working tree 8D sin commit/push.
Actions 37350396753 intento 2 valida únicamente 8C. La evidencia anterior se
conserva como histórica; los resultados nuevos se detallan en
[PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md). No hay CI 8D observada ni despliegue.

Herramientas actuales: Node 24.14.0 obligatorio, npm engine-strict y lock congelado,
Flutter 3.47.4/Dart 3.13.3, Supabase CLI 2.117.0, Deno 2.2.12. CI y contenedor
harness usan ese Node compatible con ZXing 0.23.0; UMD/licencia/manifest no cambian.
`node mobile/tool/prepare_decoder.mjs --check` detecta drift sin sobrescribirlo.

`./supabase/tests/run_phase8d.ps1` crea, ejecuta release real y limpia un stack
nuevo; `-Full` añade SQL/HTTP/Deno/Flutter y harness instrumentados.
No correr suites con fixtures/budget concurrentemente. Los fixtures requieren
identidad de stack propio además del flag disposable; CI admite su runner fresco.
Nunca manipular contadores/guards del stack habitual del desarrollador.

Readiness espera el marcador del proceso serve actual, después probes acotados
Auth/PostgREST/Storage y rechazo JWT Edge, sin mutaciones persistentes. Salida o
deadline falla la etapa con diagnóstico sanitizado. Las conexiones del operador
son independientes; crear usuario/institución/certificado no tiene reintento ciego.
Teardown encuentra también filas propias con respuesta perdida. Tests controlados
reproducen old-ready y errores/señales/salida temprana. Esto no confirma la causa
histórica UND_ERR_SOCKET del intento 1.

El E2E nuevo construye lib/main.dart release con configuración completa y HTTPS;
selecciona/copia/descarga mediante UI/semántica y adaptadores reales. Incluye mismo
origen con cookie, QR renderizado, cámara Y4M y ZXing local, 8 MiB, checked_at previo,
dos repeticiones de carreras, errores acotados y renovación temporal real de 60 s.
No reutiliza 7D/8B+8C como evidencia de main.dart. JSON/capturas solo públicas
sintéticas en build/phase8d-evidence; TLS, secretos y configuración temporal no se
suben como artefactos. CI conserva las suites y añade readiness, drift, release
HTTPS, compilación Android y artefactos sanitizados; CI 8D todavía no observada.

Windows Chrome platform test mantiene la limitación documentada; no es PASS.
La prueba Linux CI permanece obligatoria. Probes Android usan un emulador exclusivo,
rechazan reemplazar un paquete ya instalado y limpian archivos/instalación propios.
Cámara física y recorrido nativo completo siguen pendientes.

## Revalidación del cierre 8D (10/10/2026)

Checkout inicial main limpio, local/remoto **6235486** («8D stage»). La CI
**37373509169 intento 1** falló antes de ejecutar: ambos jobs sin runner/pasos,
anotación de adquisición hosted fallida y error interno GitHub confirmado por el
operador. **No es fallo de tests ni CI validada.** 37350396753 intento 2 success
se reconsultó: SHA d31a273, exclusivamente 8C. Detalle y acciones en
[PHASE8_OPERATOR_CHECKLIST.md](PHASE8_OPERATOR_CHECKLIST.md).

Se ejecutaron desde raíz en PowerShell 7.6.5 **run_phase8d.ps1 -Full (exit 0)**
y **run_phase8d.ps1 (exit 0)**, cada uno con stack nuevo y finally. 611 SQL,
68 Deno, 198 Flutter +1 omitido; HTTP 366/135/90/296/255 y suites Storage,
concurrencia/preservación PASS. Builds y recorridos complementarios 7D/8B+8C/PDF
PASS; main.dart release Chrome 155: 127 aserciones +141 checks de artefactos.
Resultados/tiempos, Android, fallos y omisiones en
[PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md); no reutilizar los números históricos.

Correcciones locales solo de herramientas: SHA/working_tree_dirty/evaluated_at
reales en evidencia (antes base_commit constante), ruta PNG nativa bajo
Push-Location y KO de consola adb con exit 0. 8 tests Node CDP/readiness/metadatos
y 7 regresiones PowerShell PASS, incluidas las añadidas después de arrancar Full
y ejecutadas aparte. CI conserva suites y añade la regresión nativa con shell
pwsh, sin quitar checks, cambiar pins ni continue-on-error. Cambios nuevos
pendientes de publicación/CI del SHA exacto por el operador.

El smoke Linux Docker se reconstruyó: 45 PASS, Ubuntu 24.04, Node 24.14.0,
Chrome 154.0.8037.97; Windows smoke 45 PASS. No es recorrido completo Linux.
Android main debug/release compilan; probe PDF y primer probe cámara/permisos/
lifecycle PASS. QR nativo sin confirmación, intentos con deadlines y datos
insuficientes para atribuir fallo al producto. No recorrido Android completo,
cámaras físicas, Firefox/Safari/iOS ni revisión humana. APK main debug/release:
1.812 comprobaciones de ausencia de valores técnicos, no emitidos.
Edge 155 release: primer intento FAIL esperando confirmación QR; repetición
acotada sin emulador activo **127 +141 PASS**, exit 0. Causa del primer fallo no
confirmada; failure.json conservado separado, sin ocultarlo con retry de POST
ni aumentar deadlines. Guiones ejecutados en Windows; no CI nueva observada.
Dictamen vigente: **Diseño 9A posible con aceptación 8D pendiente**.
Formato Deno ampliado del workflow: 43 archivos PASS; regeneración assets y
git diff de migraciones/lockfiles/assets sin cambios. La causa histórica
UND_ERR_SOCKET sigue sin confirmar.

Una comprobación auxiliar de parseo YAML con Python no se pudo ejecutar por
ausencia de PyYAML (ModuleNotFoundError); no se instaló otra dependencia. El
fragmento añadido se revisó manualmente, las fuentes PowerShell se parsearon y
sus siete regresiones pasan; la validación Linux/CI del workflow modificado queda
pendiente del operador. La limpieza final de logs/PID e imagen de smoke fue
rechazada automáticamente: recursos/rutas en PHASE8_OPERATOR_CHECKLIST.md.
