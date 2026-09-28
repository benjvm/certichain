# Administración institucional — Fase 6

## Decisión del MVP

El alta institucional es administrada: un `platform_admin` crea una institución
`pending` y asigna un primer `owner` a una identidad de Auth con perfil existente,
en una operación atómica. Las solicitudes de autoservicio y la interfaz Flutter
institucional quedan para otro incremento. Elegir «Institución» al registrarse
continúa creando únicamente un perfil `holder`.

No hay emisión ni revocación: ni siquiera una institución `verified` obtiene
INSERT/UPDATE en `certificates`. La fase 7 será emisión segura sin blockchain,
mediante backend, PDF privado, SHA-256 e idempotencia.

## Primer administrador y administradores adicionales

La operación `certichain_private.grant_platform_admin(target, confirm_target,
expected_admin_count)` exige una conexión SQL confiable como **`postgres`**.
Es `SECURITY INVOKER`, no está en un esquema expuesto y no concede EXECUTE a
PUBLIC, `anon`, `authenticated` ni `service_role`. La migración debe aplicarse
con el propietario confiable `postgres`, como las anteriores. No se utiliza
una cuenta Auth administrativa compartida ni una contraseña predefinida.

El procedimiento comprueba UUID explícito y confirmación idéntica, existencia
en Auth y perfiles, y número actual de administradores. Bloquea las escrituras
de perfiles durante la comprobación/cambio. Devuelve `platform_admin_assigned`
o `already_platform_admin`; afecta exactamente la PK confirmada. El contador
esperado es **0** para el primero. Si ya hay administradores, el operador debe
revisarlos y proporcionar el contador real para cada alta adicional. Un contador
desactualizado produce error y ningún cambio; no volver a intentar a ciegas.

Todas las promociones globales siguen requiriendo SQL confiable. Incluso un
`platform_admin` autenticado no puede cambiar `profiles.role` mediante UPDATE.
El perfil ordinario conserva la edición de nombre y sus políticas de lectura.
No existe RPC público de promoción ni sincronización de roles desde metadatos.
La retirada de administradores y el cierre de cuentas son tareas operativas
fuera de este flujo; requieren revisión individual y SQL confiable. No retirar
el último administrador operativo sin preparar un sucesor y acceso de recuperación.

### Procedimiento local reproducible

1. Reconstruir **solo un entorno local desechable**: `supabase start` y
   `supabase db reset --local`. Reset borra los datos locales.
2. Crear las identidades mediante el registro normal existente o Auth local,
   suministrando `full_name` válido. Elegir la identidad administrativa individual
   y comprobar visualmente su UUID en Auth y su perfil correspondiente. No guardar
   las identidades, correos o credenciales en archivos versionados.
3. En PowerShell, leer las entradas explícitamente. La confirmación debe proceder
   de una segunda comprobación de la identidad, no copiarse automáticamente.
   Consultar primero el contador con acceso confiable:

```powershell
docker exec supabase_db_certichain psql -X -U postgres -d postgres -c "SELECT current_database(), current_user; SELECT count(*) FROM public.profiles WHERE role = 'platform_admin';"
```

```powershell
$phase6Target = Read-Host 'UUID del usuario Auth revisado'
$phase6Confirm = Read-Host 'UUID confirmado tras comprobar Auth y profiles'
$phase6Count = Read-Host 'Número actual de platform_admin (0 para el primero)'
Get-Content -Raw supabase/admin/grant_platform_admin.sql |
    docker exec -i supabase_db_certichain psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 `
        -v "target_id=$phase6Target" -v "confirm_target_id=$phase6Confirm" -v "expected_admin_count=$phase6Count"
