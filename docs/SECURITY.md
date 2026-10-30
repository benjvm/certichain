# Seguridad y privacidad

Política vigente del MVP. Los límites y la evidencia ejecutada están en [PHASE10_ACCEPTANCE](PHASE10_ACCEPTANCE.md); las decisiones estructurales, en [ADRs](ADR_README.md).

## Límites de confianza y autorización

Flutter y cualquier navegador son clientes no confiables. RLS y backend vuelven a comprobar identidad, sesión, membresía actual, estado institucional y propiedad. El dominio y la UI no contienen privilegios ni secretos.

- `auth.users` mantiene identidad; `profiles` contiene datos de aplicación. El trigger confiable provisiona `holder`; metadatos o preferencia de registro no conceden roles.
- `certificates` permite solo SELECT autorizado a `authenticated`: titular, miembro de la emisora o plataforma. No hay INSERT/UPDATE/DELETE/upsert de cliente, tampoco para `platform_admin`.
- `anon` no lee perfiles, instituciones, membresías, certificados, operaciones privadas o Storage. Verificación pública usa únicamente proyecciones técnicas cerradas.
- Grants de TRUNCATE/REFERENCES/TRIGGER API retirados. TRUNCATE no depende de RLS. Tablas técnicas expuestas tienen RLS y carecen de políticas permisivas para clientes.
- Instituciones y miembros se mutan mediante RPC autorizados, con `auth.uid()`, campos cerrados, `search_path` controlado y protección transaccional del último owner. No borrar instituciones para corregir incidencias.
- Solo SQL operativo confiable asigna `platform_admin`, con UUID confirmado y contador esperado. Ni API de perfiles, metadatos ni RPC público permiten promoción.
- Emitir exige owner/admin/issuer vigente de una institución verified. Revocar/reautorizar exige owner/admin de la emisora verified o suspended. Plataforma sin esa membresía no obtiene privilegio de revocación.
- `service_role` pertenece solo al backend. Su capacidad técnica no elimina la obligación de comprobar autorización de negocio antes y al persistir.

Procedimientos: [administración](INSTITUTION_ADMINISTRATION.md), [emisión](SECURE_ISSUANCE.md), [revocación](REVOCATION.md) y [datos](DATABASE.md).

## Documentos y archivos

El bucket `certificates` es privado, `application/pdf`, máximo **8 388 608 bytes**. Políticas restrictivas niegan operaciones directas SELECT/INSERT/UPDATE/DELETE a `anon` y `authenticated`. MIME/extensión del navegador o del bucket no sustituyen validación estructural y límites en servidor.

El backend valida el subconjunto PDF de [SECURE_ISSUANCE](SECURE_ISSUANCE.md), rechaza cifrado y contenido activo/no admitido, limita recursos, guarda sin upsert y relee/hashéa los bytes finales antes de publicar. Los documentos publicados y sus metadatos son inmutables. Rutas opacas `<institution_id>/<certificate_id>.pdf`, sin nombres o emails.

`certificate-pdf` exige JWT/Auth y autorización actual: titular propio, incluso con emisora suspended, o miembro owner/admin/issuer de verified. El 404 es uniforme para ajeno/ausente/sin documento. El handler devuelve solo `signed_url` y `expires_in:60`, con no-store. La capacidad dura hasta su vencimiento aunque posteriormente cambie la membresía. Cada nueva descarga vuelve a autorizar. No persistir la URL en modelo, navegación, historial o preferencias.

Revocar no borra PDF ni retira copias exportadas. El reconciliador elimina únicamente un huérfano confirmado bajo su protocolo; nunca un PDF completed para resolver EVM. Retención legal y análisis adicional de archivos para producción requieren decisiones propias.

El PDF candidato y los JSON de apertura se procesan localmente. Límites y cancelación se comprueban antes/durante lectura; no se suben nombre, ruta o bytes. Los adaptadores nativos limpian solo su copia de caché conocida, con validación de ruta real y sin borrar originales o archivos ajenos. No se promete borrado seguro del soporte ni eliminación tras crash.

## Información pública de verificación

El registro v1 admite exclusivamente `schema_version`, `result`, `credential_code`, `title`, `issuer.name`, `issued_at`, `expires_at`, `checked_at` y `verification_source`. `not_found` contiene solo versión y resultado. El nombre/ID del titular no se publica.

La elegibilidad exige publicación completed y vínculos/documento coherentes. Prioridad: revoked, expired (`expires_at <= checked_at`), issuer_unavailable, valid. Suspender no revoca automáticamente. Fechas del servidor, sin reclasificar la vigencia por reloj cliente. `valid` no autentica al presentador ni comprueba su copia.

V2 envuelve ese registro con evidencia blockchain; v3 añade evidencia separada de revocación. La app usa v3. Campos blockchain cerrados: estado/finalidad/fecha/fuente, red/contrato/versión, K/I/C opacos, flag de revocación, transacción/bloque/confirmaciones y fechas EVM cuando hay evidencia válida. `last_evidence` es anterior, conserva fecha original y no se rellena con valores inventados. La lista y nulabilidad por estado se fijan en [BLOCKCHAIN_VERIFICATION](BLOCKCHAIN_VERIFICATION.md) y [REVOCATION](REVOCATION.md).

Quedan excluidos del público: identidad del titular, hashes documentales registrados, salt, apertura, PDF, rutas privadas, URLs firmadas, motivo/actor/request_id internos, raw transactions, nonces/ledger, secretos y snapshots SQL completos. Compare v1 recibe únicamente código/hash candidato y devuelve un resultado de integridad, nunca el hash esperado.

