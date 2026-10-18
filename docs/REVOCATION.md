# Revocación — Fase 10

## Requisito vigente de cabeceras — 18/10/2026

No-store sigue siendo obligatorio en **todas las respuestas del handler privado**.
La única excepción autorizada es su ausencia en 401 JWT genéricos emitidos por
Supabase antes del handler, con ruta/escenario/código/cuerpo cerrado comprobados.
[Política, diagnóstico estricto y evidencia](PHASE10B_GATEWAY.md),
[ADR-0018](adr/0018-irreversible-revocation-and-public-v3.md). El gate distingue
Auth, privacidad, no-store de la aplicación y excepción externa visible. No basta
cualquier 401. verify_jwt=true, Auth real y autorización SQL no cambian. Alojado
NOT_RUN. Los pendientes estrictos del 16/10 inferiores son evidencia histórica;
el nuevo dictamen y pruebas constan en [aceptación](PHASE10_ACCEPTANCE.md).

Aceptación para demo Web local del 15/10 y revisión 10B del 16/10 conservadas
como historia. El requisito revisado del 18/10 y su dictamen constan en:
[PHASE10_ACCEPTANCE](PHASE10_ACCEPTANCE.md).
Decisiones: [ADR-0018](adr/0018-irreversible-revocation-and-public-v3.md).

Solo owner/admin actuales de la emisora verified/suspended solicitan o reautorizan.
La decisión SQL se aplica inmediatamente, de forma irreversible, antes de cualquier
RPC, saldo, firma o confirmación. Suspender no revoca automáticamente. Errores,
reintentos/reorg/restore no restauran active. Completed, documentos, apertura y
metadatos se conservan. Las políticas PDF/apertura siguen vigentes: titular propio
también con emisora suspended; miembros actuales solo de verified. No se prometen
retirar copias exportadas ni capacidades firmadas de 60 s ya entregadas.

## API Auth y privacidad

POST `revoke-certificate`, verify_jwt=true y Auth real; JSON cerrado UTF-8 ≤8192
bytes con certificate_id e idempotency_key UUID canónicos y reason. Normalización
y huella exactas en ADR-0018. Actor/red/contrato/emisor/firmante se resuelven en
servidor. Motivo obligatorio privado, 1–500 puntos Unicode; no HTML interpretado,
logs del cuerpo, errores upstream ni motivo en PDF, QR, código, enlace o EVM.

202 significa nueva decisión SQL, nunca confirmación blockchain; 200 recuperación.
DTO cerrado: certificate_id, request_id (null en históricos), status active/revoked,
revoked_at SQL, reason privado nullable y synchronization [{operation_id,status}].
POST `revocation-progress` recibe solo certificate_id y devuelve ese DTO; no cambia
autorizaciones ni firma. POST `reauthorize-revocation` recibe operation_id de
revoke, vuelve a autorizar y añade actor/rol/fecha al historial existente; no cambia
la primera decisión. Todas las respuestas del handler no-store. Sin raw, salts, nonces,
secretos, ledger o mensajes upstream. 401 sesión inválida; 400 entrada inválida;
413 cuerpo grande; 404 revocation_unavailable uniforme para ajeno/ausente/denegado;
409 idempotency_conflict/busy; 503 temporary_failure.

El handler selecciona y valida explícitamente los seis campos del DTO y los dos
de cada elemento synchronization. Descarta campos RPC adicionales en ambos
niveles; campos obligatorios ausentes, tipos/UUID/fechas/estados inválidos o datos
incoherentes producen 503 cerrado sin contenido upstream. Conserva microsegundos,
request_id/reason null históricos y los null del certificado activo. `created`
es booleano interno obligatorio solo en la solicitud; nunca se expone ni permite
que progreso/reautorización devuelvan 202. UUID admite mayúsculas y se normaliza
a minúsculas, sin espacios ni saltos de línea. Un deadline del cuerpo da 503.