if ($LASTEXITCODE -ne 0) { throw 'Bootstrap rechazado; revisar antes de reintentar' }
Remove-Variable phase6Target,phase6Confirm,phase6Count
```

4. Comprobar `confirmed_target`, resultado y COMMIT. Confirmar que solo el perfil
   previsto cambió y que otra identidad sigue `holder`. Volver a iniciar sesión
   con esa cuenta individual para las operaciones API; su rol se consulta en BD.
5. Para un entorno remoto, usar el mismo archivo con `psql` y una conexión
   administrativa confiable elegida explícitamente. Obtener credenciales desde
   el gestor de secretos, nunca argumentos con contraseña, Flutter ni Git.
   Verificar proyecto/host/base/usuario antes de ejecutarlo. No se ha aplicado
   este procedimiento a ningún proyecto remoto durante la fase 6.

Las pruebas automatizadas no pueden comprobar que el operador haya seleccionado
a la persona/proyecto correctos ni que las credenciales administrativas estén
bajo su control. Esas revisiones, el cierre de la conexión privilegiada y la
verificación de una sesión HTTP firmada de la cuenta elegida son comprobaciones
manuales obligatorias del bootstrap. Los UUID de pruebas son sintéticos.

## Operaciones disponibles por la API de Supabase

Estos RPC de `public` tienen EXECUTE únicamente para `authenticated` y verifican
`auth.uid()` y las filas reales de autorización en servidor. Los UUID de owner
y miembro son **objetivos**, nunca la identidad del actor. Usar una sesión Auth
válida con `supabase.rpc(nombre, parámetros)`; no enviar `userId` administrativo,
rol global ni claims construidos en el cliente. Los ejemplos SQL siguientes
describen firmas; los parámetros deben proceder de entradas del operador.

| RPC | Actor permitido | Resultado |
|---|---|---|
| `create_institution(p_name, p_slug, p_owner, p_website = null)` | `platform_admin` | UUID; institución `pending` y `owner` atómicos |
| `update_institution_details(p_institution, p_name, p_slug, p_website = null)` | `platform_admin`, `owner`, `admin` de esa institución | Actualiza únicamente nombre, slug, web y hora de servidor |
| `set_institution_status(p_institution, p_status)` | `platform_admin` | Transición institucional validada |
| `set_institution_member(p_institution, p_member, p_role)` | `platform_admin`, `owner` de esa institución | Alta o cambio de rol en la pareja institución/usuario |
| `remove_institution_member(p_institution, p_member)` | `platform_admin`, `owner` de esa institución | Baja; si ya no existe, éxito idempotente |

`admin` institucional administra datos y lee miembros, pero no modifica
membresías ni se aprueba. `issuer` no administra. `institution_admin` global no
confiere permisos sin una fila válida de membresía. Una persona puede participar
en varias instituciones; las autorizaciones están limitadas a la seleccionada.
La administración de datos/miembros se permite en los cuatro estados para
resolver incidencias y preparar una nueva revisión. No concede emisión.

### Validación y errores

- Nombre: 2–160 caracteres, recortado en los extremos, sin controles ni solo
  espacios. Se rechazan entradas inválidas, no se normalizan silenciosamente.
- Slug: 3–80 caracteres ASCII en minúsculas; segmentos alfanuméricos separados
  por un guion. Único; nombre repetido permitido. Slug repetido devuelve `23505`
  con `Institution slug is already in use`; no es un upsert de instituciones.
- Web: opcional; `https://`, sin espacios/controles, hasta 2048 caracteres.
  Es un dato informativo; el servidor no descarga ni resuelve esa URL.
- Owner/miembro: Auth y perfil existentes; se bloquea su referencia durante la
  operación. No se abre la lectura de perfiles al propietario para enumerarlos;
  debe recibir un UUID confirmado por un canal operativo autorizado. Invitaciones
  y búsqueda de personas quedan pendientes.
- `42501`: operación no autorizada. Una institución inaccesible/no existente
  devuelve el mismo error de administración a un gestor sin acceso.
- `22023`: entrada/transición inválida o identidad objetivo inexistente para
  un gestor autorizado. Errores de validación/duplicados son fijos, sin nombres,
  correos, valores de constraint ni detalles internos.
