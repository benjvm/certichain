# Emisión privada autenticada — Fases 7B, 7C y 7D

## Incremento local de revocación — 15/10/2026

[REVOCATION](REVOCATION.md) define los endpoints Auth, motivo/auditoría privados,
SQL irreversible, worker durable y evidencia pública v3 con issue/revoke separados.
V1/v2 y compare conservan contrato; la app usa v3. Resultados ejecutados y
dictamen vigente: [PHASE10_ACCEPTANCE](PHASE10_ACCEPTANCE.md). Los apartados
que describen revocación futura conservan el contexto histórico de sus fases.
La demo se reproduce con `./supabase/tests/run_phase10.ps1`; sin despliegue remoto,
Sepolia ni corrección Android atribuida. Cámara=0 con la exclusión persistente.

## Integración posterior 9D

Emisión sigue publicando active/completed y PDF privado exactamente como antes.
Cliente institucional permite anclaje explícito de ese certificado, sin repetir
formulario/PDF. Recibo/key aislados antes del POST, recuperar misma solicitud
ante respuesta perdida; progreso/reautorización manuales. 202 no confirma cadena;
worker confiable externo conserva toda firma. Wallet, v1, QR y códigos intactos.
Apertura es otro endpoint Auth protegido, con permisos propios equivalentes al
documento; ningún fallo de anclaje borra la publicación.
[Contrato/operación](BLOCKCHAIN_VERIFICATION.md), [aceptación 9D](PHASE9D_ACCEPTANCE.md).

## Estado y límite de confianza

7B implementa `POST /functions/v1/issue-certificate`. Solo owner/admin/issuer
vigentes de una institución verified pueden emitir. 7C incorpora el cliente
Flutter institucional y `POST /functions/v1/certificate-pdf` para descarga privada.
7D cierra las pruebas integrales y endurecimiento. 8A añade el backend público
descrito en [PUBLIC_VERIFICATION.md](PUBLIC_VERIFICATION.md). 8B–8D entregan
pantalla pública, QR, escáner y comparación local de copia. 8D está publicada en
6235486; el bloqueo histórico de 37373509169 se conserva. CI posterior success
38280055013 intento 1 para 2066e908af30913462cf3daf77324eab2a63dfc4 en
database/flutter/android. Cámara omitida por instrucción vigente; ver TESTING.
Revocación de producto y blockchain siguen pendientes: [9A](PHASE9A_BLOCKCHAIN_SPEC.md)
define el protocolo sin cambiar publicación/completed, hash o permisos actuales.
No se ha desplegado ninguna función ni migración remota.

Para servirlo manualmente, con el stack local reconstruido y la CLI 2.117.0:

```powershell
npx --no-install supabase functions serve
```

Enviar el multipart descrito abajo a http://127.0.0.1:54321/functions/v1/issue-certificate
con Authorization: Bearer de una sesión Auth local real y la clave pública local.
No usar --no-verify-jwt ni el token service_role como sesión del solicitante.

`verify_jwt = true` permanece habilitado. La función consulta efectivamente
Auth `/user` con el JWT del solicitante y la clave pública. Su ID verificado
es el único actor. Otro cliente técnico usa service_role, exclusivamente en
servidor, para las RPC estrechas y Storage. Metadatos y cuerpo no autorizan.
No se amplían grants, RLS ni SELECT de perfiles para clientes.

## Entrada y respuesta

Una petición multipart/form-data contiene exactamente:

| Campo | Contrato |
|---|---|
| institution_id | UUID, normalizado a minúsculas con guiones |
| holder_id | UUID confirmado por un canal operativo autorizado |
| idempotency_key | UUID por intento lógico, scoped a institución |
| title | NFC, trim, 1–200 puntos de código Unicode, sin controles C0/C1 |
| description | Opcional; NFC, trim, hasta 4000 puntos; vacío pasa a NULL |
| expires_at | Opcional; RFC3339 con segundos, zona Z o ±HH:mm y 0–6 decimales |
| pdf | Un File .pdf, MIME application/pdf, bytes reales >0 y <=8 388 608 |

