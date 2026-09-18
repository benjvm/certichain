# Requisitos del producto

## Problema

Las empresas verifican credenciales mediante documentos fáciles de alterar y procesos manuales dependientes del emisor. CertiChain ofrece una verificación reproducible de integridad, procedencia y vigencia sin publicar datos personales en blockchain.

## Actores

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

- Una institución posee estado `pending`, `approved`, `suspended` o `rejected`.
- Solo una institución `approved` puede emitir.
- Sus miembros tienen permisos explícitos, inicialmente `owner` o `issuer`.

### RF-03 Emisión

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

- Buscar por código o URL obtenida del QR.
- Responder `valid`, `revoked`, `expired`, `pending`, `not_found` o `integrity_mismatch`.
- Mostrar únicamente los campos públicos aprobados.
- No requerir descarga del PDF para una comprobación normal.
- Permitir opcionalmente subir una copia para comparar su SHA-256 sin conservarla.

### RF-06 Revocación

- Solo la institución emisora puede solicitarla.
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
