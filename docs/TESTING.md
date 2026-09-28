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
es una propuesta futura. Las pruebas de PDF/Storage, formato de hash,
idempotency key, endpoint público y backend de emisión/revocación se incorporarán
cuando esos flujos y constraints existan. No están cubiertos por esta fase.

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

No se ha observado CI de estos cambios, aplicado migración remota ni ejecutado
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
Ejecuta start, reset, las 429 pruebas, concurrencia, preservación histórica y
lint de public/certichain_private con `--fail-on warning`, y detiene el stack
en always(). No usa continue-on-error ni silencia fallos con `|| true`.

Referencias verificadas en repositorios oficiales con `git ls-remote`:
[checkout v4.3.1](https://github.com/actions/checkout/releases/tag/v4.3.1)
(`34e114876b0b11c390a56381ad16ebd13914f8d5`),
[setup-cli v1.7.3](https://github.com/supabase/setup-cli/releases/tag/v1.7.3)
(`1dedf2c611547ede7232d26866dd3c56ab903bbb`) y
[CLI v2.117.0](https://github.com/supabase/cli/releases/tag/v2.117.0).
Los dos uses se fijan al SHA completo. Contrato de comandos:
[testing y linting de Supabase](https://supabase.com/docs/guides/local-development/cli/testing-and-linting).

Se excluye extensions del lint porque contiene pgTAP externo, con los avisos
documentados en fase 5. Los dos esquemas propios se comprueban enteros: no se
filtran errores del proyecto ni se rebaja su umbral. Crear el workflow **no
demuestra CI pasada**; falta observar su ejecución tras publicar los cambios.

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