No se admiten claves desconocidas, repetidas, archivos adicionales ni campos
para actor, issued_by, issued_at, estado, código, ID, ruta o hash. El sobre
multipart tiene un presupuesto adicional de 32 768 bytes. La lectura por stream
comprueba bytes reales aunque Content-Length falte o sea falso. El límite del
bucket es una segunda barrera. Una petición que excede límites devuelve 413.

La expiración debe ser futura al reservar/publicar y como máximo diez años desde
reserva. El reintento completed puede recuperar un certificado ya expirado:
la expiración forma parte de su identidad, no se recalcula. Fechas imposibles,
segundos intercalares y fracciones mayores de seis dígitos se rechazan. issued_at
procede de clock_timestamp() en la transacción que publica.

Elegibilidad MVP del titular: Auth y profiles existentes, email confirmado,
no anónimo, no eliminado, no bloqueado actualmente y profiles.role = holder.
Se comprueba después de autorizar al actor y otra vez al publicar, bloqueando
Auth/profiles FOR SHARE. Una identidad no elegible devuelve un error fijo;
no se exponen sus datos. En 7C el titular copia su propio UUID desde Mi perfil y
lo comparte voluntariamente; el formulario permite pegar «ID del titular».
No es un email y no existe búsqueda global. Invitaciones o búsqueda con
consentimiento quedan para un incremento posterior.

Éxito: 201 para la publicación confirmada, 200 para recuperar completed;
`{"status":"completed","certificate_id":"UUID"}`. Nunca se devuelve ruta,
URL PDF, código, huella, hash, token de lease, datos personales ni secretos.
Solo certificate_id y un estado/error seguro son necesarios para el cliente.

| HTTP | error | Significado / actuación |
|---|---|---|
| 401 | unauthenticated | Sesión ausente, inválida, expirada o no resoluble por Auth |
| 403 | forbidden | Sin membresía permitida/institución verified; incluye reintento completed |
| 400/422 | invalid_input | Lista cerrada, campos, fecha o titular no elegible |
| 422 | invalid_pdf | PDF no inspeccionable según política siguiente |
| 413 | payload_too_large | Archivo o petición excede su presupuesto |
| 409 | idempotency_conflict | Misma clave con actor/huella distintos; no modifica reserva |
| 409 | operation_in_progress | Lease activo o propietario vencido; Retry-After: 120 |
| 409 | attempt_failed | cleanup_pending/failed; conciliar y utilizar una nueva clave |
| 503 | temporary_failure | Dependencia/commit incierto; repetir misma entrada tras lease |
| 503 | stored_object_invalid | Colisión/bytes almacenados incoherentes; conciliar |
| 500 | internal_failure | Fallo inesperado sin detalles privados |

El gateway JWT puede responder su propio 401 antes de ejecutar la función.
No se anuncia HTTP success si no se confirma la transacción de publicación.
No se registran peticiones completas, PDF, JWT, rutas, PII o errores upstream.

## Política PDF y recursos

Se fija pdf-lib 1.17.1 y sus dependencias/integridades en functions/deno.lock.
Es TypeScript/JavaScript portable sin proceso externo ni binario nativo, usado
solo para leer; las APIs Web estándar no ofrecen un parser PDF. No se transforma
ni se vuelve a guardar el documento. Entrada y bytes finales tienen el mismo hash.
La dependencia necesita seguimiento de seguridad y pruebas al actualizarse;
el lock y los vectores impiden una actualización silenciosa.

El parser se complementa con validación de header, EOF/startxref, offsets xref,
objetos referenciados, Root, terminadores endobj, longitudes de streams,
referencias y páginas. Se rechaza reparación implícita, truncado/corrupción y
cifrado. Un adaptador pequeño del PDFObjectParser exportado verifica el offset
consumido porque pdf-lib tolera endobj ausente; tiene regresión específica.

