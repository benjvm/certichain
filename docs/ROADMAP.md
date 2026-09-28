# Hoja de ruta del MVP

## Fases de implementación

Estos incrementos registran entregas reales; su numeración es independiente de
las etapas conceptuales del MVP descritas más abajo.

### Fase 4D — Fundamentos visuales y detalle Flutter (entregada)

Fundamentos visuales basados en Figma, Inter local, cabecera y navegación
compartidas; Inicio con perfil real, total y recientes; wallet de hasta 50
certificados; consulta de perfil y cierre de sesión. Las tarjetas abren un
detalle leído por ID y titular con carga, ausencia/inaccesibilidad, error y reintento.
Se conserva el aislamiento por sesión, incluido el detalle.
No equivale a completar la fase de blockchain del roadmap conceptual inferior.
Alcance, permisos y pruebas en [STUDENT_WALLET.md](STUDENT_WALLET.md).
Referencia y adaptaciones visuales en [FLUTTER_UI_FOUNDATIONS.md](FLUTTER_UI_FOUNDATIONS.md).

Pendiente: acceso al PDF, paginación completa, QR/verificación, emisión,
aprobación institucional, revocación y blockchain. 4D no añadió escrituras.

### Fase 5 — Cierre de autorización y preparación de emisión segura

**Objetivo:** cerrar la emisión y revocación por la API de tablas hasta disponer
de un backend confiable, manteniendo wallet y detalle de 4D.

**Alcance:** Supabase local, grants, RLS, pruebas de integración y documentación.
Se preservan datos, columnas, enums y políticas SELECT. No incluye pantallas,
endpoints, Storage, emisión, QR, verificación pública ni blockchain.

**Entregables:**

- Migración nueva `20260928202802_close_direct_certificate_writes.sql`: elimina
  INSERT/UPDATE de certificados por RLS, retira sus grants de escritura para
  `authenticated`, `anon` y PUBLIC, y conserva SELECT para `authenticated`.
- Cierre de TRUNCATE en las cuatro tablas privadas; retirada de REFERENCES y
  TRIGGER innecesarios. El trigger histórico de certificados conserva su guarda;
  se retira su grant EXECUTE a clientes.
- Pruebas con roles API y claims: titulares, `owner`/`admin`/`issuer` en todos los
  estados institucionales, administrador global, otra institución y anónimo;
  aislamiento, lecturas 4D e integridad tras escrituras rechazadas.
- [Contrato de emisión confiable](SECURE_ISSUANCE.md) y documentación de permisos
  efectivos y verificación local.

**Criterios de aceptación:** ningún `authenticated`, incluido `platform_admin`,
puede insertar, actualizar/revocar, hacer upsert o borrar certificados por la
API de tablas; `anon` no obtiene acceso; las lecturas legítimas se conservan;
la migración no borra ni altera datos; reset, SQL/RLS y lint del código propio
pasan localmente.

**Estado al 28/09/2026: implementada y verificada localmente.** Reconstrucción
completa, 242 comprobaciones SQL y lint de `public`/`certichain_private` superados.
El lint global informa incidencias de la extensión pgTAP; véase [TESTING.md](TESTING.md).
No se ha aplicado a un proyecto remoto. Esta fase **no habilita emisión ni
revocación**: ambas permanecen cerradas para clientes y sus endpoints están pendientes.

### Orden recomendado de los siguientes incrementos (pendientes)

1. Aprovisionamiento, administración y aprobación institucional: alta confiable
   del primer administrador, instituciones y membresías, protección del último
   `owner` y aprobación con `verification_status = 'verified'`.
2. Emisión segura sin blockchain: backend autorizado, PDF privado, validación
   real, SHA-256 de bytes finales, idempotencia y recuperación de fallos parciales.
3. Verificación pública y QR: interfaz mínima, privacidad y límites de abuso.
4. Anclaje blockchain: contrato, adaptador de backend, estados e idempotencia.
5. Revocación completa y endurecimiento: backend, sincronización blockchain,
   reconciliación, seguridad, recuperación y pruebas del recorrido completo.

## Etapas conceptuales del MVP

El plan original siguiente describe capacidades objetivo, no entregas completadas.
La antigua «Fase 5 — Revocación y endurecimiento» se denomina ahora **Etapa 5**;
no debe confundirse con la Fase 5 de implementación anterior.

### Etapa 0 — Diseño y entorno

- Aprobar requisitos, actores y límites del MVP.
- Crear wireframes y flujo de navegación.
- Aprobar ADR iniciales de Supabase, arquitectura, red y storage.
- Inicializar Flutter, Supabase local, Foundry y CI.

**Salida:** repositorio reproducible, documentación base y pantallas navegables sin lógica real.

### Etapa 1 — Identidad e instituciones

- Auth, recuperación y perfiles.
- Instituciones, miembros y aprobación administrativa mínima.
- Políticas RLS y pruebas de aislamiento.

**Salida:** usuarios e instituciones acceden solo a lo autorizado.

### Etapa 2 — Certificados sin blockchain

- Migraciones de certificados y tipos.
- Upload privado, validación, SHA-256 y estados.
- Wallet del estudiante y panel de institución.

**Salida:** emisión off-chain completa y segura.

### Etapa 3 — Verificación y QR

- URL/código público estable.
- DTO público mínimo.
- QR, escáner y verificación opcional de archivo.
- Rate limit y registro prudente de eventos.

**Salida:** un tercero verifica sin cuenta y detecta un PDF alterado.

### Etapa 4 — Blockchain

- Contrato probado en Anvil.
- Despliegue en testnet.
- Edge Function/adaptador, idempotencia y reconciliación.
- UI de pendiente, confirmado y fallo.

**Salida:** emisión anclada y comprobable on-chain.

### Etapa 5 — Revocación y endurecimiento

- Flujo de revocación completo.
- Pruebas E2E, seguridad y accesibilidad.
- Observabilidad, recuperación ante fallos y límites.
- Datos y guion de demo reproducibles.

**Salida:** MVP defendible como TFG.

### Etapa 6 — Memoria y entrega

- Diagramas definitivos, decisiones y resultados.
- Métricas de pruebas y limitaciones.
- Vídeo/demo y manual de instalación.
- Backlog de evolución: API propia, emisión masiva, identidad verificable, eIDAS.

## Criterio de priorización

Si el calendario se complica, conservar en este orden: verificación, autorización/RLS, emisión segura, QR, blockchain, revocación, extras visuales. No sacrificar seguridad o reproducibilidad para añadir funciones secundarias.
