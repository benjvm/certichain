# ADR-0018 — Decisión irreversible, compensación EVM y evidencia pública v3

- Fecha: 15/10/2026.
- Estado: accepted para demo Web local; evidencia en [PHASE10_ACCEPTANCE](../PHASE10_ACCEPTANCE.md).

La autorización de emitir no autoriza revocar: owner/admin ACTUALES de la emisora
verified o suspended, con Auth no anónimo, no eliminado ni bloqueado. Plataforma
sin membresía, issuer y titular no heredan permiso. Suspender no revoca.

Una transacción padre primero (institución → publicación → certificado → binding
→ anchor → operación → nonce) guarda decisión privada y status/revoked_at SQL.
No llama RPC EVM ni Storage. La publicación completed, código, PDF, H/S/K/C/I e
historial permanecen intactos. Históricos activos son revocables, sin aumentar su
elegibilidad pública/documental/de anclaje. Históricos revocados no reciben actor,
motivo o fecha nuevos. Guards protegen identidad e irreversibilidad aun frente al
antiguo bypass de platform_admin; ninguna recuperación reactiva SQL.

certificate_revocations contiene una decisión por certificado; revocation_keys
conserva alias de claves por institución. Texto NFC, CRLF/CR→LF, trim ASCII
espacio/tab/LF, 1–500 puntos Unicode, controles salvo tab/LF y surrogates inválidos
rechazados. Huella SHA256 de UTF8("certichain:revocation-request:v1") || 00 ||
uuid_send(certificate_id) || UTF8(motivo canónico), calculada en SQL.
Igual clave/huella recupera; distinta huella conflictúa; otra clave recupera la
primera decisión sin sobrescribirla. Motivo se representa como texto, nunca HTML.
Solo owner/admin actuales de verified/suspended consultan el motivo por RPC Auth;
no tablas privadas para service_role ni SELECT público nuevo.

Sin anchor no se crea uno. Issue sin firma persistida pasa al estado técnico
privado cancelled, invalida lease/generation y libera solo su reserva sin intentos.
Persist-before-broadcast hace seguro ese cierre. Issue firmado no se puede
desfirmar: una operación revoke única del mismo anchor conserva la obligación,
también si su deployment dejó de ser el habilitado actual. Read null/timeout no
cancelan esa obligación. Reconciliar issue tardío compatible es legítimo cuando
SQL está revocado y existe compensación; C/I incompatibles siguen siendo divergence.

El coordinador observa firmas previas aunque cambie la membresía. Nuevas firmas,
incluidos replacements, exigen autorización vigente; blocked/failed requieren
reautorización explícita auditada después de observar todos los intentos. Revoke
usa I almacenado y canRevoke, nunca canIssue. Se mantienen ADR-0016, nonces,
CAS, límites y claves solo en host confiable. Deployment deshabilitado/reset o
writes_stopped bloquea firmas, sin trasladar obligaciones a otro contrato.
Reorg conserva SQL revoked e historial; se concilian issue y revoke separadamente.

v1/v2 son cerrados: v3 añade un bloque revocation explícito, con fecha SQL,
estado de sincronización y receipt de revoke separado del hash de issue. La
proyección técnica se obtiene en una sentencia con la misma elegibilidad que v2.
El lector valida deployment, canonicidad, calldata/evento/estado y C/I; nunca
encola ni firma. v2 conserva sus campos y su divergence conservadora mientras SQL
y EVM discrepan. El cliente v3 explica además la demora esperada. Ningún receipt
se convierte en actual al fallar RPC; last_evidence mantiene su fecha observada.
Anvil no demuestra finalidad PoS. Comparación PDF y vigencia son independientes.

Alternativas descartadas: pending_revocation público, esperar EVM antes de SQL,
motivo en calldata/metadata, authorize_issuance para revoke, nuevo ledger,
salts nuevos, inventar auditoría histórica, cambiar v1/v2 silenciosamente o saltar
nonces desconocidos. No hay nuevas dependencias de producto.
