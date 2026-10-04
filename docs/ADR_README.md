# Architecture Decision Records

Los ADR registran decisiones estructurales para evitar que el proyecto cambie de dirección sin contexto y sirven como evidencia razonada en la memoria del TFG.

## Convención

Nombre:

```text
NNNN-titulo-corto.md
```

Estados permitidos: `proposed`, `accepted`, `superseded`, `rejected`.

No se edita el razonamiento histórico de un ADR aceptado para ocultar un cambio. Se crea otro ADR que lo sustituye y ambos se enlazan.

## Plantilla

```markdown
# ADR-NNNN: Título

- Status: proposed
- Date: YYYY-MM-DD
- Deciders: Benjamin Sánchez

## Context

¿Qué problema o restricción obliga a decidir?

## Decision

¿Qué se ha decidido exactamente?

## Alternatives considered

- Alternativa A: ventajas y desventajas.
- Alternativa B: ventajas y desventajas.

## Consequences

### Positive

- ...

### Negative / risks

- ...

## Validation

¿Cómo sabremos que la decisión funciona?
```

## ADR iniciales recomendados

Decisión aceptada implementada en Fase 6:
[0007-managed-institution-administration.md](adr/0007-managed-institution-administration.md).

Decisiones aceptadas de emisión y documentos:
[ADR-0008](adr/0008-private-issuance-reservations.md),
[ADR-0009](adr/0009-leased-private-issuance.md) y
[ADR-0010](adr/0010-institutional-client-and-document-capabilities.md).

Verificación pública del registro y presupuesto compartido:
[ADR-0011](adr/0011-public-registry-verification.md).

1. `0001-use-supabase-initially.md`.
2. `0002-feature-first-clean-boundaries.md`.
3. `0003-version-database-with-migrations.md`.
4. `0004-private-document-storage.md`.
5. `0005-select-evm-test-network.md`.
6. `0006-backend-owned-blockchain-signing.md`.

No crear ADR para cada detalle menor; reservarlos para decisiones caras de revertir o con alternativas reales.
