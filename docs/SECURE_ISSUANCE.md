# Contrato del futuro backend de certificados

## Estado tras las Fases 5 y 6

Emisión y revocación no están implementadas. `authenticated` solo puede leer
certificados autorizados por RLS, incluso si su perfil es `platform_admin`.
`anon` no tiene acceso a la tabla. No existe un RPC alternativo que escriba certificados.
Flutter conserva su clave pública y la sesión del usuario; nunca recibe
`service_role`, claves de firma ni lógica privilegiada.

Este contrato define comprobaciones para una futura Edge Function u operación
de backend; no introduce endpoints o abstracciones vacías. El hecho de que una
identidad técnica de servidor pueda omitir RLS no autoriza al solicitante:
el backend debe comprobar todos los puntos siguientes antes de persistir.

## Autorización en el momento de emitir

1. Validar la sesión y el token mediante Auth: autenticidad, vigencia y sujeto.
   Derivar la identidad del token validado, no del cuerpo ni de metadatos
   editables del usuario; rechazar sesiones ausentes, inválidas o expiradas.
2. Consultar en base de datos el perfil y una membresía vigente en la institución
   indicada. Autorizar solo `institution_members.role` igual a `owner`, `admin`
   o `issuer`. `holder`, `institution_admin` global y `platform_admin` por sí
   solos no sustituyen la membresía; una excepción administrativa futura exige
   decisión explícita y pruebas, nunca un bypass implícito.
3. Exigir `institutions.verification_status = 'verified'`. `pending`, `rejected`
   y `suspended` se rechazan. Revalidar membresía/rol y estado al crear la fila
   mediante una operación transaccional que serialice los cambios concurrentes
   de autorización; comprobarlos solo antes de subir el PDF sería insuficiente.
4. Comprobar que el destinatario existe en Auth y `profiles`, es elegible como
   titular según la regla de producto acordada y puede resolverse sin enumerar
   perfiles privados. El mecanismo de selección/invitación de destinatario sigue
   pendiente; no ampliar SELECT de perfiles para anticiparlo.

## Entrada, PDF e integridad

- Lista cerrada de campos de entrada; validar título no vacío, descripción,
  límites de longitud, fechas y expiración. Usar el reloj del servidor y exigir
  expiración posterior a emisión en el flujo futuro (la constraint actual
  permite igualdad). No permitir al cliente fijar `issued_by`, estado,
  `revoked_at`, ruta, hash ni marcas internas. Generar IDs/código opacos en servidor.
- El contrato real es `holder_id`, `issued_by`, `credential_code`,
  `document_path`, `document_hash` de tipo text y estado `active`/`revoked`.
  No existen todavía `public_id`, `idempotency_key`, `document_sha256`,
  `anchoring`, `anchor_failed` ni tablas blockchain. Añadir los campos y
  constraints necesarios mediante migraciones nuevas antes de usarlos.
- Validar extensión `.pdf`, tipo real y estructura PDF mediante un parser de
  servidor; MIME declarado o cabecera `%PDF` por sí solos no bastan. Rechazar
  archivos vacíos, truncados, inválidos o que no puedan comprobarse, y aplicar
  controles de contenido malicioso cuando proceda. Establecer un límite finito
  de bytes en backend y bucket, limitar también la lectura/parseo y probar el
  borde y su exceso. El límite global actual de Storage (50 MiB) no es una
  política de documentos aprobada; el valor de producto debe fijarse y probarse
  en la fase de PDF antes de habilitar el endpoint.
- Guardar solo en bucket privado, con rutas de IDs opacos creadas por servidor;
  ningún cliente puede reemplazar el objeto final. Las descargas futuras deben
  autorizarse y usar URLs firmadas cortas. No hay bucket ni flujo PDF entregado
  en esta fase.
- Calcular SHA-256 en backend sobre los **bytes finales almacenados**, después
  de cualquier transformación; comprobar lectura e integridad del objeto final
  antes de crear el certificado. Nunca confiar en un hash aportado por Flutter.
  Definir y validar su representación (por ejemplo, hexadecimal de 64 caracteres
  en el `document_hash` actual) mediante una migración y pruebas futuras.
- Crear inicialmente `active` en la emisión segura sin blockchain. Congelar
  metadatos, emisor, titular, fechas, PDF y hash tras emitir. Corregir un certificado
  requerirá revocación y nueva emisión; no sustituir silenciosamente su PDF.

## Idempotencia y fallos parciales

- Introducir una clave de idempotencia persistente, con unicidad y ámbito de
  institución/operación definidos en base de datos. Vincularla al solicitante y
  al contenido normalizado, incluidos bytes/hash: mismo contenido devuelve el
  mismo resultado; misma clave con otro contenido se rechaza. Probar reintentos
  simultáneos y respuestas perdidas; el actual `credential_code UNIQUE` no
  implementa este contrato.
- PostgreSQL y Storage no comparten una transacción. Registrar el avance de la
  operación, usar un objeto final inmutable y publicar la fila solo cuando
  autorización, PDF e integridad estén confirmados. Si falla la inserción tras
  subir, limpiar el objeto huérfano o dejar trabajo de reconciliación durable;
  si se pierde la respuesta después de insertar, recuperar el resultado sin
  duplicar ni borrar el PDF válido. Probar caídas entre cada paso y limpieza fallida.
- No habilitar el endpoint mientras falten almacenamiento privado, validación,
  constraints de integridad, control transaccional de permisos, idempotencia o
  recuperación. Errores externos seguros y correlación operativa sin PII,
  documentos, rutas privadas, tokens o secretos en logs.

## Revocación futura

La solicitud pasa por backend: validar sesión, membresía `owner`/`admin` en la
institución emisora, propiedad institucional y transición `active → revoked`.
`issuer` no obtiene revocación por el hecho de poder emitir. `revoked_at` se fija
en servidor y la operación es irreversible e idempotente. La política sobre
revocar certificados de una institución suspendida deberá decidirse y probarse
expresamente; no reusar automáticamente la autorización de emisión.

Cuando exista anclaje, registrar y seguir la transacción de revocación, reintentar
de forma segura y reconciliar base de datos y blockchain. La verificación pública
no debe anunciar una revocación confirmada en cadena antes de su confirmación.
Los estados intermedios y evidencias requerirán nuevas migraciones: el esquema
actual solo admite `active` y `revoked`. El trigger histórico únicamente protege
la transición y los campos; no verifica sesión, membresía, PDF ni blockchain y
no constituye una implementación de este flujo.

## Dependencias del siguiente incremento

Fase 6 resuelve el administrador inicial mediante SQL confiable, alta administrada
atómica, aprobación y miembros con protección concurrente del último owner.
Los RPC verifican roles reales y serializan mutaciones por fila institucional;
no habilitan escritura de certificados. Bootstrap, decisiones y procedimiento:
[INSTITUTION_ADMINISTRATION.md](INSTITUTION_ADMINISTRATION.md).

Fase 7: emisión segura sin blockchain mediante backend, PDF privado, SHA-256 e
idempotencia. Su transacción de autorización debe coordinarse con la misma fila
institucional que bloquean los cambios de miembros/estado en fase 6; no basta
con una comprobación previa aislada. Posteriormente: verificación pública/QR, anclaje y
revocación completa con endurecimiento, según [ROADMAP.md](ROADMAP.md).
