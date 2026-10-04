# Requisitos del producto

## Problema

Las empresas verifican credenciales mediante documentos fáciles de alterar y procesos manuales dependientes del emisor. CertiChain ofrece una verificación reproducible de integridad, procedencia y vigencia sin publicar datos personales en blockchain.

## Actores

Las capacidades siguientes describen el MVP objetivo. Tras Fase 6 se conservan
Auth y las lecturas de wallet/detalle 4D. 7A–7D entregan emisión autenticada,
PDF privado, recuperación y cliente institucional. Escrituras directas siguen
cerradas; el flujo de revocación permanece pendiente. 8A añade backend público
por código, todavía sin pantalla, QR ni blockchain.

| Actor | Capacidades del MVP |
|---|---|
| Estudiante | Consultar, abrir y compartir sus certificados |
| Institución | Completar su perfil, emitir, listar y revocar sus certificados |
| Verificador público | Escanear QR o introducir código y consultar el resultado permitido |
| Administrador | Aprobar o suspender instituciones y auditar incidencias |

`verifier` no necesita ser un rol autenticado en el MVP: la verificación esencial será pública y de solo lectura.

## Historias esenciales

- Como institución aprobada, quiero emitir un certificado para un estudiante identificado, adjuntando el PDF y sus metadatos.
- Como estudiante, quiero ver mis certificados y compartir una URL/QR verificable.
- Como verificador, quiero conocer si el certificado existe, es íntegro, pertenece a un emisor aprobado y no está revocado o expirado.
- Como institución, quiero revocar un certificado emitido por mí indicando un motivo interno.
- Como administrador, quiero aprobar instituciones antes de que puedan emitir.

## Requisitos funcionales

### RF-01 Identidad

- Registro, inicio y cierre de sesión mediante Supabase Auth.
- Recuperación de contraseña.
- Perfil asociado a `auth.users`.
- Autorización efectiva en servidor/RLS, nunca solo en navegación de UI.

### RF-02 Instituciones

- El esquema real usa `verification_status` con `pending`, `verified`,
  `suspended` o `rejected`. «Aprobada» significa `verified`, no `approved`.
- Solo una institución `verified` podrá emitir mediante backend autorizado;
  en Fase 5 ninguna institución puede emitir directamente mediante la API.
- Los roles de membresía reales son `owner`, `admin` e `issuer`.
- Fase 6 entrega alta administrada: plataforma crea institución pending y primer
  owner existente en una transacción. Autoservicio e interfaz Flutter quedan
  pendientes. El registro normal y la selección «Institución» crean un holder.
- Solo plataforma aprueba/rechaza/suspende/reabre para revisión. Owner y admin
  institucional editan datos; solo owner y plataforma gestionan miembros.
- Conservar al menos un owner bajo bajas, degradaciones, cascadas y concurrencia.
  No permitir eliminar instituciones; conservar referencias e historial.
- Primer administrador y adicionales: SQL confiable con identidad confirmada,
  nunca metadatos, RPC público de promoción ni UPDATE ordinario de perfil.

### RF-03 Emisión

- Operación privilegiada de backend: sesión, membresía autorizada y estado
  institucional revalidados al persistir; nunca INSERT directo desde Flutter.
- Cumplir [SECURE_ISSUANCE.md](SECURE_ISSUANCE.md); primero emisión segura sin
  blockchain, posteriormente anclaje.
- Registrar destinatario, título, tipo, fecha de emisión y expiración opcional.
- Aceptar un PDF válido dentro del límite configurado.
- Calcular SHA-256 sobre los bytes finales almacenados.
- Crear un identificador público no secuencial y estable.
- Registrar la prueba on-chain de forma idempotente.
- Mostrar un estado de proceso si la transacción aún no está confirmada.

### RF-04 Wallet de certificados

- Listar exclusivamente los certificados del estudiante autenticado.
- Mostrar emisor, título, fechas y estado derivado.
- Acceder al documento mediante autorización y URL temporal.

### RF-05 Verificación pública

- 8A: POST público por `credential_code` UUID, sin cuenta o sesión.
- Responder `revoked`, `expired`, `issuer_unavailable`, `valid` en ese orden
  para publicaciones elegibles; `not_found` para evidencia ausente/incompleta.
- Mostrar exclusivamente el contrato v1 de [PUBLIC_VERIFICATION.md](PUBLIC_VERIFICATION.md).
- Un instante servidor para caducidad y checked_at; expiración inclusiva.
- Presupuesto compartido global 60 POST/60 s, incluso entradas inválidas;
  agotamiento 429 y fallo técnico 503, nunca ausencia fabricada.
- No requerir descarga del PDF para una comprobación normal.
- 8B–8D pendientes: pantalla pública, QR/enlaces/escáner y comparación de copia
  sin conservarla. `integrity_mismatch` requerirá su contrato posterior;
  `pending` no existe sin un proceso blockchain real.

### RF-06 Revocación

- Solo la institución emisora puede solicitarla.
- Solicitud autorizada en backend con membresía `owner`/`admin`; ningún cliente,
  incluido `platform_admin`, utiliza UPDATE directo en `certificates`.
- La revocación es irreversible en el MVP.
- Persistir el resultado de blockchain y reflejarlo en la verificación.

## Requisitos no funcionales

- Seguridad: RLS, validación en servidor, buckets privados y secretos fuera del cliente.
- Privacidad: minimización de datos, nada de PII on-chain y retención documentada.
- Mantenibilidad: migraciones versionadas, capas desacopladas y ADR.
- Portabilidad: dominio independiente de Supabase; PostgreSQL estándar cuando sea posible.
- Accesibilidad: contraste AA, etiquetas semánticas y soporte de tamaño de texto.
- Rendimiento: respuesta de verificación objetivo menor de 2 s sin contar congestión de red blockchain.
- Observabilidad: errores correlacionables sin registrar información sensible.
- Fiabilidad: emisión idempotente y estados recuperables ante fallo parcial.

## Fuera del MVP

- Compra, venta o transferencia de credenciales.
- NFT, token fungible o wallet criptográfica del estudiante.
- Consenso propio o red blockchain privada.
- Edición de un certificado emitido; se revoca y se crea uno nuevo.
- Integraciones masivas con universidades, firma eIDAS y pagos.
- LinkedIn social, marketplace de cursos o mensajería.

## Criterio de éxito de la demo

Una institución aprobada emite un PDF; el alumno lo ve y comparte su QR; la verificación devuelve válido. Tras alterar una copia, la comprobación por archivo detecta el cambio. Tras revocarlo, el mismo QR devuelve revocado.
