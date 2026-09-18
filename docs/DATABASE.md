# Modelo de datos y migraciones

La primera migración, `initial_schema`, define cuatro tablas: `profiles`,
`institutions`, `institution_members` y `certificates`. Los campos y tablas
adicionales descritos más abajo son propuestas para incrementos futuros, no
parte del esquema inicial. La primera migración habilitó RLS; la segunda,
`rls_policies`, define las políticas para `authenticated`. `anon` no tiene
acceso directo a ninguna de las cuatro tablas.
Los certificados conservan referencias obligatorias; por ello se impide borrar
un perfil o institución que tenga certificados asociados. Esta decisión también
puede impedir borrar un usuario de `auth.users`, porque su perfil se eliminaría
en cascada. Una futura política de eliminación o anonimización debe resolver
explícitamente ese caso sin perder el historial.

## Fuente de verdad

El esquema se define exclusivamente en `supabase/migrations/`. El panel visual sirve para inspección, nunca para realizar cambios no versionados.

Crear una migración:

```bash
supabase migration new create_initial_schema
```

Aplicar localmente:

```bash
supabase start
supabase db reset
```

El nombre real llevará timestamp, por ejemplo `20260918190000_create_initial_schema.sql`. Una migración compartida no se reescribe; la corrección se hace en una migración posterior.

## Modelo inicial propuesto

### `profiles`

| Columna | Tipo | Regla |
|---|---|---|
| id | uuid | PK y FK a `auth.users(id)` |
| full_name | text | obligatorio |
| avatar_path | text | opcional |
| created_at | timestamptz | default `now()` |
| updated_at | timestamptz | actualizado por trigger |

El correo y la contraseña no se duplican aquí.

### `institutions`

| Columna | Tipo | Regla |
|---|---|---|
| id | uuid | PK, default UUID aleatorio |
| name | text | obligatorio |
| slug | text | unique |
| website | text | opcional |
| logo_path | text | opcional |
| status | text | check: pending/approved/suspended/rejected |
| created_at | timestamptz | default `now()` |
| updated_at | timestamptz | default `now()` |

### `institution_members`

| Columna | Tipo | Regla |
|---|---|---|
| institution_id | uuid | FK, parte de PK compuesta |
| user_id | uuid | FK a `profiles`, parte de PK |
| role | text | check: owner/issuer/viewer |
| created_at | timestamptz | default `now()` |

La pertenencia sustituye un único `role` global y permite que una persona participe en varias instituciones.

### `certificate_types`

| Columna | Tipo | Regla |
|---|---|---|
| id | uuid | PK |
| institution_id | uuid | FK |
| name | text | obligatorio |
| description | text | opcional |
| active | boolean | default true |

Unique recomendado: `(institution_id, lower(name))` mediante índice de expresión.

### `certificates`

| Columna | Tipo | Regla |
|---|---|---|
| id | uuid | PK interno |
| public_id | uuid | unique, usado por QR |
| institution_id | uuid | FK obligatoria |
| recipient_id | uuid | FK a `profiles` |
| certificate_type_id | uuid | FK opcional |
| title | text | obligatorio |
| description | text | opcional |
| issued_at | timestamptz | obligatorio |
| expires_at | timestamptz | opcional, posterior a emisión |
| document_path | text | obligatorio y privado |
| document_sha256 | bytea | exactamente 32 bytes |
| status | text | anchoring/active/anchor_failed/revoking/revoked |
| idempotency_key | uuid | unique |
| created_by | uuid | FK a `profiles` |
| created_at | timestamptz | default `now()` |
| updated_at | timestamptz | default `now()` |

Los metadatos que deben quedar congelados después de emitir se validan mediante permisos y trigger. No se permite sustituir silenciosamente el PDF.

### `blockchain_records`

| Columna | Tipo | Regla |
|---|---|---|
| id | uuid | PK |
| certificate_id | uuid | FK |
| operation | text | issue/revoke |
| network | text | identificador de red |
| chain_id | bigint | obligatorio |
| contract_address | text | obligatorio |
| transaction_hash | text | unique |
| block_number | bigint | opcional hasta confirmar |
| payload_hash | bytea | 32 bytes |
| status | text | pending/confirmed/failed |
| error_code | text | opcional, sin secretos |
| created_at | timestamptz | default `now()` |
| confirmed_at | timestamptz | opcional |