Pendiente detectado en la revisión 10B: el 401 del gateway JWT local de Supabase
CLI 2.117.0 ocurre antes del handler y no añade Cache-Control. La garantía no-store
del handler incluye sus errores, pero no acredita ese rechazo previo. Se conserva
verify_jwt=true: cerrar el requisito HTTP extremo a extremo exige corregir la
cabecera en la capa gateway, sin desactivar JWT ni sustituir Auth real. El harness
registra este incumplimiento como FAIL, no como excepción aceptada al contrato.
La [continuación de diagnóstico](PHASE10B_GATEWAY.md) identifica el main service
de la CLI, incluye reproducción sin secretos y matriz HTTP real con token
ausente/inválido/expirado y sesión válida. No hay configuración soportada para
sus cabeceras previas al handler. Alojado NOT_RUN; no se atribuye al alojado ni
un defecto local ni una corrección. Se mantienen JWT y Auth real.

Clave por institución: igual certificado/motivo canónico recupera la petición,
también tras pérdida de respuesta. Misma clave con certificado/motivo distinto
conflictúa. Otra clave recupera la decisión original sin nueva revocación ni
sobrescribir fecha/motivo; el alias queda persistido. Consulta/reintento siempre
requieren membresía actual. El titular y plataforma no leen auditoría por privilegio
implícito. Históricos sin completed siguen sin exposición pública; revocados
anteriores conservan fecha y ausencia de actor/motivo registrados.

## Worker y observación

El registro privado SQL se conserva aun sin anchor. Sin firma issue durable se
cancela solo ese trabajo. Con firma persistida se conserva obligación revoke por
cada anchor existente, incluso deployments deshabilitados. Issue tardío compatible
se reconcilia y compensa con el mismo K/I/C/S; no se crea otra emisión.
Unknown/null no demuestra abandono. Orden de EOA, fencing, reservas, replacements,
reverts y rotación siguen ADR-0016. No saltar ni liberar nonces desconocidos.

Issue y revoke guardan operaciones/attempts/receipts propios. Revoke requiere
deployment vivo idéntico, registro C/I correcto, signer vigente y canRevoke.
Observar/retransmitir bytes ya firmados sigue siendo posible sin permiso humano
actual; firmar otra vez exige autorización vigente, y blocked/failed requieren
reautorización explícita. Configuración incompatible, falta de saldo/permiso o
ledger incompleto se muestran como bloqueo. Reorg no revierte SQL.

`verify-certificate-v3` es público lector, sin signer ni encolado; mismo código
UUID, presupuesto global compartido consumido una vez, JSON ≤2048 bytes, deadline
total 12 s y no-store. Envelope cerrado {schema_version:"3",registry:v1 literal,
blockchain:evidencia de issue,revocation}. Not_found: ambos bloques null. El nuevo
bloque cerrado contiene state, revoked_at SQL, checked_at, source, evidence y
last_evidence. Estados: not_requested/not_applicable/pending/blocked/included/
confirmed/reorged/unavailable/divergence. Evidence actual de revoke contiene
transaction_hash,block_number,block_hash,confirmations,revoked_at EVM,checked_at,
finality. Last_evidence solo transaction_hash,block_number,block_hash,checked_at
observado anteriormente. No motivo ni actor. V1/v2 y compare v1 conservan contrato.
La UI explica por separado SQL revoked, demora esperada, reorg, indisponibilidad
y divergencia incompatible. El receipt original de issue nunca se reemplaza.

## Pasos MANUALES del operador (no ejecutados remotamente aquí)

1. Revisar backup/vínculo y aplicar **solo migraciones nuevas**, en orden:
   `20261015100000_irreversible_revocation.sql` y
   `20261015110000_revocation_public_v3.sql` y
   `20261016110000_revocation_reauthorization_unavailable.sql` (corrección 10B del
   404 de operación ausente, sin cambios de datos). Desde la raíz:

   ```powershell
   supabase migration list --linked
   supabase db push --linked --dry-run
   # Solo tras revisión/autorización del operador y backup privado:
   supabase db push --linked
   ```

