# ADR-0010 — Cliente institucional, recibos y acceso privado al documento

Fecha: 30/09/2026. Estado: aceptada para 7C.

## Decisión

La cuenta conserva Inicio, Mis certificados y Mi perfil como titular. El espacio
institucional se ofrece por membresías reales del usuario actual, independientemente
de profiles.role e institutionPreference. Una selección institucional explícita
delimita listado e intento. No se reutiliza el detalle de titular como detalle
institucional ni se amplía SELECT de perfiles, instituciones o miembros.

El destinatario MVP comparte voluntariamente su UUID desde Mi perfil. El formulario
lo recibe como ID del titular; el backend comprueba elegibilidad con su error
genérico. Invitaciones y búsqueda con consentimiento son otro incremento.

Cada envío lógico fija un UUID antes de HTTP y congela metadatos normalizados y
bytes. Se guarda previamente un recibo sin secretos: clave, fecha y fingerprint v1
SHA-256, separado por actor e institución. Máximo 20 recibos en este dispositivo,
retención de 7 días. No contiene PDF, JWT, título, descripción, destinatario ni
nombre de archivo. SharedPreferences no es un almacén seguro: solo recibe ese
contexto mínimo, que tampoco autoriza ante el servidor.

Tras reiniciar, el usuario debe reintroducir los datos y seleccionar el PDF original.
Solo una huella idéntica habilita el envío con la clave anterior. Se admite reconstruir
la fecha original incluso pasada: el backend puede recuperar completed, sin recalcular
expiración. Si no coincide, no se envía. Abandonar el recibo requiere una decisión
explícita con aviso de duplicados y revisión del listado/operador; no cancela el backend.
Tras pérdida/expiración/evicción del recibo, una emisión nueva no es un reintento seguro.
No se promete recuperar bytes, metadatos ni archivos del dispositivo.

El endpoint separado certificate-pdf verifica Auth real y llama a un RPC técnico
estrecho. Solo titular o owner/admin/issuer actual de la emisora verified pueden
acceder. El titular conserva acceso si la institución se suspende, rechaza o cambia.
Platform_admin sin esa propiedad/membresía, otra institución y UUID conocido no
autorizan. Operación completed, identidad/hash/ruta canónica y bytes disponibles son
obligatorios. Se reautoriza después de leer Storage e inmediatamente antes de firmar.
No hay ampliación de políticas del bucket.

La respuesta no-store contiene URL firmada relativa y expires_in=60; no devuelve
campos document_path, document_hash ni credenciales. La URL contiene necesariamente
la ruta opaca del objeto y un token de capacidad: quien la recibe puede usarla hasta
el vencimiento, también después de perder membresía. No se promete revocación inmediata
de capacidades ya emitidas. Ausente, ajeno, legado e inexistente en Storage comparten
404 document_unavailable. Una comprobación de disponibilidad descarta la URL; cada
descarga solicita otra, sin persistirla ni introducirla en rutas/historial de la app.

Chrome descarga un Blob temporal de los bytes recibidos y revoca su URL. Android/iOS
usan el diálogo nativo de guardado mediante file_picker. El usuario decide conservar
el PDF fuera de la app; esa copia deja de estar controlada por la sesión/backend.
CORS permite el transporte Web con JWT explícito, no cookies ni autorización implícita.

## Alternativas y límites

Un buscador global ampliaría exposición de personas sin consentimiento. Guardar el PDF
en preferencias permitiría recuperación cómoda con un coste de privacidad inaceptable.
Reutilizar una clave para contenido diferente crearía conflicto; inventar otra al
reintentar podría duplicar una emisión confirmada. Un futuro endpoint autorizado de
recuperación puede mejorar el recorrido, pero no es imprescindible para este MVP.

No se implementan aprobación institucional en Flutter, revocación, verificación pública,
QR, blockchain, invitaciones ni publicación remota. Validación local y límites de
dispositivos/CI en [TESTING.md](../TESTING.md).