Los endpoints públicos tienen `verify_jwt=false` intencionalmente; el transporte omite Authorization/apikey/cookies incluso en mismo origen, rechaza redirecciones y usa límites/deadlines. Los privados conservan JWT/Auth. Una caída SQL/RPC es un fallo técnico o evidencia no disponible, nunca una ausencia fabricada.

Cada POST público consume presupuesto global atómico **60/60 s**, compartido entre versiones y compare, antes de validar. OPTIONS no consume. No almacenar IP, códigos o historial de búsquedas en ese contador. 429 incluye Retry-After; no depende de X-Forwarded-For. Este presupuesto sirve a la demo; requiere protección de ingress, equidad y carga antes de tráfico público.

## Blockchain, firma y apertura

SHA-256 se calcula sobre los bytes exactos del PDF. El hash H y salt S permanecen privados; on-chain solo K/C/I opacos, direcciones técnicas, permisos, versión, estado y fechas mínimas. No PII, texto del certificado, rutas, hash documental o motivo en estado, calldata ni eventos. Encoding y compromiso normativos en [protocolo v1](PHASE9A_BLOCKCHAIN_SPEC.md).

El administrador EVM y el firmante operativo están separados. Las claves se inyectan por secretos de backend/CI; no llegan a Flutter, al lector público ni a configuración Web. El worker ordinario rechaza la clave administrativa. Cada EOA mantiene su ledger exclusivo y completo.

Persistir firma/nonce/hash/raw privado antes de broadcast. Reconciliar todos los intentos, incluidos replacements anteriores; receipt aislado o nonce unknown no autoriza saltar historial. Fencing impide actuar al worker vencido. Despliegue/genesis/runtime/bloque canónico y permisos se revalidan. Un reset o nueva cadena no sustituye la identidad anterior. Reorg/fallo EVM no reactiva SQL revocado.

`certificate-opening` aplica Auth/autorización actual y devuelve una apertura mínima para el titular propio o miembro autorizado de verified. Hash/salt solo en memoria local durante la comprobación; copiar/exportar requiere acción explícita. Logout/cambio de sesión/salida descartan referencias y respuestas tardías. Las copias externas siguen bajo control de quien las recibió.

Backups deben conservar bytes exactos del PDF, identidad, H/K/I/C/S y ledger. Recuperar filas de `storage.objects` no recupera bytes. [Operación y restore](BLOCKCHAIN_OPERATIONS.md).

## Excepción del gateway JWT

Toda respuesta de un handler CertiChain, incluidos errores, exige `Cache-Control: no-store`. La excepción externa autorizada el 18/10/2026 cubre **solo la ausencia** de esa cabecera en rechazos JWT genéricos de Supabase **anteriores al handler**, reconocidos por el test. No corrige ni parchea Supabase, no añade un proxy y no desactiva JWT/Auth.

El reconocimiento está limitado a `revoke-certificate`, `revocation-progress` y `reauthorize-revocation`, en escenarios sin token, Bearer inválido o token firmado expirado. Exige HTTP 401, `sb-error-code`/`code` coincidentes y uno de estos pares genéricos:

| Código | Mensaje exacto |
|---|---|
| UNAUTHORIZED_NO_AUTH_HEADER | Missing authorization header |
| UNAUTHORIZED_INVALID_JWT_FORMAT | Invalid JWT format |
| UNAUTHORIZED_ASYMMETRIC_JWT / UNAUTHORIZED_LEGACY_JWT | Invalid JWT |

El JSON UTF-8 debe ser cerrado, sin claves duplicadas/adicionales; `msg`, si aparece, repite `message`. Se inspecciona solo en memoria. `public` u otro Cache-Control no se acepta como ausencia. Si el proveedor entrega no-store, se registra cumplimiento sin excepción. Un 401 del handler, código/estado inesperado, red fallida, cuerpo malformado o contenido privado nunca se exceptúa.

La matriz contiene 17 pares ruta/escenario exactos. `cache_control_result` sigue FAIL si falta una cabecera; `result` evalúa la política revisada, conservando `external_exception_count` y `external_exception_applied`. No transformar el FAIL estricto en PASS. Solo códigos/estados/cabeceras allowlist se guardan. Implementación: `supabase/tests/phase10_gateway_policy.ts`; decisión: [ADR-0018](adr/0018-irreversible-revocation-and-public-v3.md). Alojado NOT_RUN.

## Configuración, logs y límites

- Dart defines solo para URL/base Web y clave pública anon/publishable; release remoto requiere HTTPS. No secretos en Git, seeds, binarios o capturas.
- Nunca registrar PDF/apertura, hashes/salts privados, tokens, cuerpos Auth/privados, PII, URL firmada o errores upstream arbitrarios. Diagnósticos con categorías estables, estado y ubicación segura.
- Informes de aceptación sanitizados y vinculados a run_id/SHA/fecha; builds inspeccionados para excluir secretos. Rotar cualquier secreto expuesto mediante el procedimiento operativo.
- Conservación de permisos probada con titulares distintos, emisor, ajeno, plataforma y anónimo; los filtros de ámbito se mantienen incluso cuando RLS permite más lecturas por otro rol del usuario.
- Cámara excluida de pruebas por instrucción del usuario. No se elimina la funcionalidad; [TESTING](TESTING.md) conserva el motivo exacto y las comprobaciones independientes.
- No se acredita identidad del presentador, verdad académica, acreditación legal o custodia de producción por registrar un compromiso. El proyecto sigue siendo un MVP demostrable, no un sistema público aceptado para producción.
