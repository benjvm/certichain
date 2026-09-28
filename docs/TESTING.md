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

## CI

En cada pull request:

- formato y análisis de Dart;
- unit/widget tests de Flutter;
- recreación local de base y pruebas SQL/RLS;
- formato, build y tests de Foundry;
- escaneo de secretos y dependencias.

Las pruebas que requieren credenciales externas se separan y nunca bloquean el desarrollo local sin una alternativa determinista.

## Definición de terminado

Un cambio incluye pruebas del comportamiento nuevo, mantiene los límites de autorización, actualiza fixtures/seeds si corresponde y deja documentado cualquier riesgo o comprobación manual pendiente.
