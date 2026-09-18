# Seguridad y privacidad

## Activos sensibles

- Documentos PDF y datos personales del estudiante.
- Sesiones y tokens de autenticación.
- Claves de servicio de Supabase y claves blockchain.
- Membresía y permisos de instituciones.
- Integridad entre PDF, base de datos y registro on-chain.

## Límites de confianza

Flutter y cualquier navegador son clientes no confiables. RLS y las operaciones de backend deben volver a comprobar identidad, pertenencia, estado de la institución, propiedad del certificado y validación de entrada.

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
