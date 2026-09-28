# ADR-0007: Alta institucional administrada y mutaciones SQL controladas

- Status: accepted
- Date: 2026-09-28

## Context

La fase 5 cerró las escrituras de certificados. Las políticas institucionales
históricas permitían crear instituciones sin owner, mover membresías o retirar
todos los propietarios. El registro siempre crea perfiles holder y no dispone
de un proceso de acreditación institucional de autoservicio.

## Decision

Implementar alta administrada por platform_admin mediante un RPC transaccional
que crea institución pending y primer owner. Mantener estados reales
pending/verified/rejected/suspended. Solo platform_admin decide aprobación,
rechazo, suspensión y reapertura para revisión. Los owner gestionan miembros;
los admin institucionales editan datos. Cerrar DML institucional de las tablas
y usar operaciones SQL estrechas con identidad de Auth y autorización en BD.

El primer administrador y los adicionales requieren SQL confiable como postgres,
objetivo/confirmación explícitos y contador esperado. Ningún RPC público ni
UPDATE ordinario de perfil permite promociones globales. No hay cuenta compartida.

Serializar mutaciones de miembros mediante escritura de la fila institucional,
con guarda inmediata del último owner e invariante diferible para el alta.
Proteger cascadas de Auth/perfiles. Cerrar DELETE/TRUNCATE institucional y conservar
referencias históricas; planificar anonimización en otro incremento.

## Alternatives considered

- Autoservicio con solicitudes: necesita identidad institucional, revisión e
  interfaz nuevas; queda pendiente para evitar ampliar el MVP.
- DML directo con RLS: puede limitar actores, pero requiere proteger columnas,
  altas parciales y transacciones de múltiples operaciones. RPC estrechos
  proporcionan un contrato ejecutable y errores controlados.
- Solo conteo/SELECT FOR UPDATE de propietarios: snapshots antiguos o dos filas
  distintas permiten write skew; la escritura del padre garantiza serialización
  o aborto bajo los tres niveles de aislamiento probados.
- Edge Functions: útiles para el PDF futuro; sin servicios externos en esta fase,
  SQL evita otra credencial/backend y mantiene todo el cambio atómico.

## Consequences

Las dependencias Supabase quedan en auth.uid(), roles API, PostgREST RPC y CLI;
la transacción, locks, constraints y triggers son PostgreSQL. El bootstrap se
reserva a operadores con acceso confiable. No se amplían lecturas de perfiles:
la resolución/invitación de miembros todavía requiere asistencia operativa.
Los clientes futuros deben traducir errores y reintentar transacciones abortadas.
Los grants/políticas SELECT y el bloqueo de certificados se conservan.

## Validation

pgTAP con roles API efectivos, regresión de las 242 pruebas previas, fallo del
segundo INSERT del alta, cascadas y estados reales. Pruebas concurrentes en una
base temporal con copia exclusiva del esquema: bloqueo observado, segunda
operación rechazada y un owner conservado. CI reconstruye localmente y ejecuta
estos controles sin secretos de proyectos remotos. Procedimiento y revisiones
manuales en [INSTITUTION_ADMINISTRATION.md](../INSTITUTION_ADMINISTRATION.md).
