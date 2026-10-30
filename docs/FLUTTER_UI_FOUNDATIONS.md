# Fundamentos visuales Flutter

La fuente de implementación es `mobile/lib/app/theme/` y los widgets compartidos. [Figma · CertiChain](https://www.figma.com/design/XRk4TDOeU4yZwBHIRBRXJ6/CertiChain) conserva la referencia visual; datos, permisos y capacidades reales prevalecen sobre ilustraciones o acciones de un diseño.

## Tokens y componentes

| Fundamento | Valor / fuente |
|---|---|
| Primario, superficie y fondo | #4F5FFF, #FFFFFF, #F8F9FC |
| Fondo primario y borde | #EEF0FF, #E4E7EC |
| Cabecera, texto principal y secundario | #0E1950, #101828, #667085 |
| Tipografía | Inter local, pesos 400/500/600/700 |
| Margen horizontal | 24 |
| Radios de tarjeta/total/acceso/botón | 12/16/13/12 |
| Botón / navegación | Alturas mínimas 48/70, ampliables con texto |

Los colores de estado usan texto/icono además de color, con tonos de texto oscuros #067647/#B42318. Las medidas son mínimos y espaciados, no coordenadas rígidas. Scroll, Wrap y Expanded conservan acciones a 320 px y texto ×2; nunca reducir la escala del sistema para ocultar overflow.

`AppTopBar`, `AppBottomNavigation`, `AppButton`, `CertificateCard`, `StatusBadge`, `ReadLoading`, `ReadEmpty` y `ReadError` centralizan composición, jerarquía y estados. Iconos Material centralizados en `AppIcons`, con semántica para información y sin etiquetas redundantes para decoración.

Inter 4.1 se empaqueta en `mobile/assets/fonts/` con licencia SIL OFL. No se descarga tipografía en ejecución. La familia/fallbacks y espaciado viven en el tema; una actualización de assets requiere revisar licencia y regresiones visuales.

## Referencias de diseño útiles

| Vista / componente | Nodo Figma |
|---|---|
| Inicio / wallet / detalle / perfil | 4:100 / 4:135 / 4:176 / 5:219 |
| CertificateCard / StatusBadge | 3:24 / 3:23 |
| AppButton / navegación | 3:12 / 3:30 |

La inspección original tuvo alcance limitado por el plan del conector; no acredita equivalencia píxel a píxel de todo Figma. Una revisión futura debe consultar el diseño vigente y comprobar sus cambios, en vez de asumir que la captura histórica sigue actual.

## Comportamiento de producto

- Formularios con autofill/foco/Next/Done, validación compartida, visibilidad de contraseña, carga y protección de doble envío. Registro en dos pasos; la preferencia institucional no concede privilegios. No mostrar proveedores sociales o recuperación funcional sin implementarlos.
- Inicio conserva tres certificados recientes, total exacto y navegación real. Wallet muestra el límite de 50; sin categorías ficticias, fotos inventadas o nombre de emisor oculto por RLS.
- «Espacio institucional» deriva de membresía real. La emisión usa ID voluntario de titular, título y fechas; tres pasos y confirmación. Sin búsqueda de alumnos/email o programas no existentes.
- Revocación muestra certificado/ámbito y confirmación explícita; motivo privado, cancelación y recuperación de la misma clave. Progreso manual sin porcentajes o confirmación EVM simulados.
- Detalle distingue registro CertiChain, evidencia issue/revoke, integridad de mi copia y validez de la apertura. Anvil no se presenta como finalidad PoS. Evidencia previa conserva etiqueta, fuente y fecha.
- PDF y apertura se obtienen por acción explícita. No ofrecer preview ficticia. QR negro/blanco, máximo 280 px, margen de cuatro módulos, únicamente enlace/código públicos. Texto e IDs largos seleccionables y ajustables.
- Resultado, carga y errores con regiones semánticas; foco visible y acciones alcanzables. Sin contenido privado retenido tras cambio de sesión.

## Verificación y límites

Widgets/layouts comprueban 320×568, 360×800, 390×844 y tamaños amplios, texto aumentado, teclado y ausencia de overflow. [Comandos](TESTING.md). Semántica automática no sustituye revisión humana con teclado/lector de pantalla ni dispositivos físicos.

Cámara SKIP/NOT_RUN por instrucción del usuario; se conservan alternativas manuales y pruebas de QR estático, PDF y navegación. [Estado de plataformas](PHASE10_ACCEPTANCE.md#límites-y-pendientes-reales).
