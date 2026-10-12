# Seguridad y privacidad

## Activos sensibles

- Documentos PDF y datos personales del estudiante.
- Sesiones y tokens de autenticación.
- Claves de servicio de Supabase y claves blockchain.
- Membresía y permisos de instituciones.
- Integridad entre PDF, base de datos y registro on-chain.

## Límites de confianza

Flutter y cualquier navegador son clientes no confiables. RLS y las operaciones de backend deben volver a comprobar identidad, pertenencia, estado de la institución, propiedad del certificado y validación de entrada.

## Autorización efectiva tras las Fases 5, 6, 7A, 7B y 7C

`certificates` tiene únicamente una política SELECT para `authenticated`:
titular, miembro de la institución emisora o `platform_admin`. Los grants del
rol API se limitan a SELECT; no puede emitir, modificar, revocar, hacer upsert
ni borrar, aunque su rol de aplicación sea `owner`, `admin`, `issuer` o
`platform_admin` y la institución esté `verified`. No basta con aprobar la
institución para abrir INSERT: también son obligatorias las validaciones de
archivo, hash y operación del servidor.

`anon` no tiene grants sobre certificados y no obtiene filas de perfiles,
instituciones ni membresías por RLS. 8A publica únicamente una proyección cerrada
mediante Edge; no abre ninguna tabla a clientes.
Se han retirado TRUNCATE, REFERENCES y TRIGGER de las cuatro tablas para
PUBLIC, `anon` y `authenticated`; las lecturas autorizadas se conservan.
TRUNCATE exige control mediante grants porque
[PostgreSQL no le aplica RLS](https://www.postgresql.org/docs/17/ddl-rowsecurity.html).
7B añade dos RPC técnicas con EXECUTE solo para service_role; no son una vía
de emisión directa para clientes.
La tabla `certificate_issuance_operations` tiene RLS sin políticas y no concede
lectura ni escritura a `anon` o `authenticated`; contiene claves, huellas y
vínculos privados. Los nuevos triggers de integridad no tienen EXECUTE directo
para roles API ni service_role. Ningún RPC de 7A publica certificados.

La emisión se realiza exclusivamente por el backend autenticado; la revocación
sigue pendiente. El contrato vigente está en
[SECURE_ISSUANCE.md](SECURE_ISSUANCE.md). El backend valida sesión, rol/membresía,
`verification_status = 'verified'` en la emisión, destinatario, campos,
PDF real y límites, almacenamiento privado, SHA-256 de los bytes finales,
idempotencia y recuperación. El backend es responsable de autorización
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
| Cambio de metadatos o PDF | Inmutabilidad tras emisión y SHA-256; compromiso on-chain futuro, aún no implementado |
| Clave blockchain extraída | Clave solo en backend/secret manager, nunca en app |
| Abuso de endpoint público | Rate limit, respuesta uniforme y monitorización sin PII |
| Archivo malicioso | Límite de tamaño, MIME real, PDF válido y análisis cuando proceda |
| Doble emisión por reintento | Clave de idempotencia y constraint unique |
| Enumeración de certificados | `credential_code` UUID aleatorio independiente, presupuesto compartido y ausencia uniforme |
| Inyección o datos inválidos | Consultas parametrizadas, constraints y validación servidor |

## Información pública de verificación

8A permite exclusivamente `schema_version`, `result`, `credential_code`, `title`,
`issuer.name`, `issued_at`, `expires_at`, `checked_at` y `verification_source`.
Para `not_found`, solo `schema_version` y `result`. No hay logo en el modelo
actual, ni campos blockchain en este contrato.

La elegibilidad exige publicación completed y evidencia coherente. Prioridad:
revoked, expired (expires_at <= checked_at), issuer_unavailable, valid.
Suspender una institución no revoca sus certificados. Las fechas conservan
microsegundos y proceden de PostgreSQL. `valid` acredita el registro bajo estas
condiciones; no identifica al presentador ni compara su copia de PDF.

`verify-certificate` tiene verify_jwt=false exclusivamente para ese endpoint.
Cada POST consume presupuesto global atómico 60/60 s antes de validar entrada;
OPTIONS no consume. La fila privada no registra IP, códigos ni eventos; no se
confía en X-Forwarded-For. Si falla la infraestructura, se devuelve 503 seguro.
RPC técnicos exclusivos service_role, search_path vacío y sin nuevos grants de
tablas/Storage. No hay lectura de PDF por consulta. Alcance y límite de confianza:
[PUBLIC_VERIFICATION.md](PUBLIC_VERIFICATION.md). El presupuesto es protección
de la demo local, compartido por todos; producción requiere otro diseño de abuso.

El nombre completo del estudiante no debe mostrarse públicamente por defecto. Una futura opción de consentimiento o enlace compartido con alcance limitado requiere diseño específico.

## Secretos y configuración

- La clave `anon` pública puede estar en Flutter; su seguridad depende de RLS correcta.
- `service_role`, claves privadas EVM y credenciales administrativas son secretos de servidor.
- Proporcionar `.env.example` con nombres y valores ficticios.
- Ignorar `.env*` reales y habilitar detección de secretos en CI/repositorio.
- Rotar cualquier secreto expuesto y documentar el incidente.

## Storage

- Bucket `certificates` privado, `application/pdf`, máximo 8 388 608 bytes.
  La configuración vive en migración y config local. Cuatro políticas
  restrictivas de `storage.objects` deniegan SELECT/INSERT/UPDATE/DELETE en
  ese bucket a `anon` y `authenticated`, incluso ante futuras políticas
  permisivas. Las pruebas HTTP locales comprueban listar, leer, subir,
  reemplazar y eliminar; la ausencia de políticas por sí sola no sería prueba.
- Ruta final `<institution_id>/<certificate_id>.pdf` con UUID opacos, sin nombres
  ni emails; `upsert: false` e inmutabilidad tras publicar. 7B hace validación
  estructural del PDF, límite de bytes en backend y lectura/hash del objeto
  final antes de publicar. El MIME/límite del bucket no sustituyen esa validación.
- Descarga autorizada en 7C mediante URL firmada de 60 segundos. Los PDF emitidos se
  conservan, también si se revocan. El reconciliador local explícito puede borrar
  por API Storage un huérfano confirmado; no hay borrado automático de PDFs
  válidos. La política legal de retención requiere decisión posterior.

## Checklist antes de demo pública

- RLS habilitada y probada con estudiante A, estudiante B, emisor y anónimo.
- Ninguna tabla sensible tiene grants públicos amplios.
- No existen secretos en Git ni en el binario móvil.
- Endpoints de emisión y revocación validan autorización en servidor.
- Logs y errores no revelan tokens, consultas, rutas privadas o PII.
- Dependencias auditadas y versiones fijadas.
- Se ha probado PDF inválido, grande, alterado y duplicado.

## Privacidad y autoridad EVM — diseño 9A

[9A](PHASE9A_BLOCKCHAIN_SPEC.md) selecciona compromiso documental con salt privado:
SHA-256 del PDF no aparece en cadena, eventos, calldata ni DTO público. Omitirlo
del API no lo mantendría privado si se publicase on-chain. K derivado del código
y issuerId opaco siguen correlacionables. Sin apertura autorizada, un tercero
no puede verificar la correspondencia PDF/compromiso; match candidato v1 sigue
confiando en Supabase. Salt se persiste privado antes de firma, se conserva en
reintentos/backup y nunca se sustituye bajo una clave ya registrada.

Administrador EVM y firmante operativo backend separados. Cuenta de servicio
compartida autorizada por issuerId; no acredita firma personal de cada universidad.
Backend conserva Auth/membresías reales; emisión verified, revocación futura
owner/admin de emisora verified o suspended. Cambios SQL/EVM no son atómicos y
retirar una membresía no cancela una transacción ya firmada. No wallets/secretos
en Flutter. RPC Anvil interno o loopback, sin exposición pública privilegiada.

Evidencia v2 futura podrá publicar chain ID, contrato, versión, clave/compromiso/
emisor opacos, transacción/bloque, confirmaciones/finalidad y fecha/origen. Esta
lista no modifica v1 ni sus RPC en 9A. Nunca titular, H/salt, PDF/ruta/capacidad
privada o motivo de revocación. Fallos RPC no son ausencia, revocación ni PDF
alterado. Tablas futuras privadas y retención en sección 6 de 9A.

## Limitación académica del MVP

El MVP demuestra integridad técnica, no acredita legalmente a una institución ni sustituye marcos regulatorios como eIDAS. Cualquier lanzamiento real requiere revisión legal, DPIA cuando corresponda, gestión profesional de claves y respuesta a incidentes.


## Controles efectivos del backend 7B

La Edge Function `issue-certificate` conserva verify_jwt=true y valida el JWT
mediante Auth con un cliente separado del técnico. Actor exclusivamente de ese
ID, nunca cuerpo/user_metadata. Las RPC service_role autorizan por institución
bajo bloqueo padre primero y revalidan antes del INSERT. Platform_admin sin
membresía no emite; un actor retirado no recupera completed por este endpoint.
Titular confirmado/no anónimo/no bloqueado/no eliminado con perfil holder.

Entrada multipart cerrada, sin issued_by/status/ID/ruta/hash/código manipulables;
límite real de lectura incluso sin Content-Length, PDF de hasta 8 MiB, metadatos
limitados, fechas normalizadas con microsegundos e issued_at de BD. Validación
estructural mediante pdf-lib 1.17.1 fijado y controles complementarios, con
subconjunto conservador documentado: sin cifrado, acciones, JavaScript ni adjuntos;
recursos/Flate acotados. El parser no es un antivirus ni prueba de renderizado.

Storage exclusivamente técnico, ruta reservada y upsert:false; una colisión se
inspecciona sin reemplazo. Leer/limitar/validar bytes almacenados y comparar
SHA-256 antes de publicar. Certificado/completed atómicos. Token de lease de
120 segundos protege procesos vencidos; cleanup_pending/failed nunca se reabren.
Limpieza revalida BD, usa Storage API y confirma ausencia; completed/revocado se
conserva. No hay cron: la conciliación local explícita conserva fallos pendientes
y lápidas para subidas tardías. No registra PDF, JWT, rutas, huellas, PII o secretos.

Respuesta mínima con certificate_id o error/estado seguro, Cache-Control:no-store;
sin PDF público, ruta privada ni huella. Inyección de fallos solo disponible en
runtime loopback/kong local sin DENO_DEPLOYMENT_ID y con token efímero de prueba;
no tiene efectos sin esa configuración. No habilita acciones privilegiadas
adicionales. Contrato y límites: [SECURE_ISSUANCE.md](SECURE_ISSUANCE.md).

## Lectura privada del documento en 7C

certificate-pdf verifica Auth real en cada petición y usa una RPC técnica de
EXECUTE exclusivo service_role. Requiere operación completed, vínculo/IDs/hash
coherentes, ruta canónica y objeto disponible con bytes íntegros. Revalida antes
de firmar. No cambia grants/RLS de perfiles, miembros, instituciones, certificados
ni Storage. Conocer UUID o profiles.role = platform_admin no autoriza el PDF.

Permiso: titular propio siempre, aun con institución suspendida; o miembro actual
owner/admin/issuer de la institución emisora verified. Bajas/suspensión deniegan
URLs nuevas a miembros; otra institución/persona y anónimo no obtienen documento.
Los casos ajeno/ausente/legado sin PDF/objeto ausente comparten 404 seguro sin
describir existencia. Se devuelven solo signed_url y expires_in:60, no campos
document_path/document_hash ni secretos. La URL necesariamente contiene la ruta
opaca del objeto y su token: es una capacidad reutilizable por cualquiera que
la posea hasta vencer, aunque cambien permisos tras su entrega. No se promete
revocación instantánea de capacidades. Cache-Control:no-store; no logging de URLs.

Flutter nunca conserva capacidades en entidades, preferencias, rutas o historial.
Cada descarga vuelve a solicitar acceso; Chrome usa Blob temporal, Android/iOS
guardan bytes con selector nativo. El archivo guardado queda bajo control del
usuario: una baja de membresía no borra copias ya descargadas. El bucket continúa
privado y bloqueado para operaciones directas anon/authenticated.

El UUID de titular se comparte voluntariamente desde su perfil; no hay búsqueda
de correo ni SELECT de terceros. La preferencia Institución del registro no es
autorización. Los recibos de emisión locales guardan clave/huella/fecha y se
limitan a 20/7 días por claves de identidad e institución; no PDF, JWT, secretos,
filenames ni metadatos personales. Son preferencias sin cifrado, evidencia mínima
que se descarta al vencer. La UI destruye datos visibles al cambiar de
cuenta/401 y no inicia una emisión nueva como si fuera recuperación exacta.
Detalles y riesgos en [ADR-0010](adr/0010-institutional-client-and-document-capabilities.md).

7D añade barreras de sesión a las lecturas institucionales: una identidad o token
distintos, o sesión vencida, impiden devolver resultados obtenidos previamente.
El E2E local conserva respuestas reales durante cambios de institución, cuenta
y renovación para comprobar que no se presentan datos anteriores. No amplía
permisos ni altera la ventana de una capacidad PDF ya entregada. Los fixtures
privilegiados, firma de JWT vencido y conciliación se ejecutan exclusivamente
en el runner local; claves administrativas y de firma nunca llegan al cliente.

## Cliente público y compartición autorizada — 8B

HttpVerificationRepository usa cliente independiente sin credenciales
Supabase/Authorization/apikey ni cookies (fetch credentials:omit en Web). Fallos públicos no disparan
requireSignIn/logout. API exclusivamente desde SUPABASE_URL validado, nunca desde
el enlace. Proyección v1 cerrada y fechas estrictas; abort/15 s/8 KiB y errores
técnicos separados de not_found. Estado del servidor. Retry-After bloquea
reintento manual; sin polling o idempotencia pública. Presupuesto global 60/60 s.

La lectura del código propio captura identidad/token/caducidad al iniciar y
revalida al recibir, aunque RLS autorice otras facetas institucionales. Filtros
id/holder_id y solo cuatro campos. Sin RPC, permisos, migraciones, perfiles ajenos
u operaciones privadas nuevos. issuance_operation_id protegido por 7B identifica
vínculos existentes; endpoint conserva el juicio completo de elegibilidad.
Históricos sin vínculo no se comparten ni transforman. Compartir expone
voluntariamente un UUID de registro; no concede PDF ni acceso privado.

PUBLIC_VERIFICATION_BASE_URL separa Web/backend; HTTPS salvo loopback HTTP en
desarrollo, sin credenciales/query/fragmento. QR solo URL/código, sin nombres,
correos, hashes, JWT/apikey/capacidades PDF; documento emitido intacto.
Sin códigos/resultados/historial en preferencias. Panel propiedad de la ruta,
retirado ante sesión/token/identidad distintos. Navigator privado sustituido
tras logout; historial Web no lo reconstruye.

Evidencia HTTP/Web con stack descartable, fixtures sintéticos y Auth/Edge reales.
Secretos administrativos en host, nunca build/QR/petición pública. CDP comprueba
headers efectivamente transmitidos y un contexto aislado sin sesión. QR
decodificado independientemente. 8C aborda cámara/archivo elegido/privacidad/
recursos; 8D endurecimiento integral/abuso operativo. Sin enlaces nativos,
identidad del presentador, blockchain o despliegue. La comparación de copia está
implementada mediante hash candidato, con bytes únicamente locales.


## Escáner y hash candidato — 8C

El cliente público no publica document_hash. compare-certificate-hash devuelve
solo schema_version, verification v1 y file_integrity. Campos públicos permitidos
siguen siendo los de 8A; no se añaden titular, ruta, archivo o hash esperado.
El candidato revela únicamente SHA-256 aportado voluntariamente por quien compara;
no se registra en logs, preferencias o tablas. Bytes/nombre/ruta permanecen en
el dispositivo; no hay upload/Storage ni reescritura. Vacío/>8 MiB rechazado y
lectura acotada; el MIME/extensión orienta el selector y no prueba integridad.

Código y digest estrictos, cuerpo 2 KiB, respuesta 8 KiB, deadlines/no-store,
CORS y el presupuesto global atómico 60/60 compartido, incluidos POST inválidos.
Errores de infraestructura nunca se convierten en not_found o discrepancia.
RPC exclusivos service_role con search_path vacío; snapshot privado cerrado.
Estado/hash desde una lectura coherente, sin ampliación de permisos. Coincidir
no hace válido un certificado revocado/caducado y no prueba identidad/blockchain.

Cámara por acción, permiso mínimo y frames locales sin persistencia. QR aceptado
solo por contrato de base confiable/UUID; ningún enlace ajeno se abre/consulta.
Detección bloqueada antes de parar para impedir duplicados; pausa/cierre/dispose
invalida callbacks y libera cámara incluso si termina tarde el permiso. Decoder
Web local versionado, licencia y manifest; no CDN durante la lectura. Cambiar
archivo/código o cerrar invalida cálculo/respuestas. Reintentos siempre explícitos.

El transporte Web exige credentials:omit: withCredentials:false conserva cookies
same-origin. E2E precarga una cookie de sesión sintética en el origen del proxy
y comprueba CDP/servidor sin Cookie, Authorization o apikey. Datos de fixtures y
claves técnicas están solo en host del stack descartable. Diagnóstico del harness
CDP/Chrome conserva tipos/localizaciones/categorías acotadas, nunca mensajes
crudos, expresiones, URLs, payloads, tokens o stderr completo.


## Evidencia integral 8D y límite de lanzamiento

El recorrido release sobre main.dart verifica ausencia de Authorization/apikey/
Cookie en ambos endpoints públicos, incluido origen compartido con cookie
preexistente. Solo se envían código y hash candidato; no se sube el PDF comparado.
QR y clipboard contienen únicamente el enlace público con código. El navegador
carga el decoder y procesa los fotogramas localmente, sin CDN ni subida. El build
se inspecciona para excluir service_role, JWT secret y token técnico de fallos.
Los DTO cerrados no incluyen hash registrado, titular, rutas ni URLs firmadas.
Las pruebas SQL/HTTP conservan RLS, bucket privado y denegación de RPC técnicos a
anon/authenticated, y comprueban aislamiento entre titulares y cambio de cuenta.

Las alteraciones del presupuesto y el teardown de fixtures se limitan a proyectos
certichain_8d_* (o los anteriores certichain_8a_*) creados fuera del repositorio,
o al runner CI nuevo. Una variable de entorno por sí sola no autoriza el stack
habitual. Se restaura el contador; los guards de teardown se restauran dentro de
una transacción y se eliminan únicamente filas/objetos de la ejecución sintética.
No hay migraciones nuevas ni relajaciones de HTTPS/RLS en producción.

El presupuesto global atómico compartido 60 POST/60 segundos puede agotarse para
todos los usuarios. La prueba de renovación espera tiempo real, sin modificar
reloj ni contador durante esa ventana. Protección para lanzamiento público queda
pendiente de diseño y pruebas de carga. Limitaciones de plataforma y retención
local: [PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md).
