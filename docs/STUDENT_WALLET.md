# Wallet personal y detalle — Fases 4D y 7C

## Navegación y datos reales

Después de autenticar, `/` contiene los destinos internos
`AuthenticatedSection.home/wallet/profile`: Inicio, Mis certificados y Mi perfil.
Atrás desde wallet/perfil vuelve a Inicio. Las rutas públicas `/`, `/login` y
`/register` conservan su comportamiento cuando no hay sesión.

Inicio presenta nombre y rol de `profiles`, avatar genérico, total exacto y
tres certificados recientes. Wallet muestra hasta 50 registros ordenados por
`issued_at DESC, id DESC`, e indica el límite si el total lo supera. Solo hay
«Todos»: el esquema no tiene categorías. Mi perfil muestra los datos reales y
opciones explícitamente no disponibles; cerrar sesión sigue funcionando.
No se usan fixtures en producción ni se conceden permisos por el rol mostrado.

Una tarjeta de Inicio o wallet abre `/certificates/detail` con un ID como
argumento y el titular de la sesión. Es una ruta interna, sin deep links.
El detalle vuelve al destino y desplazamiento originales; se evita abrir dos
detalles por pulsaciones consecutivas. Renovar el token del mismo usuario
conserva la ruta. Cambiar de identidad o salir sustituye todo el navegador.

## Lecturas y autorización

- Perfil: `profiles.select(id,full_name,role).eq(id, userId).maybeSingle()`.
  Un perfil ausente muestra error/reintento y permite salir.
- Wallet: selección mínima de `id, holder_id, institution_id, title, issued_at,
  expires_at, status` y relación opcional `institutions(name)`, filtro de
  `holder_id`, límite 50 y `count=exact`.
- Detalle: `CertificateRepository.readCertificate(userId, certificateId)`;
  el adaptador reutiliza la selección y mapeo de wallet, filtra tanto `id`
  como `holder_id`, y usa `maybeSingle()`. Un resultado sin fila significa
  «No existe o no tienes acceso», sin distinguir casos que permitan enumeración.
  Titular/ID inesperados y estados desconocidos fallan de forma segura.
- Se conserva el cliente con clave pública y sesión del usuario; RLS es la
  autorización efectiva. El filtro de titular sigue siendo obligatorio para
  cuentas que también puedan leer datos institucionales o administrativos.
- RLS puede ocultar `institutions`: ser titular no concede acceso al emisor.
  Se muestra «Institución no disponible» sin descartar el certificado.
- No se consultan rutas de documentos, hashes, códigos de credencial, correos,
  transacciones ni historiales. 7C añade un endpoint PDF separado; las selecciones
  y políticas de lectura personal permanecen intactas.

Las lecturas del adaptador tienen timeout de 20 segundos. Los mensajes de error
son fijos y seguros; no se presentan errores crudos del proveedor.

## Detalle y significado de los estados

El detalle relee el certificado en lugar de considerar la tarjeta una fuente
actualizada. Presenta título, emisor opcional, emisión, expiración opcional y
vigencia. Si no hay expiración, indica «Sin fecha de expiración».
7C consulta la disponibilidad autorizada del documento. Si está disponible
ofrece «Descargar PDF»; cada pulsación solicita una capacidad nueva de 60 segundos.
Un certificado histórico sin documento conserva un estado de ausencia explícito.
No se simula una vista previa. Los errores y la sesión caducada se gestionan sin
exponer respuestas crudas. Chrome descarga un Blob temporal y Android/iOS usan
guardado nativo; no se navega ni se persiste la URL firmada.

«Detalles» muestra el ID real. «Blockchain» muestra «Sin datos de blockchain»;
«Historial» explica que el backend todavía no lo proporciona. Compartir está
deshabilitado y QR/verificación pública se señalan como pendientes. No hay hashes,
bloques, enlaces ni códigos inventados.

La entidad deriva la vigencia: revocado prevalece sobre expiración; active con
`expires_at <= ahora` se muestra «Expirado»; el resto, «Válido». Este estado no
acredita verificación blockchain y la UI lo explica. Fechas locales `dd/MM/yyyy`,
instantes comparados con su zona horaria. La hora del dispositivo sirve solo
para presentación; la verificación autoritativa requerirá el backend.

## Estados y ciclo de vida