Política conservadora MVP: PDF 1.0–1.7 de una sola revisión, xref clásico,
1–100 páginas, <=20 000 objetos/entradas, <=100 000 nodos/nombres y profundidad
<=64; nombres <=1024 caracteres. No se admiten xref/object streams, revisiones
incrementales, codecs desconocidos, cadenas de filtros ni DecodeParms.
Streams sin filtro o FlateDecode son inspeccionables; Flate se descomprime con
lectura limitada a 16 MiB acumulados. Se impide inflar object streams antes de
invocar el parser. Preflight puede rechazar nombres sospechosos dentro de datos:
es una restricción deliberada del MVP, no una promesa de compatibilidad universal.

Se rechazan JavaScript/JS, AA/A/Action/OpenAction, Launch, RichMedia, EmbeddedFiles/
EmbeddedFile/Filespec/EF/AF, AcroForm/XFA, Rendition/Movie/Sound/3D,
SubmitForm, ImportData, GoToR/GoToE y URI en el grafo
parseado, incluidas claves escapadas. Adjuntos, formularios y acciones se deniegan, no se
eliminan silenciosamente. Este parser NO es un antivirus ni un renderer; no
asegura que los operadores gráficos o todos los lectores interpreten igual el
PDF. Ampliar compatibilidad necesita fixtures y otra revisión de recursos.

