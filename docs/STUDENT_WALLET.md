# Fase 4C — Inicio autenticado y wallet personal

## Navegación e interfaz

Después del login, registro con sesión o restauración, `/` muestra el área
autenticada. `AuthenticatedSection` centraliza sus tres destinos internos:
Inicio, Mis certificados y Mi perfil (consulta). No son URLs ni deep links.
Atrás desde wallet/perfil vuelve a Inicio. Las rutas públicas `/`, `/login` y
`/register` conservan su flujo cuando no hay sesión.

Inicio presenta saludo desde `profiles.full_name`, avatar genérico sin foto
inventada, total real, accesos 2×2 y tres certificados recientes. Mi perfil
muestra nombre y rol procedentes de la tabla, sin conceder permisos. Todas las
cuentas reciben esta vista personal; los paneles institucionales quedan pendientes.
Wallet muestra hasta 50 certificados, del más reciente al más antiguo, con
desempate por ID. Indica el límite cuando el total lo supera. Solo existe el
chip «Todos»: el esquema vigente no tiene categorías de certificados.

Se reutilizan tema, espaciados, radios y AppButton. La navegación inferior incluye
los tres destinos funcionales. Escanear y añadir certificados están deshabilitados
y etiquetados como no disponibles. Las tarjetas no abren detalles falsos. No se
usan fixtures ni datos de demostración en producción.

## Lectura y permisos

- Perfil: `profiles.select(id,full_name,role).eq(id, userId).maybeSingle()`.
  Un perfil ausente muestra un error recuperable con reintento y posibilidad de
  cerrar sesión. No se fabrica un perfil con metadatos de Auth o datos del formulario.
- Wallet: `certificates`, filtro explícito `holder_id = userId`, orden
  `issued_at DESC, id DESC`, límite 50 y `count=exact`. Se solicitan únicamente
  `id, holder_id, institution_id, title, issued_at, expires_at, status` y
  `institutions(name)` mediante relación opcional (sin `!inner`).
- Se usa el cliente Supabase existente, con clave pública y sesión del usuario.
  RLS sigue siendo la autorización efectiva. El filtro de titular es necesario
  incluso para usuarios que puedan leer certificados ajenos como miembros o admins.
- La RLS de instituciones permite leerlas a miembros y administradores de
  plataforma; ser titular no basta. Si la relación devuelve null se muestra
  «Institución no disponible» y se conserva el certificado. No se expone un nombre
  inventado ni se amplían permisos para resolver esta limitación.
- No se leen rutas de documentos, hashes, correos ni códigos de credencial.
  No se cambian migraciones, RLS, esquema o dependencias.

El dominio deriva la vigencia: `revoked` prevalece sobre la expiración;
`active` con `expires_at <= ahora` se muestra «Expirado» y el resto «Válido».
Un estado desconocido falla de forma segura. Las fechas se muestran en la zona
local del dispositivo como `dd/MM/yyyy`; los instantes de expiración se comparan
con su zona horaria. El estado no acredita verificación blockchain y la UI lo explica.
Un temporizador actualiza la vigencia al alcanzar la próxima expiración visible.
La hora del dispositivo solo sirve para presentación; una futura verificación
autoritativa deberá usar el backend.

## Estados y ciclo de vida

Perfil y wallet tienen lecturas independientes, carga accesible, error seguro y
reintento. Un fallo nunca se interpreta como wallet vacía ni total cero. La lista
vacía explica dónde aparecerán futuros certificados. Las peticiones tienen un
timeout de 20 segundos. «Actualizar datos» y volver al primer plano recargan datos;
no hay suscripción Realtime. La revocación realizada fuera de la app se refleja
al recargar.

El navegador se sustituye al cambiar de identidad/estado Auth. Sus futuros y
temporizadores no pueden presentar respuestas de la sesión anterior. Los
reintentos sustituyen también el futuro de lectura; se ignoran respuestas
supersedidas y se cancelan temporizadores al destruir el área. Los datos solo se
mantienen en memoria durante esa sesión, sin segunda caché persistente.

## Verificación

Desde `mobile/`: `dart format lib test`, `flutter analyze`, `flutter test`.

- Widgets con repositorios falsos: perfil presente/ausente, carga/error/reintento,
  wallet vacía y poblada, fechas/estados, navegación, cambio de identidad con
  respuestas tardías, cierre de sesión y conservación de pestaña al refrescar token.
- Adaptadores con SDK real y servidor HTTP loopback simulado: selección de campos,
  filtro por titular, límite, orden, total, relación inaccesible/accesible, perfil
  ausente, error de backend y rechazo de titular/estado inesperado.
- Dominio: revocado antes que expirado, sin expiración, pasado, futuro y límite
  exacto con offset horario.
- Diseño: widgets a 320×568, 360×800 y 390×844, escala de texto 2, sin overflow.
  Regresiones de Auth existentes incluidas. También se inspeccionaron capturas
  del inicio y wallet a 390×844 con fixtures sintéticos, fuera del código de
  producción. Las capturas del harness de tests no validan fuentes/iconos del
  dispositivo.

Estas pruebas no verifican RLS en un servicio real. No se ha ejecutado una prueba
contra Supabase local/remoto en esta fase ni una prueba manual en dispositivo.
El test de integración local de Auth sigue siendo opt-in.

## Pendiente

Paginación más allá de los 50 registros visibles, edición de perfil, categorías,
detalle, PDF/Storage, QR/escáner, emisión, verificación pública y blockchain.
La autorización institucional para emitir requiere otra fase: la RLS vigente
no exige que la institución esté aprobada (`verification_status = verified`
en el esquema real). Esta fase no incorpora ninguna operación de escritura.
