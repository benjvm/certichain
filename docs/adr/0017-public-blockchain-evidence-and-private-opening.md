# ADR-0017 — Evidencia pública v2 y apertura privada

- Estado: accepted para implementación local 9D.
- Fecha: 2026-10-13.

## Decisión

POST verify-certificate-v2 es independiente de v1. Una lectura SQL coherente
obtiene el registro v1 literal y un snapshot técnico mínimo del anclaje del
entorno configurado. No se devuelve blockchain_job. Sin publicación elegible,
registry=not_found y blockchain=null, sin consultar EVM. Sin anclaje elegible,
off_chain_only. No se consulta verify v1 para fabricar el envelope.

La lectura pública reutiliza EvmRegistry sin privateKey, con transporte lector
acotado y lista permitida de métodos. Nunca encola, reconcilia ni escribe. Un
deadline total de 12 s cubre presupuesto, entrada, SQL y EVM; SQL fallido es 503,
EVM fallido permite registro + unavailable. El presupuesto global 60 POST/60 s
se consume exactamente una vez, antes de validar. OPTIONS no consume.

Evidencia actual backend_rpc requiere deployment/runtime/protocolo, canonicidad,
receipt, calldata, evento y estado K/C/I comprobados. Las observaciones previas
persisted_receipt conservan su fecha dentro de last_evidence, siempre anterior.
Timeout/null no acreditan ausencia/reorg. Revocación SQL/EVM distinta produce
divergence. Anvil confirmed conserva not_applicable, nunca finalized.

certificate-opening exige Auth real y una RPC técnica estrecha: titular propio
o miembro owner/admin/issuer actual de emisora verified. Suspensión no retira
acceso al titular; plataforma sin propiedad/membresía no lo recibe. Revalida
publicación y vínculos/H/K/I/S/C. No-store, sin Storage ni material operativo.

Flutter conserva cuatro resultados separados: registro, evidencia, comparación
candidata v1 y comprobación local con apertura. Comparar v1 sustituye el registro
por su propio snapshot y deja la evidencia anterior identificada, nunca combinada
como actual. Obtener/copy/export/import son acciones explícitas. H/S/apertura
solo en memoria del flujo, sin QR, enlaces, preferencias o analytics. El cálculo
SHA-256 usa exactamente 9A y el vector 9B, sin Web3 ni nueva criptografía.

Anclaje institucional usa recibos mínimos por usuario/institución/certificado,
clave persistida antes de POST, recuperación explícita y estados reales. Cambios
de sesión/token, institución, certificado y dispose invalidan respuestas privadas.
El worker permanece externo. No cambia contrato 9B, v1 ni permisos SELECT.

## Consecuencias y límites

La observación RPC depende del backend/proveedor. La apertura prueba relación
documental con el compromiso, no identidad ni verdad académica; no modifica
revocación/caducidad. Explorar un enlace permitido aporta contraste adicional.
No hay explorador Anvil. Copias exportadas están bajo control del usuario.
9E amplia aceptación/recuperación; 10 implementará revocación de producto.

Contrato, límites y comandos: [BLOCKCHAIN_VERIFICATION](../BLOCKCHAIN_VERIFICATION.md).