Perfil y wallet conservan carga, error y reintento independientes. Un fallo
no se interpreta como lista vacía ni total cero. El detalle añade carga,
ausencia/inaccesibilidad y error/reintento. Los nuevos futuros ocultan datos
anteriores durante la lectura y descartan respuestas sustituidas.

Wallet y detalle actualizan la vigencia con temporizadores de expiración.
Actualizar datos o volver al primer plano relee el recurso correspondiente;
no hay Realtime. La revocación externa se refleja al recargar.
El navegador ligado a identidad/estado Auth destruye rutas, futuros visibles
y temporizadores al cambiar de cuenta o salir. No hay caché persistente adicional.

## Verificación

Desde `mobile/`:

```powershell
dart format lib test
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Cobertura funcional:

- Navegación al detalle desde ambos orígenes y regreso.
- Lectura fresca, carga, ausencia, error seguro y reintento; campos opcionales,
  revocación y expiración; pestañas explícitas y compartir deshabilitado.
- Renovación de token, reanudación, respuestas sustituidas y respuesta tardía
  tras cambio de usuario o salida.
- Selección mínima y filtros de titular/ID con SDK real y HTTP loopback simulado;
  ausencia, emisor oculto y rechazo de identidad/estado inesperados.
- Regresiones existentes de Auth, perfil y wallet.

Se inspeccionaron capturas de las cuatro pantallas a 390×844, 320×568 y texto ×2.
Las pruebas incluyen también 360×800 y 320×568 con texto ×2, con Inter e iconos
Material cargados. Los campos inferiores y cerrar sesión siguen accesibles por
scroll. Las capturas usan fixtures sintéticos exclusivos de tests.
Véase [FLUTTER_UI_FOUNDATIONS.md](FLUTTER_UI_FOUNDATIONS.md) y [TESTING.md](TESTING.md).

Estas pruebas no prueban RLS en un Supabase real ni equivalen a una revisión en
dispositivo físico. El test local de Auth sigue siendo opt-in.

Resultado ejecutado el 28/09/2026: formato sin cambios pendientes, análisis sin
incidencias, 68 pruebas superadas y 1 omitida (integración opt-in de Supabase local).
`flutter build web` también completó correctamente. Las 14 pruebas del detalle
y las 2 nuevas del adaptador están incluidas en ese total.

## Pendiente

Paginación completa, categorías, edición/configuración de perfil,
QR/escáner, compartir, autoservicio de aprobación institucional, revocación
desde la app, notificaciones, verificación pública y blockchain.

4D no añadió escrituras. La Fase 5 posterior conserva sus políticas SELECT y
selecciones de wallet/detalle, y cierra INSERT/UPDATE y demás escrituras directas
de certificados mediante grants y RLS, también para `platform_admin` y para
instituciones `verified`. Sus pruebas SQL verifican esas lecturas efectivas;
no habilita emisión, revocación ni acceso al PDF. El backend futuro deberá
cumplir [SECURE_ISSUANCE.md](SECURE_ISSUANCE.md).

## Facetas de titular e institución en 7C

Mi perfil incorpora «Copiar mi ID de titular» para perfiles holder. El estudiante
comparte voluntariamente ese UUID con la institución; no comparte credenciales
ni concede acceso a su perfil. La institución lo pega como ID, nunca como email.
La elegibilidad sigue siendo comprobada por el backend; no hay búsqueda global.

Una membresía real añade «Espacio institucional» sin sustituir los tres destinos
personales. Listado y formulario se filtran por la institución seleccionada y
su rol/estado real. Registrar la preferencia Institución no concede membresías
ni cambia la autorización. El detalle personal sigue filtrando holder_id aun
cuando esa cuenta sea emisora; el éxito de emisión abre el listado institucional.

La nueva descarga comprueba completed, objeto e integridad en servidor: el titular
conserva acceso aunque se suspenda la institución. Owner/admin/issuer actuales
de una institución emisora verified pueden descargar desde su listado. Un
platform_admin sin esa condición no obtiene el PDF. La consulta de disponibilidad
no guarda capacidades y cada descarga vuelve a autorizar. Una capacidad ya
entregada puede usarse hasta su vencimiento, incluso tras una baja de membresía.

La navegación destruye borradores/URLs visibles ante cambio de cuenta o 401.
Solo hay recibos mínimos de emisión pendientes separados por identidad;
recuperación y límites en [SECURE_ISSUANCE.md](SECURE_ISSUANCE.md).
Pruebas locales actuales y limitaciones de dispositivos en [TESTING.md](TESTING.md).
