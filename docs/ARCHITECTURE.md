# Arquitectura

## Principios

1. El dominio define el producto; Supabase y EVM son adaptadores reemplazables.
2. Ningún secreto o privilegio administrativo reside en Flutter.
3. La base de datos es la fuente operativa; blockchain es la prueba externa de integridad y revocación.
4. Los procesos distribuidos usan estados explícitos e idempotencia, no una transacción ficticia entre PostgreSQL y blockchain.

## Contenedores

```mermaid
flowchart TD
    A[Flutter app] -->|HTTPS| B[Supabase API y Edge Functions]
    B --> C[(PostgreSQL)]
    B --> D[Storage privado]
    C -->|cola privada 9C| E[Worker y adaptador EVM]
    E --> F[CertificateRegistry v1]
    G[Verificador web o app] -->|URL o QR| B
```

Flutter puede leer datos autorizados mediante repositorios respaldados por el SDK de Supabase. Emisión, revocación, hashing definitivo y escritura blockchain pasan por una Edge Function u otro backend confiable.

Tras Fase 5, la API de tablas de `certificates` solo permite SELECT autorizado
para `authenticated`; emisión y revocación directas no están habilitadas,
incluido para `platform_admin`. 7B implementa la Edge Function autenticada y
RPC técnicos de publicación; 7C añade cliente y acceso autorizado al PDF.
El [contrato vigente](SECURE_ISSUANCE.md) define sus controles. El nuevo flujo
de revocación y blockchain siguen pendientes.

Fase 6 resuelve administración institucional mediante operaciones SQL
transaccionales expuestas como RPC autenticados: alta pending con primer owner,
datos, estados y miembros. Sus funciones verifican auth.uid() y autorización
en BD y sustituyen el DML institucional directo. La aprobación corresponde a
plataforma; owner gestiona miembros y admin institucional edita datos. La
escritura de la fila institucional serializa los cambios y protege último owner,
también en cascadas de Auth. DELETE institucional se cierra para conservar historial.
Bootstrap y altas adicionales de plataforma requieren SQL operativo confiable;
no son RPC públicos ni actualizaciones ordinarias de perfil.
Decisión: [ADR-0007](adr/0007-managed-institution-administration.md).
La Fase 7 entrega emisión segura sin blockchain con backend, PDF privado, SHA-256
e idempotencia; los RPC de fase 6 no escriben certificados ni implementan PDF.

## Estructura Flutter

```text
mobile/lib/
├── app/                    # arranque, router, tema e inyección
├── core/                   # errores, utilidades y contratos compartidos
├── features/
│   ├── auth/
│   ├── certificates/
│   ├── issuance/
│   ├── verification/
│   ├── institutions/
│   └── profile/
└── main.dart
```

Cada feature puede contener:

```text
feature/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
├── data/
│   ├── datasources/
│   ├── models/
│   └── repositories/
└── presentation/
    ├── pages/
    ├── controllers/
    └── widgets/
```

Regla de dependencias: `presentation → domain ← data`. El dominio no depende de las otras capas. `data` implementa interfaces definidas en `domain`.

## Contratos principales

- `AuthRepository`: sesión, registro y recuperación.
- `CertificateRepository`: consultas autorizadas y detalle.
- `IssuanceRepository`: solicitud y seguimiento de emisión.
- `VerificationRepository`: proyección pública por código.
- `HashComparisonRepository`: comparación pública de un hash candidato.
- `ComparisonPdfPicker` / `PdfHasher` / `QrCamera`: capacidades locales de copia y QR.
- `InstitutionRepository`: perfil, miembros y estado.
- `BlockchainRegistry` (backend 9C): preparar/enviar/observar tx,
  consultar registro/emisor y validar despliegue; solo backend, DTO puro y
  adaptador RPC separados según [9A](PHASE9A_BLOCKCHAIN_SPEC.md).
- `DocumentStorage`: guardar, recuperar y eliminar documentos según política.

Los nombres representan responsabilidades; no obligan a crear una clase por método.

## Flujo de emisión vigente sin blockchain

