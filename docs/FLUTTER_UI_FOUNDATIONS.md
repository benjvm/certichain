# Fundamentos visuales Flutter — Fase 4D

## Referencia inspeccionada

[Figma · CertiChain](https://www.figma.com/design/XRk4TDOeU4yZwBHIRBRXJ6/CertiChain)
es la referencia visual de esta fase. El wireframe original se conserva en
`docs/ChatGPT Image Sep 20, 2026, 09_00_47 PM.png`; no hay
`docs/certichain-wireframe.png`.

| Pieza | Nodo Figma | Evidencia |
|---|---|---|
| Inicio estudiante | 4:100 | Contexto completo y captura |
| Mis certificados | 4:135 | Contexto completo y captura |
| Detalle | 4:176 | Contexto completo y captura |
| Mi perfil | 5:219 | Estructura completa y captura en navegador |
| CertificateCard | 3:24 | Contexto completo y variantes de uso en Inicio/wallet |
| StatusBadge | 3:23 | Variantes Válido, Revocado y Pendiente |
| AppButton | 3:12 | Inventario Primary/Outline/Danger/Ghost; Primary incluido en contexto de detalle |
| AppBottomNavigation | 3:30 | Contexto incluido en Inicio/wallet |

El conector alcanzó el límite del plan Starter durante la inspección. No se
obtuvo el contexto completo independiente de Mi perfil ni el catálogo completo
de variables/estilos. Se revisó Mi perfil en el navegador con el nodo seleccionado;
sus geometrías proceden de metadata, y sus fundamentos compartidos de los
contextos completos. Esta limitación impide afirmar una auditoría exhaustiva
de todas las variantes o tokens del archivo. No se modificó Figma.

## Valores comprobados y componentes incorporados

Los valores se centralizan en `mobile/lib/app/theme/`.

| Fundamento | Valor o composición |
|---|---|
| Primario / superficie / fondo | #4F5FFF / #FFFFFF / #F8F9FC |
| Fondo primario / borde | #EEF0FF / #E4E7EC |
| Cabeceras | #0E1950, añadido como inkBlue |
| Texto principal / secundario | #101828 / #667085 |
| Familia | Inter, pesos 400/500/600/700 |
| Saludo / cabecera / tarjeta | 21 bold / 17 semibold / 15 semibold |
| Sección / caption / navegación | 16 semibold / 12 / 11 medium |
| Margen horizontal | 24, frente a 20 en la especificación anterior |
| Tarjeta / total / acceso / botón | Radios 12 / 16 / 13 / 12 |
| Accesos en referencia | Dos columnas, separación horizontal 10, mínimo 100 de alto |
| Navegación / botón | Mínimos 70 / 48; crecen con texto |
| Placeholder de diploma | Ancho máximo 280, mínimo 200 de alto |

`AppTopBar` adapta su altura al texto y comparte volver/actualizar.
`AppBottomNavigation` usa icono y texto, estado seleccionado y áreas seguras.
`AppButton` conserva carga/deshabilitado y añade Outline/Ghost con uso real
en compartir pendiente/cerrar sesión; el primario es plano como en Figma.
No se construyen variantes destructivas sin un flujo que las necesite.

`CertificateCard` comparte composición compacta, emisor opcional, fechas,
insignia y acción de detalle. `StatusBadge` comunica con palabra, icono y color.
`CertificatePreview` preserva el espacio del diploma con ausencia explícita.
`ReadLoading`, `ReadEmpty` y `ReadError` comparten panel y jerarquía.

No se encontraron imágenes estáticas en los contextos obtenidos de estas vistas:
el diseño usa formas y glifos de texto para iconos/avatar/diploma. Se usa la
familia Material outlined/rounded ya incluida en Flutter, centralizada en
`AppIcons`, en lugar de glifos ambiguos. No se añade Lucide ni otro paquete.
Los iconos informativos tienen texto/semántica; los decorativos acompañan texto.

Inter 4.1 está empaquetada localmente (aproximadamente 1,6 MiB), sin red en
ejecución ni dependencia google_fonts. Procedencia:
[release oficial](https://github.com/rsms/inter/releases/tag/v4.1).
Licencia SIL OFL incluida en `mobile/assets/fonts/Inter-LICENSE.txt`;
mantenimiento mediante actualización deliberada de estos assets.
Roboto/Arial y la fuente de plataforma actúan como alternativas.

## Adaptaciones al contrato real y accesibilidad

- Las cuatro categorías de Figma se reducen a «Todos», sin filtros ficticios.
- El emisor puede estar oculto por RLS; no se inventa ni se amplían políticas.
- El avatar es genérico, sin foto inventada ni acceso de edición.
- Inicio conserva total exacto, tres recientes y accesos. Añadir/escanear están
  deshabilitados y etiquetados. La navegación conserva tres destinos funcionales.
- El componente inferior de Figma tiene cuatro acciones y marca Certificados
  incluso en algunas otras vistas. Flutter selecciona el destino real y no
  añade un escáner sin implementar.
- Mi perfil conserva ficha y filas reconocibles, con mensajes de no disponibilidad
  que aumentan su altura respecto de los 60 px de referencia. Cerrar sesión
  funciona también como salida de estados de error.
- No hay campo de tipo/categoría en la entidad; detalle muestra el título real.
  La preview y QR ilustrativo de Figma se sustituyen por mensajes explícitos,
  sin simular PDF, enlaces ni información de blockchain.
- Válido significa vigencia presentada por la app. No es una prueba blockchain.
  «Detalles» presenta el ID real; Blockchain/Historial explican datos ausentes.
- El verde #16B364 y rojo #F04438 de Figma se conservan como tokens. Las palabras
  de estado usan tonos más oscuros (#067647 / #B42318) para contraste legible.
  Fechas usan texto secundario, en lugar del terciario claro del diseño.
- Las medidas son mínimos/espaciados, no coordenadas ni alturas rígidas:
  scroll, Wrap y Expanded preservan contenido. A escala de texto ≥1,5 los accesos
  pasan a una columna; la navegación amplía el espacio de Certificados.
  Cabeceras e ID se ajustan a varias líneas; no se reduce la escala del sistema.

## Revisión y alcance

Se revisaron visualmente las cuatro vistas con fuentes/iconos reales en el
harness Flutter a 390×844, 320×568 y texto ×2, incluidos sus contenidos inferiores
por scroll. Las pruebas añaden 360×800 y verifican navegación y ausencia de
overflow. Se corrigieron fuente de cabecera, relleno de accesos y división
de la etiqueta Certificados. No se afirma equivalencia píxel a píxel de Mi perfil
por la limitación del conector ni una prueba manual en dispositivo.

Capturas reproducibles en `mobile/build/phase4d-review/` (ignoradas por Git);
fixtures solo en tests. Comandos en [TESTING.md](TESTING.md).
Datos/permisos y rutas en [STUDENT_WALLET.md](STUDENT_WALLET.md).

Tras 7C, siguen pendientes aprobación institucional por autoservicio,
QR/escáner, compartir, verificación pública, blockchain, revocación,
historial real y notificaciones.

## Emisión institucional y documentos — Fase 7C

Se intentó inspeccionar Figma: metadatos generales accesibles, pantallas
institucionales bloqueadas por el límite de llamadas del plan Starter.
Se usó el collage/wireframe de CERTICHAIN_UI_IMPLEMENTATION.md y sus vistas
«Emitir certificado» y «Certificados emitidos», conservando Inter local, AppTopBar,
AppButton, tokens, tarjetas, separación y estados de lectura. No se bloqueó la
implementación ni se inventó contexto de Figma.

El acceso «Espacio institucional» aparece por membresía real. Selector de
institución, nombre, rol y estado proceden de RLS. Se mantiene la navegación
personal. El formulario de tres pasos usa «ID del titular» con pegar/UUID y ayuda
de consentimiento; no simula emails, búsqueda de estudiantes, programas o tipos
ausentes. La expiración muestra su interpretación UTC. Solo Confirmar permite
emitir. En espera hay texto honesto y botones bloqueados, sin porcentaje.
El resultado presenta el ID y lleva al listado, sin detalle personal indebido.

Listas muestran título, fecha, vigencia y referencia corta, límite 50 visible,
carga/vacío/error/reintento. No se inventa el nombre del titular ni una acción
de revocar. Documento disponible ofrece descarga; legado/ausente tiene mensaje
explícito sin previsualización ficticia. Los ID largos son seleccionables y se
ajustan; scroll y Wrap mantienen acciones accesibles en 390×844, 360×800 y
320×568 con texto ×1/×2. Capturas con Inter real en
mobile/build/phase7c-review/ (ignoradas); resultados en [TESTING.md](TESTING.md).

## Pantalla pública y QR — 8B

Se conserva Inter local, AppTheme/tokens, AppTopBar, AppButton y ReadLoading.
Se revisaron la captura de detalle Figma 4:176 y el collage original: el QR
ilustrativo se sustituye por un enlace real; no hay preview de PDF ni prueba
blockchain inventada. La pantalla pública conserva cabecera, espacios y tarjeta
de resultado, sin navegación privada de estudiante.

Formulario con UUID, foco/teclado, carga, resultado y errores separados.
Resultados con palabra e icono además de color; verde oscuro de tokens para
vigencia. Fechas UTC explicadas y código seleccionable. Verificar, Actualizar
comprobación y Consultar otro código son explícitos y alcanzables por scroll.
Estados y confirmación de copia son regiones semánticas vivas.

Panel del detalle con QR negro/blanco, máximo 280 px, zona libre de cuatro
módulos, código/enlace seleccionables y confirmación de copia. Se elimina con
cambios de sesión o al salir. Sin hoja nativa, QR ficticio o detalles técnicos
en el producto.

Pruebas con Inter: 320×568, 360×800, 390×844 y 1280×900, texto ×1/×2, sin overflow
y acciones alcanzables. Capturas Chrome reales a 390×844 revisadas en
mobile/build/public-verification-e2e/public-390.png y share-390.png; QR
decodificado independientemente. No se afirma auditoría con lectores de
pantalla ni revisión en dispositivos físicos. Este apartado sustituye los
pendientes QR/compartir/verificación pública históricos de 4D/7C. Escáner y
comparación de copia quedan en 8C.