2. Revisar el I y signer existentes, sin cambiar su identidad. En una sesión host
   confiable, SUPABASE_URL/SERVICE_ROLE y EVM_RPC_URL por entorno privado; nunca
   argumentos con claves ni cuentas RPC desbloqueadas. Para suspended, conservar
   revoke y retirar issue; ACTOR_PLATFORM/DEPLOYMENT/INSTITUTION/I/SIGNER/KEY son
   valores existentes revisados, no literales para ejecutar:

   ```powershell
   npx --yes deno@2.2.12 run --allow-env --allow-net --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts configure ACTOR_PLATFORM DEPLOYMENT INSTITUTION I SIGNER false true KEY
   # Sesión administrativa separada con EVM_ADMIN_PRIVATE_KEY:
   npx --yes deno@2.2.12 run --allow-env --allow-net --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts admin-worker CONFIG_OPERATION
   ```

   Confirmar configuración canónica con otra pasada. Verified puede conservar
   true/true; canIssue no es condición para revoke. Retirada total bloquea nuevas
   firmas. Rotación conserva I y exige ledger exclusivo íntegro del nuevo EOA.

3. Configurar/publicar endpoints cuando el operador autorice el despliegue:

   ```powershell
   supabase functions deploy revoke-certificate --project-ref PROJECT_REF
   supabase functions deploy revocation-progress --project-ref PROJECT_REF
   supabase functions deploy reauthorize-revocation --project-ref PROJECT_REF
   supabase functions deploy verify-certificate-v3 --project-ref PROJECT_REF
   ```

   Conservar verify_jwt=true en los tres privados; false solo en públicos. Edge
   recibe EVM_ENVIRONMENT_ID/EVM_RPC_URL de lectura, nunca claves EVM. Publicar
   cliente v3 coordinadamente; clientes v1/v2 siguen compatibles.

4. Ejecutar/reiniciar worker externo, sin EVM_ADMIN_PRIVATE_KEY en su entorno:

   ```powershell
   npx --yes deno@2.2.12 run --allow-env --allow-net --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts worker
   # Pasada focalizada sobre operación existente:
   npx --yes deno@2.2.12 run --allow-env --allow-net --frozen --config supabase/functions/deno.json supabase/admin/blockchain.ts worker OPERATION
   ```

   Revisar/reautorizar bloqueos desde la UI owner/admin. Reconciliar TODOS los
   intentos antes de reautorizar. No editar status/canonical_attempt/nonces para
   fabricar éxito. Restaurar ledger/bytes exactos; un deployment nuevo no sustituye
   obligaciones anteriores. Disabled/writes_stopped/reset requieren revisión de
   identidad y recuperación, nunca escritura automática en otro contrato.

5. Comprobar SQL mediante progreso Auth; v3 público debe seguir revoked aun con
   EVM activo o caído. Tras worker contrastar receipts/eventos/C/I/bloques canónicos
   de issue y revoke separados. No usar fecha checked_at como revokedAt EVM. Una
   coincidencia PDF/apertura no acredita vigencia. Anvil finality=not_applicable.

6. Limpiar solo recursos propios. El runner crea y destruye su stack/Anvil/red y
   temporales; no ejecutar reset sobre el entorno habitual. Para un stack del
   preparador interrumpido:

   ```powershell
   ./supabase/tests/stop_disposable_local.ps1 -Root RUTA_EXACTA_DEVUELTA
   ```

   Nunca borrar certificados/PDF completed para resolver un fallo EVM. Retención
   de raw y backups privados sigue BLOCKCHAIN_OPERATIONS. No desplegar Sepolia ni
   financiar signers reales como parte de esta aceptación.

## Demo local

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1
# HTTP/SQL/Anvil sin acreditar Flutter:
./supabase/tests/run_phase10.ps1 -BackendOnly
```

Android archivos conserva incidencia 9E; Android completo/iOS/Safari/Firefox,
Sepolia/finalidad PoS y accesibilidad humana requieren evidencia propia.
Cámara SKIP/NOT_RUN: «Omitidas por instrucción del usuario; no hay cámara física disponible».