7A–7D implementan emisión segura sin blockchain: autorización de sesión y
membresía, `verification_status = 'verified'` al persistir, destinatario válido,
PDF validado/privado, SHA-256 de sus bytes finales e idempotencia durable con
recuperación ante fallos de Storage/base de datos. Publica estado `active` y
conserva inmutables sus datos finales. Reserva y publicación transaccionales
rodean las operaciones Storage; véase [SECURE_ISSUANCE.md](SECURE_ISSUANCE.md).

## Backend público 8A

Verificador sin sesión → POST verify-certificate → consumo de presupuesto
compartido en PostgreSQL → entrada JSON cerrada → lookup_public_certificate.
Solo el backend posee service_role; ambos RPC técnicos tienen EXECUTE exclusivo.
La consulta enlaza certificado/operación completed/institución y proyecta campos
públicos. Un instante servidor evalúa resultados. No accede a Auth, membresías
del verificador ni Storage; no descarga ni compara PDFs por petición.

El limitador serializa una fila privada, usa reloj servidor tras el lock y no
depende de cabeceras o IP. El backend consume antes de validar para cubrir los
POST desconocidos/inválidos y falla cerrado ante problemas de infraestructura.
No hay cambios Flutter en 8A. Contrato y límites:
[PUBLIC_VERIFICATION.md](PUBLIC_VERIFICATION.md), [ADR-0011](adr/0011-public-registry-verification.md).

## Backend privado 9C conforme al protocolo 9A

Publicar active/completed conserva el flujo actual. Después, una solicitud de
anclaje explícita y autorizada crea identidad/compromiso y operación durable en
tablas privadas nuevas de 9C. Un worker backend revalida, firma, persiste intento
antes de enviar y reconcilia receipt/evento/bloque/confirmaciones/finalidad.
El adaptador vive bajo `supabase/functions/_shared/blockchain/data/`; su puerto
y DTO puros en `domain/`. No hay transacción PostgreSQL abierta durante RPC ni
atomicidad PostgreSQL/EVM. Flutter no firma ni contiene Web3 en dominio.

`certificate.status` sigue active/revoked; emisión completed, anclaje e integridad
de la copia tienen estados distintos. Se retira la propuesta antigua de añadir
anchoring/anchor_failed al certificado. Expired se deriva de fecha; confirmed
no equivale a finalized. Salt/hash documental privados, compromiso público.
Sepolia/Anvil y autoridad por I según [ADR-0014](adr/0014-evm-network-toolchain-and-authority.md).
Recuperación/versionado según [ADR-0015](adr/0015-private-commitments-and-durable-anchoring.md).
Ethers fijado, nonce revertido y despliegue local según
[ADR-0016](adr/0016-durable-evm-adapter-and-reverted-nonce.md);
[operación 9C](BLOCKCHAIN_OPERATIONS.md).

La fase 10 añadirá revocación SQL irreversible inmediata y solicitud EVM durable
cuando proceda, sin retrasar la advertencia pública por un RPC caído. El trigger
histórico no implementa ese flujo. Especificación completa:
[PHASE9A_BLOCKCHAIN_SPEC.md](PHASE9A_BLOCKCHAIN_SPEC.md).

## Portabilidad futura

La primera migración prevista sería `Supabase SDK → API propia`, manteniendo casos de uso y entidades. Posteriormente, Auth y Storage pueden sustituirse detrás de adaptadores. Las dependencias específicas de Supabase se inventarían en ADR y en `docs/DATABASE.md`.


## Comparación y escáner 8C

Flutter selecciona una copia local de máximo 8 MiB y calcula SHA-256 exacto sin
upload. Envía exclusivamente código/hash a compare-certificate-hash; el backend
consume el mismo presupuesto 8A y compara contra evidencia elegible en un
snapshot SQL coherente. verification v1 y file_integrity son resultados distintos:
coincidencia no elimina revocación/caducidad. verify-certificate permanece cerrado.
Escáner QrCamera local, accionado por usuario y detenido por ciclo de vida,
acepta solo enlace canónico de base confiable/UUID y requiere confirmar consulta.
Cámara/selector/hash detrás de contratos; raíz compone preview y adaptador sin
hacer depender data de presentation. La operación privilegiada/hash esperado
continúa en backend. [ADR-0013](adr/0013-public-candidate-hash-and-qr-scanning.md).