### `verification_events`

| Columna | Tipo | Regla |
|---|---|---|
| id | bigint identity | PK |
| certificate_id | uuid | FK opcional para not_found seguro |
| result | text | conjunto cerrado de resultados |
| method | text | qr/code/file |
| request_fingerprint | text | opcional, seudonimizado y con retención |
| created_at | timestamptz | default `now()` |

Esta tabla es opcional para el primer incremento. No almacenar IP sin justificación y política de retención.

## Relaciones

```mermaid
erDiagram
    PROFILES ||--o{ INSTITUTION_MEMBERS : pertenece
    INSTITUTIONS ||--o{ INSTITUTION_MEMBERS : contiene
    INSTITUTIONS ||--o{ CERTIFICATE_TYPES : define
    INSTITUTIONS ||--o{ CERTIFICATES : emite
    PROFILES ||--o{ CERTIFICATES : recibe
    CERTIFICATES ||--o{ BLOCKCHAIN_RECORDS : registra
    CERTIFICATES ||--o{ VERIFICATION_EVENTS : verifica
```

## Índices mínimos

- `certificates(recipient_id, created_at desc)`.
- `certificates(institution_id, created_at desc)`.
- Unique `certificates(public_id)` e `idempotency_key`.
- `blockchain_records(certificate_id, operation, created_at desc)`.
- Unique `blockchain_records(chain_id, transaction_hash)`.
- `verification_events(certificate_id, created_at desc)` si se activa historial.

## RLS vigente

La identidad se obtiene de `auth.uid()`. El rol global `platform_admin` permite
las operaciones administrativas expresamente indicadas abajo. `holder` e
`institution_admin` no confieren por sí solos permisos sobre instituciones:
estos dependen de `institution_members.role` (`owner`, `admin` o `issuer`).

| Tabla | Lectura | Escritura desde `authenticated` |
|---|---|---|
| `profiles` | Perfil propio o cualquier perfil para `platform_admin` | Actualización propia sin cambiar `role`; `platform_admin` puede actualizar perfiles. Sin INSERT ni DELETE de cliente. |
| `institutions` | Miembros y `platform_admin` | INSERT/DELETE solo `platform_admin`; UPDATE `owner`, `admin` o `platform_admin`. Solo `platform_admin` cambia `verification_status`. |
| `institution_members` | Fila propia; todas las filas de la institución para `owner`/`admin`; todas para `platform_admin` | INSERT/UPDATE/DELETE solo `owner` de esa institución o `platform_admin`. |
| `certificates` | Titular, cualquier miembro de la institución emisora o `platform_admin` | INSERT por `owner`/`admin`/`issuer` de la institución con `issued_by = auth.uid()`, o por `platform_admin`. UPDATE por `owner`/`admin` solo para revocar, o por `platform_admin`. Sin DELETE de cliente. |

Las funciones `certichain_private.is_platform_admin`,
`is_institution_member` y `has_institution_role` consultan únicamente el estado
de autorización del usuario actual. Son `SECURITY DEFINER`, usan un
`search_path` vacío y evitan recursión RLS. El esquema no está expuesto por la
API; solo `authenticated` puede ejecutarlas. Los triggers de `profiles` e
`institutions` impiden cambiar roles globales o estados de verificación sin
ser `platform_admin`. El trigger de `certificates` limita a los administradores
institucionales a la transición `active → revoked`, conserva todos los demás
campos y fija `revoked_at` con la hora de la base de datos.

No hay acceso directo para `anon`; la verificación pública requiere una futura
interfaz restringida. Tampoco hay una política de INSERT para perfiles: su
aprovisionamiento inicial y la asignación del primer `platform_admin` requieren
un flujo confiable. La migración no garantiza que permanezca al menos un
`owner` por institución; se necesita una regla transaccional de negocio para
evitar borrar o degradar al último. La emisión directa autorizada por RLS no
valida aún el archivo ni su hash: antes de producción, ese flujo debe pasar por
el backend confiable descrito en `docs/ARCHITECTURE.md`.

## Seeds

`supabase/seed.sql` solo contendrá instituciones, perfiles y certificados ficticios para desarrollo. Debe ser determinista, repetible y no depender de información personal real.
