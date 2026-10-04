# CertiChain — Especificación de interfaz Flutter v1

> Documento de trabajo para Codex. Referencia visual: `ChatGPT Image Sep 20, 2026, 09_00_47 PM.png` (wireframe de 15 vistas). Coloca una copia en `docs/certichain-wireframe.png` dentro del repositorio y ajusta esta ruta si cambia. La imagen manda en composición y jerarquía; este documento fija medidas, comportamiento y consistencia cuando la imagen no da suficiente detalle.

> Actualización 4D: el original se encuentra en `docs/ChatGPT Image Sep 20, 2026, 09_00_47 PM.png`.
> Para las cuatro pantallas de esta fase, la referencia visual es ahora
> [Figma · CertiChain](https://www.figma.com/design/XRk4TDOeU4yZwBHIRBRXJ6/CertiChain).
> Las migraciones/RLS y los repositorios fijan datos y permisos. El inventario
> completo de este documento es futuro, no el alcance entregado. Las diferencias
> comprobadas y su adaptación están en [docs/FLUTTER_UI_FOUNDATIONS.md](docs/FLUTTER_UI_FOUNDATIONS.md).

## 1. Encargo para Codex

Construye la interfaz móvil de CertiChain en el proyecto Flutter existente en `certichain/mobile/`, siguiendo el wireframe adjunto con la mayor fidelidad práctica posible. Implementa primero los fundamentos y widgets compartidos, después las pantallas y finalmente la navegación y los estados. Usa los nombres de dominio y convenciones de `AGENTS.md`, `README.md`, `docs/` y la migración Supabase existente como fuente de verdad para datos, roles y permisos. No alteres migraciones ni inventes esquemas. Si este documento discrepa del contrato de datos real, conserva el contrato real y documenta la adaptación de UI.

La interfaz visible estará en español. La marca dice **CertiChain** y el subtítulo del wireframe es «Tus logros, verificados en blockchain». En 4D se inspecciona Figma antes de modificar la interfaz. La imagen es una referencia visual, no un paquete de assets listos para producción.

### Entregables

1. Tema y tokens centralizados; tipografía Inter y familia de iconos coherente.
2. Widgets reutilizables con estados de carga, vacío, error y deshabilitado donde corresponda.
3. Las 15 vistas del inventario, con navegación funcional y datos de demostración claramente separados de servicios reales.
4. Diseño adaptable a tamaños pequeños y grandes, sin desbordamientos, y semántica accesible.
5. Un breve registro de pantallas terminadas, rutas, decisiones y funciones aún simuladas.

No presentes una emisión, revocación o verificación blockchain simulada como una operación real. Si todavía no existe la integración, etiqueta inequívocamente la demostración en el entorno de desarrollo y deja una interfaz de servicio sustituible.

## 2. Lectura del wireframe

El collage presenta teléfonos blancos con bordes finos, mucho espacio en blanco, azul índigo para acciones primarias, verde para verificación válida y rojo para fallo/revocación. La cabecera usa marca compacta; los paneles principales usan tarjetas ligeras, contornos discretos y navegación inferior. El escáner tiene fondo oscuro y un marco central blanco. El resultado válido tiene un fondo verde muy pálido; el inválido, rojo muy pálido.

| Nº | Vista de referencia | Contenido y jerarquía que se debe preservar |
|---|---|---|
| 1.1 | Bienvenida | Logotipo centrado, subtítulo, ilustración de certificado protegido, indicador de tres páginas, botón «Comenzar» abajo. |
| 1.2 | Beneficios | Título «Verifica la autenticidad de tus certificados con blockchain», lista de cinco beneficios con iconos y «Siguiente». |
| 1.3 | Wallet en un solo lugar | Ilustración superior de persona/certificados, título, CTA «Crear cuenta» y acción secundaria «Iniciar sesión». |
| 2.1 | Inicio de sesión | Marca arriba, título y descripción, email y contraseña, recuperar contraseña, CTA, separador, acceso social y registro. Solo mostrar acceso social si está configurado realmente. |
| 2.2 | Registro | Marca, título, selección de rol en filas azul/morado/verde, nombre, email y «Continuar». Completar el flujo de registro conforme al backend real. |
| 3.1 | Inicio estudiante | Saludo con avatar, tarjeta de total de certificados, cuadrícula 2×2 de accesos rápidos, certificados recientes, navegación inferior. |
| 4.1 | Mis certificados estudiante | Volver y título, chips de categoría, tarjetas verticales con icono/avatar, título, entidad, estado y fecha, navegación inferior. |
| 5.1 | Detalle del certificado | Previsualización del diploma arriba, título/tipo/emisor, estado y fechas, QR, botón de compartir, pestañas «Detalles», «Blockchain», «Historial». |
| 6.1 | Escanear QR | Pantalla oscura, título arriba, visor central con esquinas blancas, guía breve y acción «Cancelar». |
| 7.1 | Resultado positivo | Fondo suave verde, icono circular de aprobación, «Certificado válido», tarjeta de datos y pruebas, CTA «Ver certificado completo», compartir y consultar historial. |
| 7.2 | Resultado negativo | Fondo suave rojo, icono de error, «Certificado no válido», tarjeta con causa concreta y detalles disponibles, «Ver detalles» y «Intentar de nuevo». |
| 8.1 | Emitir certificado | Formulario institucional de tres etapas «Datos / Documento / Confirmar»; primera etapa busca estudiante y recoge tipo, nombre y fecha. |
| 9.1 | Certificados emitidos | Lista institucional, pestañas «Emitidos / Revocados», entradas con alumno, programa, referencia, estado y fecha. |
| 10.1 | Revocar certificado | Diálogo de confirmación sobre el listado/detalle, resumen del certificado, efecto de la acción, campo o motivo si el dominio lo requiere, «Cancelar» y «Revocar». |
| 11.1 | Escáner verificador | Variante oscura del escáner, texto «Escanea un código QR para verificar un certificado» y acceso al historial. |
| 12.1 | Resultado verificador | Versión compacta de resultado válido con datos, prueba y botón «Ver detalles». |
| 13.1 | Mi perfil | Cabecera, ficha de usuario y rol, filas «Información personal», «Seguridad», «Notificaciones», «Configuración» y navegación. |
| 14.1 | Historial de verificaciones | Lista cronológica con tipo, referencia, fecha/hora y estado; detalle al pulsar. |
| 15.1 | Notificaciones | Lista con iconos según evento, texto breve, fecha/hora, lectura/no lectura y navegación. |

Los números 1 a 15 son secciones del collage; algunas secciones contienen varias vistas. Mantén el patrón común aunque el wireframe use datos de ejemplo diferentes en cada pantalla.

## 3. Tokens visuales

Implementar en `lib/core/theme/` (o ubicación equivalente que ya use el repositorio), sin colores, radios o estilos de texto dispersos por pantallas. Los colores siguientes proceden de la especificación del proyecto y guían la aproximación al wireframe.

| Token | Valor | Uso |
|---|---|---|
| `brandPrimary` | `#4F5FFF` | CTA y navegación activa |
| `brandPrimaryDark` | `#3947E8` | Estado pulsado |
| `brandPrimaryLight` | `#EEF0FF` | Fondo de acento |
| `brandSecondary` | `#7657FF` | Institución |
| `success` / `successLight` | `#16B364` / `#ECFDF3` | Válido |
| `error` / `errorLight` | `#F04438` / `#FEF3F2` | Inválido y revocado |
| `warning` / `info` | `#F79009` / `#2E90FA` | Aviso / información |
| `background` / `surface` | `#F8F9FC` / `#FFFFFF` | Fondo / tarjetas |
| `border` | `#E4E7EC` | Separaciones y contornos |
| `textPrimary` / `textSecondary` / `textTertiary` | `#101828` / `#667085` / `#98A2B3` | Jerarquía textual |
| `disabled` | `#D0D5DD` | Acciones inactivas |
| `studentAccent` / `institutionAccent` / `verifierAccent` | `#4F5FFF` / `#7657FF` / `#16B364` | Acentos puntuales por rol |
| `institutionLight` | `#F3F0FF` | Fondo puntual del rol |

Inter: `Display 32/40 700`, `H1 28/36 700`, `H2 24/32 700`, `H3 20/28 600`, `Title 18/26 600`, `BodyLarge 16/24 400`, `Body 14/20 400`, `BodyMedium 14/20 500`, `Label 13/18 600`, `Caption 12/16 400`, `Tiny 10/14 500`. Formato: tamaño/interlineado/peso. Ajustar escalado de texto del sistema; no fijar altura que corte textos.

Espaciado: `0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64`. Padding horizontal de pantalla `20`; separación de elementos relacionados `8–12`; interior de tarjetas `12–16`; secciones `24–32`. Radios `4, 8, 12, 16, 20, 24, 999`; botones y campos `12`, tarjetas `12–16`, diálogo `20`, pastillas `999`. Alturas de botón `36/44/48`; objetivo táctil mínimo `44×44`. Iconos de una sola familia de trazo fino, preferiblemente Lucide si ya está disponible; tamaños `16/20/24/28/32`. Si introducir la dependencia complica el entorno, usa Material Symbols Rounded de forma consistente.

Sombras discretas: nivel 0 ninguna; nivel 1 `0 1 3 rgba(16,24,40,.08)`; nivel 2 `0 4 12 rgba(16,24,40,.10)`; nivel 3 `0 12 32 rgba(16,24,40,.16)`. Prioriza bordes ligeros. Gradientes suaves índigo solo en botones primarios y superficies destacadas que aparecen en el wireframe; las pantallas ordinarias siguen blancas.

Diseño base `390×844` como referencia visual, no como tamaño fijo. `SafeArea`, anchuras flexibles, scroll vertical, teclado sin tapar CTA; comprobar al menos `360×800`, `390×844` y texto ampliado. El contenido de tarjetas se adapta al ancho disponible. Evita situar elementos por coordenadas absolutas excepto overlay del escáner.

## 4. Arquitectura de widgets

Usa la arquitectura de carpetas vigente. Si no existe, organiza por `core/theme`, `core/widgets`, `features/auth`, `features/student`, `features/institution`, `features/verification`, `features/profile` y `features/notifications`, separando presentación, modelos y servicios cuando haya integración real.

| Widget | Contrato visual y estados |
|---|---|
| `AppButton` | Primary, secondary, outline, ghost, danger; small/medium/large; enabled, pressed, loading, disabled. Un CTA primario por pantalla. |
| `AppTextField` | Label, hint, prefijo/sufijo, helper/error; contraseña ocultable; validación textual accesible. |
| `AppTopBar` | Volver, título y acción opcional; mismos márgenes en todas las vistas internas. |
| `AppBottomNavigation` | Items configurados por rol; icono y etiqueta; estado seleccionado, persistencia de pestañas cuando convenga. |
| `StatusBadge` | Válido, revocado, expirado, pendiente, inválido: icono + palabra + color. |
| `CertificateCard` | Compacta y estándar: credencial, emisor, titular cuando corresponda, estado y fecha; navegación a detalle. |
| `CertificatePreview` | Previsualización o placeholder creíble del diploma; no simular un PDF real si no existe. |
| `VerificationResultCard` | Datos del certificado, motivo de validación/fallo y prueba disponible. No mostrar «hash coincide» sin prueba real. |
| `ScannerOverlay` | Marco de esquinas blancas sobre cámara, instrucción y salida; permiso denegado y cámara no disponible. |
| `EmptyState`, `ErrorState`, `LoadingState` | Mensaje específico, reintento si procede, skeleton en listas; evita pantallas en blanco. |
| `ConfirmActionDialog` | Resumen y consecuencia de revocación, cancelación explícita y confirmación destructiva. |

Los componentes específicos (`CertificateBlockchainInfo`, `VerificationHistoryItem`, `QuickActionCard`, `NotificationItem`, `RoleSelector`, indicador de pasos) usan los mismos tokens. Un certificado debe tener un único modelo de presentación normalizado: `id`, título, tipo, titular, emisor, fecha, expiración opcional, estado y referencias de verificación opcionales. Adapta los nombres a la base real; nunca rellenes una propiedad desconocida con una afirmación falsa.

## 5. Navegación y permisos

- Onboarding → Login / Registro. Tras autenticar, leer rol **confiable** del backend y dirigir al panel correspondiente; no usar la elección local del formulario como autoridad.
- Estudiante: Inicio, Certificados, Escanear, Perfil. Institución: Inicio, Certificados, Emitir, Perfil. Verificador: Inicio, Escanear, Historial, Perfil. La existencia exacta de «verificador» como rol registrable debe confirmarse contra migraciones y políticas; si no existe, ofrecer la verificación pública o el flujo permitido sin crear un rol ficticio.
- Compartir un certificado abre la hoja nativa solo con enlace/QR verificable cuando exista. Si no existe, muestra estado no disponible o una demo marcada, sin inventar URLs públicas.
- Las pestañas «Detalles», «Blockchain», «Historial» solo muestran campos realmente disponibles. Si todavía no hay transacción, indicar «Pendiente de registro» o «Sin datos de blockchain», nunca un hash o bloque inventado.
- Emisión: datos → documento → confirmación/revisión; bloquear doble envío, mostrar progreso y resultado real. Revocación: confirmar y conservar certificado visible con estado revocado. El backend determina permisos, propietario y transiciones válidas.
- Escaneo: solicitar permiso, procesar QR, manejar QR ilegible, desconocido, revocado, expirado, falta de conexión y respuesta pendiente. La lógica de validez debe distinguir integridad del documento, existencia del registro y vigencia/revocación; no declarar válido solo por abrir un QR.

## 6. Estados y microcopy

En listas: carga con skeleton, vacío con explicación y CTA pertinente, error con «Reintentar». En formularios: validación junto al campo y botón ocupado durante petición. En blockchain: preparación, firma si aplica, envío, confirmación, confirmado y fallo solo si el flujo real expone esas fases. Resultado inválido debe explicar la causa comprobada; si no se conoce, «No pudimos verificar este certificado» sin afirmar discrepancia de hash. Acciones destructivas requieren confirmación.

Usar el vocabulario consistente: «Certificados», «Emitir certificado», «Escanear QR», «Verificación», «Válido», «Revocado», «Expirado», «Pendiente». Fechas en formato local español; accesibilidad de contraste, iconos con etiqueta y soporte de lector de pantalla. El color nunca comunica el estado por sí solo.

## 7. Assets y fidelidad

El wireframe incluye logo geométrico, ilustración de onboarding, diploma, avatares y QR. Si el repositorio ya contiene assets de marca, reutilízalos. Si no, reproduce el logotipo mediante SVG/vector propio sencillo y usa ilustraciones provisionales coherentes; documenta cuáles requieren arte definitivo. No recortes el collage para convertirlo en interfaces ni uses QR de muestra como verificable. Las pantallas 1.1 y 1.3 necesitan una ilustración con peso visual similar; si no hay asset, compón una ilustración vectorial simple de certificado y escudo/persona. Mantén la proporción, espacio y orden del wireframe.

## 8. Secuencia de construcción

1. Inspecciona el proyecto Flutter, `AGENTS.md`, estructura y dependencias; examina la imagen a tamaño completo. Comprueba nombres de enums/tablas y funcionalidades disponibles.
2. Crea tokens y `ThemeData`, tipografía e iconos. Define datos de demostración en una sola capa separada si aún no hay API.
3. Construye botones, campos, tarjetas, estados y navegación compartidos; muestra variantes mediante pantallas reales, sin catálogo obligatorio.
4. Implementa onboarding/auth; después estudiante; después verificación; después institución; finalmente perfil, historial y notificaciones.
5. Conecta rutas y acciones. Integra servicios reales disponibles, y marca claramente los flujos que sigan simulados.
6. Ejecuta `dart format`, `flutter analyze` y las pruebas existentes. Comprueba manualmente en emulador o captura cada vista, especialmente overflow, teclado y navegación; corrige diferencias visibles frente al wireframe.

## 9. Criterios de aceptación

### Estado de implementación — Fase 7C

El espacio institucional aparece por membresías reales, independiente del rol
global y preferencia de registro. Mantiene Inicio, Mis certificados y Mi perfil
para esa misma cuenta. Selector de institución, nombre/rol/estado reales y
listado filtrado de hasta 50 certificados; no se lee el nombre del titular ajeno.
Emisión usa Datos → Documento → Confirmar con UUID de titular compartido
voluntariamente, PDF único y resumen. No hay búsqueda de emails, porcentaje
de subida ficticio ni botón de revocar. La autorización final es del backend.
Éxito 201/200 muestra ID y listado; no abre el detalle personal del emisor.

Mi perfil copia el ID propio; detalle del titular y listado institucional ofrecen
descarga solo tras comprobar documento/autorización. Legados conservan ausencia
explícita; no hay preview falsa. Chrome usa selector HTML y Blob temporal;
Android/iOS selector/guardado nativo. Reintentos mantienen solicitud/clave y los
reinicios requieren reconstrucción exacta. Fuentes, tokens, componentes,
estados y pruebas responsive se documentan en
[docs/FLUTTER_UI_FOUNDATIONS.md](docs/FLUTTER_UI_FOUNDATIONS.md) y
[docs/TESTING.md](docs/TESTING.md). El collage conserva acciones futuras fuera
del alcance: QR, revocación, verificación pública y blockchain.

### Estado de implementación — Fase 4D

Inicio, Mis certificados y Mi perfil comparten Inter local, tokens y componentes
adaptados de Figma. `AppTopBar` y `AppBottomNavigation` preservan tres destinos
reales. Las tarjetas navegables abren `/certificates/detail` y vuelven al origen.
El detalle relee el certificado del titular, muestra título, emisor opcional,
fechas y vigencia; conserva el espacio del diploma con un placeholder explícito.
«Detalles» muestra el ID real; Blockchain e Historial explican la ausencia de
datos. Compartir está deshabilitado, sin QR, PDF, hash ni pruebas ficticias.
Estados, accesibilidad y verificación en [docs/STUDENT_WALLET.md](docs/STUDENT_WALLET.md).

### Antecedente — Fase 4C

Las vistas 3.1 y 4.1 usan perfil y certificados reales mediante repositorios.
El inicio conserva saludo, total, cuadrícula de accesos y tres recientes. La
wallet muestra hasta 50 registros ordenados por emisión y navegación inferior.
La consulta básica de perfil es funcional; su edición está pendiente. Las rutas
internas son `AuthenticatedSection.home/wallet/profile` bajo el área autenticada.

Adaptaciones al esquema/RLS: solo chip «Todos» (sin categorías en el esquema),
emisor opcional con «Institución no disponible», vigencia sin afirmaciones
blockchain, avatar genérico y accesos a escanear/añadir deshabilitados. No hay
pantallas falsas de detalle, PDF o QR. Véase [docs/STUDENT_WALLET.md](docs/STUDENT_WALLET.md).

Los criterios siguientes describen la interfaz completa futura, no el alcance
entregado en 4D.

- Todas las vistas del inventario se pueden alcanzar por una ruta o flujo coherente y volver sin callejones sin salida.
- Onboarding, panel, wallet, detalle, escáner, ambos resultados, emisión, listados y diálogo mantienen composición y jerarquía reconocibles respecto al collage.
- Un cambio en color, espaciado o tipografía principal se realiza en un solo lugar y se refleja en todas las pantallas.
- Las listas comparten tarjeta y badge; los tres roles comparten identidad visual, con acentos discretos.
- Ninguna vista muestra datos blockchain, validación o permisos falsamente reales.
- Carga, vacío, error, ausencia de permiso y acciones deshabilitadas están contemplados donde aplique.
- La app compila, el análisis no introduce errores, no hay overflow en tamaños objetivo y el texto ampliado conserva los CTA esenciales.

### Prompt breve para iniciar la ejecución

> Lee `CERTICHAIN_UI_IMPLEMENTATION.md`, `docs/FLUTTER_UI_FOUNDATIONS.md`, el original `docs/ChatGPT Image Sep 20, 2026, 09_00_47 PM.png` y la documentación de arquitectura y permisos. Inspecciona las vistas pertinentes en Figma antes de editar. Trabaja solo en el incremento solicitado; el inventario completo describe fases futuras. Conserva datos reales, repositorios, RLS y componentes compartidos; etiqueta los flujos pendientes. Al terminar, informa de pantallas, comandos ejecutados y limitaciones concretas.