- `23514`: `Institution must retain an owner`. Añadir primero otro propietario.
- `40001` o `40P01`: transacción abortada por concurrencia/orden de bloqueos;
  reintentar la operación completa revalidando permisos y estado. Nunca anunciar
  éxito antes de COMMIT. Estos códigos técnicos requieren traducción en la futura UI.

### Estados y reintentos

```text
pending → verified | rejected
verified → suspended
rejected | suspended → pending → nueva decisión
```

Repetir el estado actual es idempotente. Solo el administrador de plataforma
puede hacer cualquiera de estas operaciones; no se reactiva directamente una
institución suspendida. No se permite la eliminación institucional, ni siquiera
mediante DELETE ordinario confiable: se conserva institución, miembros e
historial. Una futura eliminación/anonimización necesitará otra decisión y
migración. TRUNCATE de instituciones/membresías también se deniega mediante
triggers de sentencia, incluso por cascada desde perfiles, para no saltarse las
guardas de fila. Las FK de certificados históricos siguen restringiendo bajas.

## Propietarios y concurrencia

Toda mutación de membresía escribe la fila padre antes de comprobar propietarios.
Los RPC bloquean esa fila **antes** de consultar permisos o miembros. Las
operaciones concurrentes sobre la misma institución se serializan. El trigger
también cubre SQL confiable, cambios de rol y cascadas `auth.users → profiles →
institution_members`; IDs, usuario, institución y fecha de membresía son inmutables.

La escritura del padre fuerza error de serialización si una transacción con
snapshot antiguo intenta continuar en REPEATABLE READ/SERIALIZABLE. Un mero
conteo sin bloqueo o un bloqueo consultivo sin escritura no cubriría ese caso.
Un trigger diferible comprueba además que una institución nueva tenga propietario
al finalizar la transacción. Si el segundo paso del alta falla, se revierte
también la institución; no hay instituciones huérfanas utilizables.

La migración se detiene si encuentra instituciones previas sin owner; no inventa
propietarios. Las constraints también requieren corregir datos institucionales
previos inválidos antes de aplicar. Revisar esos datos mediante acceso confiable.
Un operador con capacidad de alterar DDL puede deshabilitar controles: ese acceso
es parte del límite de confianza, nunca una identidad de API de usuario.

## Demostración local sin datos persistentes

Con tres usuarios Auth **ya existentes** y con perfiles (administrador objetivo,
owner y segundo miembro distintos), ejecutar desde la raíz:

```powershell
$phase6Admin = Read-Host 'UUID administrativo revisado'
$phase6Confirm = Read-Host 'UUID administrativo confirmado independientemente'
$phase6Count = Read-Host 'Número actual de platform_admin'
$phase6Owner = Read-Host 'UUID del propietario existente'
$phase6Member = Read-Host 'UUID de otro usuario existente'
Get-Content -Raw supabase/admin/demo_institution.sql |
    docker exec -i supabase_db_certichain psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 `
        -v "admin_id=$phase6Admin" -v "confirm_admin_id=$phase6Confirm" -v "expected_admin_count=$phase6Count" `
        -v "owner_id=$phase6Owner" -v "member_id=$phase6Member"
if ($LASTEXITCODE -ne 0) { throw 'Demostración fallida' }
Remove-Variable phase6Admin,phase6Confirm,phase6Count,phase6Owner,phase6Member
```

El archivo muestra bootstrap, alta `pending`/primer owner, aprobación `verified`,
alta de segundo miembro como `issuer`, cambio a `admin` por el owner y suspensión
por el administrador de plataforma. Usa `SET LOCAL ROLE authenticated` y claims
solo dentro de una conexión SQL confiable local, como el harness de pruebas;
no simula la firma/validación HTTP del JWT. **Siempre hace ROLLBACK**, incluido
el bootstrap, para repetirlo sin persistir instituciones de demostración.

Para administrar datos persistentes: usar el script de bootstrap con COMMIT y
los RPC mediante sesiones reales. No sustituir los claims del actor en una
sesión de usuario. Nunca cargar estos ejemplos como migración o seed.
