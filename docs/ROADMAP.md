# Estado y próximos pasos

Revisado el **30/10/2026**. Este documento describe el estado actual; las cronologías de implementación se conservan en Git.

## MVP implementado

| Capacidad | Estado |
|---|---|
| Auth, perfil, wallet y detalle | Implementados; registro, sesión y aislamiento entre cuentas |
| Administración institucional | Alta y aprobación administradas; roles y protección del último owner |
| Emisión y PDF privado | Backend autorizado, validación, SHA-256 exacto, idempotencia y recuperación |
| Verificación pública | Código/enlace/QR, proyección limitada y comparación local de PDF |
| Blockchain | Contrato v1, firma backend, ledger durable, anclaje y evidencia pública |
| Apertura documental | Acceso Auth y comprobación local del compromiso sin publicar hash/salt |
| Revocación | Decisión SQL irreversible, worker EVM, progreso y reautorización explícitos |
| Aceptación 10E | Cerrada para Web/Chrome/Supabase local/Anvil; CI observada correcta |

El antiguo pendiente de CI de 10E está **resuelto**: los cinco workflows del commit `3c892cde3d0d21316089b2f8b6bb94702ca6f36a` terminaron correctamente el 30/10/2026. [Evidencia y límites](PHASE10_ACCEPTANCE.md). La aceptación no equivale a lanzamiento público ni acredita cambios posteriores a ese SHA.

## Trabajo que sigue siendo relevante

1. **Producto y acceso:** recuperación de contraseña, enlaces de confirmación y onboarding institucional de autoservicio con aprobación real. No ofrecer roles administrativos en el registro.
2. **Experiencia:** paginación más allá del límite actual de 50 certificados, historial útil y revisión humana de accesibilidad y teclado.
3. **Plataformas:** aceptación completa de la app Android y estabilización de sus diálogos de archivos; iOS, Firefox y Safari con evidencia propia. Compilar Android no acredita ese recorrido.
4. **Operación alojada:** configuración y despliegue explícitos en un entorno separado, backups/restore, gestión de claves, rotación y monitorización sin PII.
5. **Testnet:** despliegue autorizado en Sepolia, configuración del emisor y validación de confirmaciones/finalidad PoS; Anvil no sustituye esa evidencia.
6. **Preparación para tráfico público:** protección de ingress y equidad del presupuesto, carga/concurrencia, política de retención y tratamiento de documentos maliciosos.

## Límites vigentes

- La recuperación de contraseña sigue deshabilitada; los proveedores sociales no están configurados.
- El presupuesto público global 60 POST/60 s es un control de demo y puede agotarse para todos los usuarios.
- El gateway de Supabase puede omitir `Cache-Control` en rechazos JWT genéricos anteriores al handler. Se conserva únicamente la excepción limitada de [SECURITY](SECURITY.md#excepción-del-gateway-jwt); no se declara corregido el proveedor.
- Blockchain prueba el estado de un registro y un compromiso, no la verdad académica, la acreditación de una institución o la identidad del presentador.
- Cámara SKIP/NOT_RUN: «Omitidas por instrucción del usuario; no hay cámara física disponible». No bloquea las siguientes tareas ni reabre la aceptación Web. Se mantienen códigos manuales, enlaces, QR estático, PDF, Auth, SQL y EVM.

## Priorización

Cerrar una necesidad demostrable del MVP antes de añadir plataformas o abstracciones. Conservar `mobile/`, `supabase/`, `blockchain/` y `docs/`, dominio independiente e infraestructura detrás de contratos. Evitar NFT, pagos, multichain, transferencias y rediseños sin un caso de uso concreto.
