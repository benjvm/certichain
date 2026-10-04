# ADR-0012 — Navegación Web pública y compartición del código del titular

Fecha: 04/10/2026. Estado: aceptada para 8B local.

## Decisión

MaterialApp.router usa el Router de Flutter y un parser pequeño de `/verify` y
`/verify/<credential_code>`. Conserva la estrategia hash predeterminada de Web.
El navegador privado anterior permanece anidado y se sustituye por estado e
identidad de Auth. El Router delega atrás nativo al navegador privado; el
historial del navegador Web procede de RouteInformation. Auth no reemplaza la
pantalla pública ni provoca una consulta. Logout/cambio de cuenta destruyen
rutas privadas; volver a una URL nunca reconstruye un detalle privado.

main monta CertiChainApp con el repositorio público antes de esperar la
inicialización del SDK. Después actualiza las dependencias del mismo widget,
conservando su State/Router y la consulta. Un fallo de configuración o de
restauración privada permite seguir verificando si SUPABASE_URL es válido.
La API se toma de configuración confiable; nunca de la URL del certificado.

VerificationRepository usa un cliente HTTP independiente, sin SDK, JWT, apikey,
cabeceras de cookies ni callbacks Auth. El dominio es Dart puro. La proyección
v1 se valida cerrada, incluidas fechas y ausencia mínima. ChangeNotifier coordina
envío explícito, single-flight, generaciones, disposición y Retry-After. No se
persisten consultas/códigos ni se realizan polling o reintentos automáticos.

CredentialRepository lee únicamente id, holder_id, credential_code e
issuance_operation_id del certificado propio, con ambos filtros. Captura y
revalida usuario/token/caducidad antes/después del HTTP. El vínculo 7B existente
y sus FK/checks/inmutabilidad distinguen publicaciones de históricos; la
elegibilidad y estado definitivo siguen perteneciendo al endpoint público.
No se leen operaciones técnicas, perfiles ajenos o columnas PDF/hash.

PUBLIC_VERIFICATION_BASE_URL es la base Web; SUPABASE_URL es el backend.
La primera requiere HTTPS salvo loopback HTTP explícito en desarrollo, sin
credenciales, query o fragmento. Construye centralmente `<base>/#/verify/<uuid>`.
Si falta o es inválida, se explica la indisponibilidad de compartir y permanece
la consulta manual. localhost solo funciona en el mismo equipo.

La compartición es un panel en el detalle, propiedad de la ruta privada. Se
elimina al cambiar sesión/token/identidad y al cerrar la ruta. Copia explícita
con mensaje semántico; código y enlace seleccionables. No hay diálogo que pueda
quedar separado del estado privado. QR estable, exclusivamente enlace y UUID;
los bytes del PDF emitido permanecen intactos.

## Alternativas y mantenimiento

Navigator 1 con initialRoute fijo pierde el código y no sincroniza correctamente
historial Web. El Router estándar satisface estas dos rutas sin una dependencia
de routing nueva. La navegación privada existente conserva sus convenciones y
regresiones. Si aumenta el mapa de rutas, revisar la conveniencia de un router
declarativo externo.

qr 4.0.0, fijado en pubspec/lock, genera matriz/corrección de errores; un painter
pequeño pinta módulos negros sobre blanco con zona libre de cuatro módulos.
Flutter no incluye codificador QR y mantener uno propio sería innecesario.
La biblioteca Dart del mantenedor kevmoo tiene release 4.0.0 y soporta Web sin
cámara: [paquete](https://pub.dev/packages/qr),
[fuente](https://github.com/kevmoo/qr.dart). Actualizaciones deliberadas requieren
decodificación independiente y revisión de geometría. jsqr 1.4.0 y pngjs 7.0.0
están fijados con lock npm exclusivamente en tool, nunca en el binario.

No se entregan Universal Links, Android App Links, escáner, comparación de PDF,
blockchain, revocación nueva o despliegue. 8C incluye escáner/comparación; 8D
incluye pruebas integrales y endurecimiento del recorrido completo.