Se prueba el límite exacto de 8 MiB y FlateDecode en el runtime Edge local
1.74.3 (Deno 2.1.4), además de Deno 2.2.12 en tests. La configuración local
inspeccionada aplica memoryLimitMb=256 y cpuTimeHardLimitMs=2000; los fixtures
HTTP pasan bajo esos límites. Las pruebas locales no sustituyen mediciones de
carga/CPU en un despliegue futuro. No se hizo ese despliegue.
Referencias: [pdf-lib](https://pdf-lib.js.org/docs/api/classes/pdfdocument) y
[límites Edge](https://supabase.com/docs/guides/functions/limits).

## request_fingerprint v1 — contrato literal de 7A

SHA-256 hexadecimal minúsculo de la secuencia UTF-8 `certichain-issuance-v1`
seguida de un byte NUL y siete campos, en este orden: UUID institución, UUID
actor verificado, UUID titular, título, descripción, expiración, pdf_hash.
Cada campo lleva su longitud UTF-8 en BYTES, cuatro bytes big endian; NULL
usa 0xffffffff y no lleva bytes. UUID en minúsculas con guiones; título y
descripción NFC y trim; descripción vacía pasa a NULL. Expiración NULL o UTC
`YYYY-MM-DDTHH:mm:ss.ffffffZ`, preservando los seis decimales sin redondear a
milisegundos. pdf_hash es SHA-256 hex minúsculo de los bytes exactos aceptados.
No entran idempotency_key, issued_at ni código generado por servidor.

El fixture PDF determinista de 330 bytes de tests/pdf_fixture.mjs tiene SHA-256
`598c50f845d76f4fe6125df9906750584668e526be96e78ca43548eb60f20b1f`.
contract_test.ts fija la secuencia completa en hex y vectores NFC, longitudes
multibyte, UTC/microsegundos y NULL frente a longitud cero. Un cambio de formato
necesitaría una versión nueva, nunca reinterpretar reservas existentes.

## Transacciones, bloqueos y recorrido

La migración NUEVA 20260930150000_authenticated_private_issuance.sql añade
metadatos normalizados inmutables y lease_token/lease_until. No reescribe 7A,
certificados históricos ni triggers de revocación. Las RPC públicas siguientes
tienen SECURITY DEFINER, search_path vacío, referencias cualificadas, REVOKE
PUBLIC/anon/authenticated y EXECUTE solo para service_role:

- reserve_certificate_issuance: institución FOR UPDATE → autorización → operación
  FOR UPDATE → comprobación de identidad/titular → reserva/adquisición de lease.
- advance_certificate_issuance: institución FOR UPDATE → operación FOR UPDATE →
  token/estado/tiempo → transición. publish revalida autorización y titular antes
  del INSERT. El servidor genera credential_code opaco y issued_at.

Es el mismo orden padre primero de los cambios de membresía/estado de Fase 6.
No hay SQL abierto durante Storage. Las referencias Auth/profiles se bloquean
tras institución/operación. Deadlocks/serialización abortan y se reintenta la
operación completa; un lease perdido usa PT409, evitando que PostgREST lo trate
como un error de serialización que puede reintentar internamente.

1. Auth, entrada y parser se validan ANTES de reservar/subir; calcular pdf_hash
   y huella v1 normalizada en backend.
2. La reserva UNIQUE(institution_id,idempotency_key) fija actor/titular/huella/
   hash/target_certificate_id. Igual actor y huella recuperan resultado o lease;
   otro actor/contenido autorizado recibe conflicto sin alterar la fila.
3. reserved → uploading con token nuevo y vencimiento de 120 segundos del reloj
   PostgreSQL. Solo una transacción adquiere propiedad, incluida reserva vencida;
   otros intentos reciben in_progress o completed. El token anterior no finaliza.
4. Storage API sube application/pdf a institution_id/target_certificate_id.pdf,
   upsert:false. Una colisión se lee e investiga; nunca permite reemplazo.
   Respuesta de subida perdida también se resuelve por lectura, sin suponer fallo.
5. Descargar por cliente técnico, limitar lectura, inspeccionar PDF y comprobar
   tamaño exacto y SHA-256. uploading → finalizing almacena stored_hash = pdf_hash.
6. publish inserta el certificado active con issuance_operation_id, ruta y hash
   coherentes, y cambia operación a completed EN UNA transacción. Una excepción
   en el segundo paso revierte también el certificado. Los metadatos publicados
   y resultado completed son inmutables. Dos claves pueden emitir igual contenido.
7. Solo después de confirmar publish se devuelve 201. Si se pierde esa respuesta,
   el mismo actor actualmente autorizado obtiene 200 y el mismo certificate_id.
   Un actor retirado o institución suspendida recibe 403 incluso si completed:
   no se revela el resultado privado mediante el endpoint.

## Recuperación y reconciliación local real

No hay cron. El cliente debe guardar la clave y reenviar exactamente PDF y
metadatos. uploading/finalizing vencidos se recuperan con nuevo token: se intenta
subir sin upsert, se lee cualquier objeto existente, se valida y se publica.
También cubre corte después de reserva, subida confirmada con respuesta perdida,
objeto existente en uploading, lectura correcta con publicación fallida y
respuesta perdida después de completed. Se devuelve estado claro durante lease.

Si permisos, titular/expiración o integridad fallan tras subir, abandon cambia a
cleanup_pending cuando el lease sigue vigente. Si falla también esa RPC, la fila
uploading/finalizing sigue durable y el operador puede conciliarla al vencer.
No se borra un objeto en un catch de emisión.

El operador local puede DESCARTAR una reserva abandonada (no completarla sin
metadatos/PDF) con:

```powershell
node supabase/admin/reconcile_issuance.mjs --local <operation_uuid>
# O recorrer por páginas todas las operaciones no completadas:
node supabase/admin/reconcile_issuance.mjs --local
```

El UUID de operación solo se consulta por un operador técnico, no se devuelve
al cliente. La herramienta verifica loopback/puerto 54321 y usa claves locales de
supabase status exclusivamente en memoria; no acepta proyecto/URL remotos.

cleanup_claim bloquea institución/operación, rechaza lease activo y cualquier
certificado que referencie la operación/ruta, y obtiene lease de limpieza.
cleanup_check vuelve a comprobar BD inmediatamente antes de Storage DELETE.
cleanup_pending/failed nunca pueden volver a uploading por RPC: no habrá una
publicación concurrente tras ese chequeo. Se borra por API Storage, se confirma
404 por lectura y solo entonces cleanup_done fija failed. Jamás se manipula
storage.objects por SQL ni se limpia un PDF completed, incluso revocado.

Un fallo de borrado deja cleanup_pending; tras 120 segundos, ejecutar de nuevo.
failed es una lápida conservada: la conciliación vuelve a revisar sus objetos
para retirar una subida antigua que llegó después del borrado. Un proceso viejo
no puede publicar ni reclamar esa clave. No se promete barrer subidas tardías
sin que el operador vuelva a ejecutar el comando. Usar una NUEVA clave tras
failed/cleanup_pending; nunca sustituir bytes de una emisión publicada.
Reservas antiguas de 7A sin metadatos siguen limpiables, no se inventa su título.

## Anclaje explícito backend 9C

Publicación sigue terminando en active/completed con PDF privado. Anclaje posterior
mediante anchor-certificate, Auth real y autorización actual, nunca automático.
Sus fallos no borran completed/certificado/PDF. 202/200 mínimo de operación no
garantiza inclusión. Progreso/reautorización privados. Sin cambiar Flutter ni
habilitar revocación. [Operación](BLOCKCHAIN_OPERATIONS.md) y
[evidencia/límites](PHASE9C_ACCEPTANCE.md).

## Revocación y siguientes fases

El trigger histórico de certificados solo controla UPDATE y no bloquea el INSERT
del flujo nuevo; se conserva intacto junto con la inmutabilidad de 7A. No existe
endpoint de revocación. Su futuro backend exigirá owner/admin de la institución,
transición active → revoked, hora de servidor y una política explícita sobre
instituciones suspended. Blockchain necesitará su propio registro/reconciliación.

7C entrega pantallas de emisión, ID de titular voluntario y descarga autorizada
con URL firmada breve. 7D entrega E2E, carga/límites de abuso, revisión de compatibilidad
PDF y endurecimiento operativo. QR/verificación pública y blockchain permanecen
fuera de 7B. Resultados reales y CI observado están en TESTING.md.

## Cliente institucional 7C y recuperación

Inicio, Mis certificados y Mi perfil siguen siendo la faceta de titular.
«Espacio institucional» aparece únicamente tras leer membresías reales propias
con RLS. Ni institutionPreference ni profiles.role autorizan. La institución
activa determina listado y borrador; varias instituciones no comparten solicitud.
Pending/rejected/suspended muestran bloqueo. Se releen permisos al entrar,
reanudar, renovar sesión, cada 30 segundos y antes de enviar. Backend revalida
siempre; una baja durante la petición puede denegarla.

Datos valida UUID, NFC/trim y los límites anteriores. La fecha elegida se expresa
a medianoche UTC con seis decimales RFC3339 y se conserva normalizada. Documento
selecciona un único PDF, muestra nombre/tamaño, permite reemplazo y limita a
8 388 608 bytes antes de leer en Web y antes/durante la lectura nativa. Estas ayudas no inspeccionan ni
sustituyen el parser servidor. Confirmar es el único paso con envío: JWT real,
multipart y una petición sin porcentaje ni etapas ficticias. 201/200 muestran el
ID, refrescan el listado y permiten ir a Certificados emitidos, sin abrir un
detalle personal del emisor que filtre por otro titular.

Antes del primer envío se crea un UUID y se congela institución, titular,
metadatos normalizados y bytes. Doble pulsación no produce dos peticiones.
operation_in_progress espera Retry-After (120 segundos) antes de acción manual;
temporary_failure/respuesta perdida permiten reenviar la misma solicitud y clave.
Conflicto, attempt_failed y stored_object_invalid requieren revisión; no hay
reintentos automáticos ni sustitución silenciosa de clave.

Antes de HTTP se persiste solo un recibo (UUID de clave, huella v1 de solicitud,
fecha), separado por usuario/institución, máximo 20 recibos y retención 7 días.
No contiene campos personales, filename, PDF, JWT ni secreto. No es un almacén
cifrado: contiene únicamente evidencia mínima, nunca material de la sesión.
Tras reinicio se pide reconstruir datos y volver a seleccionar los bytes
originales; solo coincidencia exacta de huella habilita la misma clave. Incluso
una expiración ya pasada se conserva para recuperar completed. Si no coincide,
el envío queda bloqueado. «Iniciar una emisión nueva» requiere una decisión
explícita y advierte comprobar el listado/operación anterior por riesgo de
duplicado; no cancela ni recupera la operación anterior. Un recibo eliminado,
caducado o borrado con los datos del navegador no garantiza recuperación.
401 activa el flujo existente de sesión y destruye datos visibles de esa cuenta.

## Endpoint PDF 7C

`POST /functions/v1/certificate-pdf`, JSON cerrado `{"certificate_id":"UUID"}`,
Authorization Bearer de sesión Auth real y clave pública. OPTIONS únicamente
ofrece CORS; las operaciones exigen autenticación. Cache-Control: no-store en
todas las respuestas; no se registran capacidades ni cuerpos.

La RPC técnica `authorize_certificate_document`, ejecutable solo por service_role,
comprueba vínculo 7A/7B completed, IDs, hash almacenado y ruta canónica. El servidor
verifica objeto, límite y hash de bytes y revalida autorización antes de firmar.
El titular conserva acceso aunque la institución se suspenda. Un miembro debe
ser owner/admin/issuer actual de la institución emisora verified. platform_admin
por sí solo, otra institución y conocer el UUID no conceden acceso.

200 devuelve únicamente `signed_url` (capacidad relativa al API público configurado)
y `expires_in: 60`. No hay campos document_path, document_hash ni credenciales.
La capacidad contiene necesariamente el identificador opaco del objeto y su
token; puede reutilizarse hasta vencimiento incluso tras una baja posterior.
401 significa sesión inválida; 404 document_unavailable es indistinguible para
certificado ajeno/ausente/legado sin PDF/objeto ausente; 503 temporary_failure
es seguro. El bucket sigue privado sin SELECT/descarga directa para usuarios.

Flutter consulta disponibilidad y descarta esa capacidad; cada «Descargar PDF»
pide una nueva, descarga bytes y la descarta. Chrome descarga un Blob temporal
sin navegar a la URL firmada; Android/iOS usan el diálogo de guardado nativo.
No se persiste ni se añade a modelo/ruta/historial. No se ofrece una preview.
Véase [ADR-0010](adr/0010-institutional-client-and-document-capabilities.md).

## Endurecimiento y evidencia local 7D

Las lecturas de membresías y certificados emitidos capturan identidad y token
vigentes antes de la petición y los comprueban, junto con la caducidad, después.
Una respuesta obtenida bajo otra sesión, incluso del mismo usuario tras renovar
el token, se descarta. El widget sustituye futuros al refrescar o seleccionar
otra institución; el navegador ligado a identidad elimina las rutas anteriores.
Esto no cambia SELECT/RLS ni revoca datos ya descargados por un usuario autorizado.

La prueba Web usa el mismo cliente, UI, repositorios, preferencias y adaptadores
de producción con cuentas sintéticas. El runner local ejecuta el bootstrap
administrativo y comprueba PostgreSQL/Storage, sin enviar claves técnicas a Flutter.
Solo retiene o descarta respuestas **ya obtenidas del backend real** para probar
aislamiento y recuperación; no fabrica respuestas ni sustituye servicios.

Compatibilidad y carga son pruebas del subconjunto PDF documentado, con fixtures
sintéticos y límites explícitos, no un benchmark de producción ni una promesa
para todos los generadores PDF. Los leases se vencen mediante SQL confiable del
fixture; el valor de producción continúa en 120 segundos. El caso de JWT vencido
conserva claims/algoritmo/kid de Auth real y verifica la firma original antes de
firmar una expiración pasada con la clave del **contenedor local**, solo en memoria
del runner. El gateway real rechaza ese token; no se desactiva verify_jwt.

Las nuevas descargas siempre solicitan autorización/firma. Storage firma con
precisión de segundos: dos firmas dentro del mismo segundo pueden producir la
misma cadena; cruzando el `iat` real se comprueba otra URL, TTL de 60 segundos,
no-store del endpoint y caducidad efectiva. No se amplía el alcance de esa capacidad.
Comandos, resultados, límites de plataformas y CI observado en [TESTING.md](TESTING.md).
