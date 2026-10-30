# Requisitos del producto

CertiChain permite emitir, custodiar y verificar certificados académicos/profesionales con documentos privados y evidencia de integridad/revocación. El MVP del ciclo completo está implementado y aceptado para Web/Chrome con Supabase local y Anvil; [evidencia y límites](PHASE10_ACCEPTANCE.md).

## Actores

| Actor | Capacidad |
|---|---|
| Titular | Consultar sus certificados, obtener PDF/apertura y compartir código/enlace/QR |
| Institución | Emitir, listar, solicitar anclaje y revocar según membresía vigente |
| Verificador público | Consultar sin cuenta y comparar una copia sin subir el archivo |
| Plataforma | Aprobar/suspender instituciones y gestionar su alta administrada |

No existe un rol autenticado necesario de verificador. La preferencia «Institución» del registro no concede membresía ni administración.

## Requisitos funcionales vigentes

### Identidad y permisos

Registro/login/logout por Supabase Auth y perfil asociado a `auth.users`. Sesión, identidad y generación protegen datos y respuestas tardías. Autorización efectiva en backend/RLS, independiente de navegación o rol mostrado. Recuperación de contraseña, confirmación por deep link y proveedores sociales quedan pendientes, no se simulan.

### Instituciones

Estados reales `pending`, `verified`, `suspended`, `rejected`; roles `owner`, `admin`, `issuer`. Plataforma crea pending con primer owner y decide verificación. Owner/plataforma gestionan miembros; owner/admin editan datos permitidos. Último owner protegido ante baja, degradación, cascada y concurrencia. No eliminar instituciones ni promover plataforma por metadatos/API. [Procedimiento](INSTITUTION_ADMINISTRATION.md).

### Emisión

Sesión y owner/admin/issuer actual de verified; titular válido; título, emisión y expiración opcional. PDF estructuralmente válido ≤8 MiB, privado, SHA-256 sobre bytes exactos y publicación idempotente recuperable. Código público UUID opaco estable; documento/metadatos publicados inmutables. Ningún INSERT directo de cliente. [Contrato](SECURE_ISSUANCE.md).

El anclaje es posterior y explícito: `completed` de emisión y `active/revoked` no significan confirmación EVM. Compromiso con salt privado, sin hash documental on-chain, según [protocolo v1](PHASE9A_BLOCKCHAIN_SPEC.md).

### Wallet y documento

Lecturas acotadas al titular; emisor opcional por RLS; lista de hasta 50 con total/límite visibles. Detalle releído, fechas UTC y estados derivados. PDF mediante autorización y capacidad de 60 s; apertura explícita para comprobar localmente el compromiso. Copias exportadas no pueden retirarse remotamente. [Wallet](STUDENT_WALLET.md).

### Verificación pública

Código/enlace/QR sin sesión, proyección mínima cerrada y prioridad revoked/expired/issuer_unavailable/valid. `not_found` uniforme para no elegible. Un instante servidor fija vigencia/checked_at. Presupuesto global compartido 60 POST/60 s, 429/Retry-After y errores técnicos explícitos. V3 integra evidencia SQL/issue/revoke; v1/v2/compare conservan compatibilidad.

La comparación procesa bytes locales y separa integridad de vigencia. Verificar el compromiso independientemente requiere apertura autorizada compartida; compare v1 sin apertura confía en el hash esperado del backend. Una coincidencia no invalida revocación o caducidad. [Público](PUBLIC_VERIFICATION.md), [evidencia/apertura](BLOCKCHAIN_VERIFICATION.md).

### Revocación

Owner/admin de la emisora verified/suspended solicita mediante backend, con motivo privado e idempotencia. SQL inmediato e irreversible; auditoría protegida y sincronización revoke durable cuando proceda. Suspender no revoca por sí solo. Issue firmado/tardío se reconcilia y compensa; reorg o fallo RPC nunca restaura active. Progreso y reautorización explícitos. [Contrato](REVOCATION.md).

## Requisitos no funcionales

- Mínimo privilegio, RLS, validación servidor, buckets privados y secretos solo en backend.
- Nada de PII/hash documental/salt on-chain ni contenido privado en logs/DTO público.
- Migraciones nuevas y versionadas; dominio puro e infraestructura detrás de contratos.
- Recursos limitados, cancelación, idempotencia y estados recuperables ante fallo parcial.
- Texto/iconos además de color, semántica, scroll y escala de texto. Revisión humana aún pendiente.
- Observabilidad segura; no presentar el objetivo de latencia como un benchmark de producción.

## Fuera de alcance y pendientes

NFT, compra/venta/transferencia de credenciales, pagos, consenso propio, multichain, red privada e integraciones masivas no forman parte del MVP. Certificados emitidos no se editan: revocar y emitir otro. Blockchain no prueba identidad humana, verdad académica ni acreditación legal.

Pendientes verificables: [ROADMAP](ROADMAP.md). Cámara excluida por instrucción del usuario, sin bloquear trabajo posterior ni omitir QR estático/PDF/Auth/SQL/EVM.
