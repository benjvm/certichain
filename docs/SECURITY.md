# Seguridad y privacidad

## Activos sensibles

- Documentos PDF y datos personales del estudiante.
- Sesiones y tokens de autenticación.
- Claves de servicio de Supabase y claves blockchain.
- Membresía y permisos de instituciones.
- Integridad entre PDF, base de datos y registro on-chain.

## Límites de confianza

Flutter y cualquier navegador son clientes no confiables. RLS y las operaciones de backend deben volver a comprobar identidad, pertenencia, estado de la institución, propiedad del certificado y validación de entrada.

## Autorización efectiva tras las Fases 5 y 6

`certificates` tiene únicamente una política SELECT para `authenticated`:
titular, miembro de la institución emisora o `platform_admin`. Los grants del
rol API se limitan a SELECT; no puede emitir, modificar, revocar, hacer upsert
ni borrar, aunque su rol de aplicación sea `owner`, `admin`, `issuer` o
`platform_admin` y la institución esté `verified`. No basta con aprobar la
institución para abrir INSERT: también son obligatorias las validaciones de
archivo, hash y operación del servidor.

`anon` no tiene grants sobre certificados y no obtiene filas de perfiles,
instituciones ni membresías por RLS. No hay verificación pública entregada.
Se han retirado TRUNCATE, REFERENCES y TRIGGER de las cuatro tablas para
PUBLIC, `anon` y `authenticated`; las lecturas autorizadas se conservan.
TRUNCATE exige control mediante grants porque
[PostgreSQL no le aplica RLS](https://www.postgresql.org/docs/17/ddl-rowsecurity.html).
No existe una función expuesta que proporcione una vía alternativa de emisión.

Emisión y revocación permanecen cerradas hasta construir el backend confiable
de [SECURE_ISSUANCE.md](SECURE_ISSUANCE.md). Validará sesión, rol/membresía,
`verification_status = 'verified'` en la emisión, destinatario, campos,
PDF real y límites, almacenamiento privado, SHA-256 de los bytes finales,
idempotencia y recuperación. El futuro backend es responsable de autorización
incluso si usa una identidad técnica con privilegios que omiten RLS.
La revocación deberá validar la institución emisora, una transición permitida
y sincronizarse con blockchain cuando exista ese flujo. No hay secretos de
servidor ni operaciones privilegiadas en Flutter.

### Administración institucional

La Fase 6 implementa alta administrada y aprobación mediante RPC transaccionales.
Solo `platform_admin` crea una institución `pending` con primer `owner` y decide
`verified`, `rejected`, `suspended` o reapertura `pending`. La identidad se deriva
de `auth.uid()` y el rol se consulta en `profiles`, nunca de metadatos o entrada
del cliente. `owner` y plataforma gestionan miembros; `admin` institucional solo
edita datos permitidos y lee miembros. `institution_admin` global no sustituye
una membresía. La administración se permite en los cuatro estados, sin emisión.

No queda DML directo de cliente sobre instituciones/membresías: se retiran tanto
grants como políticas de escritura. Los RPC tienen lista cerrada de campos,
autorización por institución, search_path vacío y EXECUTE solo de authenticated.
La búsqueda/listado de perfiles no se amplía para resolver miembros. Las
validaciones y errores de duplicado no incluyen datos ni detalles de constraints.

El último owner está protegido por escritura/bloqueo de la fila padre, guarda
de baja/degradación, identidad de membresía inmutable y constraint diferible de
alta. Incluye cascadas desde Auth/perfiles y operaciones concurrentes; snapshots
obsoletos abortan. DELETE institucional queda cerrado para preservar referencias
y certificados históricos. Los triggers de sentencia cierran TRUNCATE de
instituciones/membresías, incluso en cascada desde perfiles, además de los grants
API ya retirados. Antes de eliminar una cuenta que sea último owner,
asignar otro propietario mediante el flujo autorizado.

El primer `platform_admin` y los adicionales solo se asignan con SQL confiable
como `postgres`, UUID objetivo confirmado y contador esperado bajo bloqueo de
perfiles. La función privada es SECURITY INVOKER y no tiene EXECUTE API, tampoco
para service_role. Los UPDATE de rol por API se rechazan incluso desde plataforma;
los metadatos y la opción «Institución» del registro no conceden permisos.
No hay cuentas/credenciales compartidas, administradores en seeds ni secretos
de servidor en Flutter. El acceso capaz de alterar el esquema es confiable y
debe controlarse operativamente. Procedimiento y revisiones manuales:
[INSTITUTION_ADMINISTRATION.md](INSTITUTION_ADMINISTRATION.md).

## Amenazas principales y controles

| Amenaza | Control mínimo |
|---|---|
| Usuario emite sin permiso | RLS denegada y emisión privilegiada con comprobación servidor |
| Acceso a PDF ajeno | Bucket privado, ruta no predecible y URL firmada corta |
| Cambio de metadatos o PDF | Inmutabilidad tras emisión, SHA-256 y registro on-chain |
| Clave blockchain extraída | Clave solo en backend/secret manager, nunca en app |
| Abuso de endpoint público | Rate limit, respuesta uniforme y monitorización sin PII |
| Archivo malicioso | Límite de tamaño, MIME real, PDF válido y análisis cuando proceda |
| Doble emisión por reintento | Clave de idempotencia y constraint unique |
| Enumeración de certificados | `public_id` aleatorio y mensajes prudentes |
| Inyección o datos inválidos | Consultas parametrizadas, constraints y validación servidor |

## Información pública de verificación

Por defecto se puede mostrar:

- resultado y estado;
- título del certificado;
- nombre público y logo de la institución;
- fecha de emisión y expiración;
- identificador público;
- red y enlace a transacción, si aporta valor.

El nombre completo del estudiante no debe mostrarse públicamente por defecto. Una futura opción de consentimiento o enlace compartido con alcance limitado requiere diseño específico.

## Secretos y configuración

- La clave `anon` pública puede estar en Flutter; su seguridad depende de RLS correcta.
- `service_role`, claves privadas EVM y credenciales administrativas son secretos de servidor.
- Proporcionar `.env.example` con nombres y valores ficticios.
- Ignorar `.env*` reales y habilitar detección de secretos en CI/repositorio.
- Rotar cualquier secreto expuesto y documentar el incidente.

## Storage

- Bucket de certificados privado.
- Ruta basada en IDs opacos, nunca en emails o nombres.
- Escritura únicamente mediante el flujo autorizado.
- Descarga mediante URL firmada y corta.
- Política documentada para revocación, eliminación y conservación legal.

## Checklist antes de demo pública

- RLS habilitada y probada con estudiante A, estudiante B, emisor y anónimo.
- Ninguna tabla sensible tiene grants públicos amplios.
- No existen secretos en Git ni en el binario móvil.
- Endpoints de emisión y revocación validan autorización en servidor.
- Logs y errores no revelan tokens, consultas, rutas privadas o PII.
- Dependencias auditadas y versiones fijadas.
- Se ha probado PDF inválido, grande, alterado y duplicado.

## Limitación académica

El MVP demuestra integridad técnica, no acredita legalmente a una institución ni sustituye marcos regulatorios como eIDAS. Cualquier lanzamiento real requiere revisión legal, DPIA cuando corresponda, gestión profesional de claves y respuesta a incidentes.
