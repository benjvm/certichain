# Hoja de ruta del MVP

## Incremento entregado — Fase 4C de implementación Flutter

Inicio autenticado con perfil real, total y certificados recientes; wallet
personal limitada a los 50 más recientes; consulta de perfil y cierre de sesión.
Incluye estados de carga/vacío/error/reintento y aislamiento por sesión.
No equivale a completar la fase de blockchain del roadmap conceptual inferior.
Detalle, permisos y pruebas en [STUDENT_WALLET.md](STUDENT_WALLET.md).

Pendiente: detalles/documentos, paginación completa, QR/verificación, emisión,
aprobación institucional y blockchain. La RLS actual todavía no comprueba que
una institución esté aprobada antes de emitir; no habilitar emisión desde Flutter.

## Fase 0 — Diseño y entorno

- Aprobar requisitos, actores y límites del MVP.
- Crear wireframes y flujo de navegación.
- Aprobar ADR iniciales de Supabase, arquitectura, red y storage.
- Inicializar Flutter, Supabase local, Foundry y CI.

**Salida:** repositorio reproducible, documentación base y pantallas navegables sin lógica real.

## Fase 1 — Identidad e instituciones

- Auth, recuperación y perfiles.
- Instituciones, miembros y aprobación administrativa mínima.
- Políticas RLS y pruebas de aislamiento.

**Salida:** usuarios e instituciones acceden solo a lo autorizado.

## Fase 2 — Certificados sin blockchain

- Migraciones de certificados y tipos.
- Upload privado, validación, SHA-256 y estados.
- Wallet del estudiante y panel de institución.

**Salida:** emisión off-chain completa y segura.

## Fase 3 — Verificación y QR

- URL/código público estable.
- DTO público mínimo.
- QR, escáner y verificación opcional de archivo.
- Rate limit y registro prudente de eventos.

**Salida:** un tercero verifica sin cuenta y detecta un PDF alterado.

## Fase 4 — Blockchain

- Contrato probado en Anvil.
- Despliegue en testnet.
- Edge Function/adaptador, idempotencia y reconciliación.
- UI de pendiente, confirmado y fallo.

**Salida:** emisión anclada y comprobable on-chain.

## Fase 5 — Revocación y endurecimiento

- Flujo de revocación completo.
- Pruebas E2E, seguridad y accesibilidad.
- Observabilidad, recuperación ante fallos y límites.
- Datos y guion de demo reproducibles.

**Salida:** MVP defendible como TFG.

## Fase 6 — Memoria y entrega

- Diagramas definitivos, decisiones y resultados.
- Métricas de pruebas y limitaciones.
- Vídeo/demo y manual de instalación.
- Backlog de evolución: API propia, emisión masiva, identidad verificable, eIDAS.

## Criterio de priorización

Si el calendario se complica, conservar en este orden: verificación, autorización/RLS, emisión segura, QR, blockchain, revocación, extras visuales. No sacrificar seguridad o reproducibilidad para añadir funciones secundarias.
