# Aceptación local — Fase 9D

## Actualización CI observada — 14/10/2026

Base integrada publicada `7737d303d6e3aa956481cbb7ca7cc2884426d7d8`:
[verification 38542815011](https://github.com/benjvm/certichain/actions/runs/38542815011),
[anchoring 38542814969](https://github.com/benjvm/certichain/actions/runs/38542814969),
[database 38542814699](https://github.com/benjvm/certichain/actions/runs/38542814699) y
[blockchain 38542814693](https://github.com/benjvm/certichain/actions/runs/38542814693).
API run/jobs consultada el 14/10: SHA coincidente, intento 1, completed/success,
pasos de integración reales y limpieza success. Incluye fix del contador público
v2/aislamiento por página/duplicados tardíos. **CI 9D observada success para ese
SHA**; no acredita cambios posteriores de 9E.
Se conserva íntegramente el registro del 13/10 y sus intentos/NOT_OBSERVED
anteriores a publicación, que son históricos. Aceptación nueva:
[PHASE9E_ACCEPTANCE](PHASE9E_ACCEPTANCE.md).

Fecha: 13/10/2026. **Implementada y validada localmente; apta para iniciar 9E.**
Sin commit, push, merge ni publicación remota. Base local/remota revalidada:
`e39dd40118139d1bf05d944b2b2926abcae53622`; árbol limpio al comenzar, sin cambios
posteriores remotos en la inspección. Las ejecuciones nuevas identifican ese HEAD
con working_tree_dirty=true: acreditan fuentes locales, no CI de un commit nuevo.

## Contratos y archivos

| Área | Entrega |
|---|---|
| Decisión/API | [ADR-0017](adr/0017-public-blockchain-evidence-and-private-opening.md), [BLOCKCHAIN_VERIFICATION](BLOCKCHAIN_VERIFICATION.md) |
| SQL | [Migración nueva](../supabase/migrations/20261013110000_blockchain_verification_opening.sql), lookup_public_certificate_v2 y authorize_certificate_opening, sin tablas/grants nuevos |
| Público | verify-certificate-v2/{index,handler,contract,observation,handler_test}.ts; VerificationBackend, strict_json y PublicEvmReader |
| Privado | certificate-opening/{index,handler}.ts; JWT/Auth real, permiso actual, apertura mínima/no-store |
| Flutter institucional | issuance/domain/anchoring_repository.dart; SupabaseAnchoringRepository, AnchorReceiptPreferences, AnchoringController/Panel; InstitutionWorkspace conectado |
| Titular | HolderBlockchain y OpeningAction en el detalle; transporte público propio, sin anchor-progress; apertura explícita |
| Cálculo local | blockchain_verification.dart, blockchain_models.dart, ProtocolOpeningTools, JSON pickers y OpeningCheckController/Panel; SHA-256 existente |
| Composición | main.dart, app/authenticated_area/router; producción v2 y dependencias reales, sin fakes |
| Pruebas | phase9d_test.dart, blockchain_verification.test.sql, phase9d_environment.ts, blockchain_verification_integration.ts, blockchain_verification_browser.mjs, run_phase9d.ps1 |
| CI | verification.yml nuevo; database.yml conserva checks y explicita cámara=0; helper Node/suites mixtas excluyen solo cámara |

v2 POST credential_code solamente, schema_version='2', registry v1 **literal** y
blockchain mínimo. Registro/cadena/copia/apertura son juicios separados. Ausencia
uniforme/null sin EVM; off_chain_only sin anchor. Estados pending/included/
confirmed/reorged/unavailable/divergence y finality independiente. Anvil confirmado
es not_applicable. No fechas/transacciones/bloques ficticios ni fallback v1.

Una lectura SQL coherente conserva completed/coherencia. Tablas 9C privadas,
sin SELECT/DML cliente. RPC estrechas SECURITY DEFINER/search_path vacío y
EXECUTE técnico. No blockchain_job ni snapshots operativos en el cliente.
Deshabilitar un deployment conserva su anchor/apertura original; reset no convierte
esa evidencia en off_chain_only ni habilita un manifiesto histórico como vivo.

PublicEvmReader sin privateKey, lista de métodos lectores, runtime/versión/genesis/
deployment, K/C/I, calldata/evento/receipt/estado/canonicidad. Null/timeout no prueban
ausencia/reorg. Fecha/fuente actuales y last_evidence anterior con fecha intacta.
Bloqueo técnico no inventa reorganización. Revocación SQL/EVM diferente produce
divergence. Total 12 s, tamaños/UTF-8/duplicados/tipos/hex/fechas/enteros acotados,
latencia medida en Server-Timing. Error SQL/registro es 503; EVM puede ser parcial.
Presupuesto único global 60 POST/60 s compartido con v1/compare, incluidos inválidos,
Retry-After, OPTIONS sin consumo y sin polling/reintento automático.

Apertura Auth: titular propio (también emisor suspendido), owner/admin/issuer
actual de verified; no plataforma implícita. Vínculos/H/K/I/S/C revalidados.
Devuelve versión/código/I/H/S/red/contrato, sin PDF/Storage/raw/nonces/claves.
Obtener/copy/export/import son explícitos. JSON <=2 KiB y PDF >0/<=8 MiB locales;
ningún upload de PDF/apertura/salt. Código/red/contrato/I/K/C, documento no
coincidente, apertura inválida y evidencia no comprobable diferenciados. Coincidir
no elimina revocación/caducidad ni acredita identidad. H/S/apertura no se guardan
en preferencias/QR/enlaces/analytics/caché persistente; salida/identidad/token
invalidan referencias y respuestas. Las copias externas quedan bajo control del
usuario, sin promesa de retirada.

Anclaje usa publicación existente, confirmación, clave guardada antes del POST,
scope usuario/institución/certificado, respuesta perdida recuperable, estados e
IDs reales, refresco manual y reautorización explícita. Sin worker queda pendiente;
Flutter no lo ejecuta ni firma. Operaciones existentes siguen consultables si
deja de ser elegible para un anclaje nuevo. Refresh de token/logout/expiración/
dispose/A→B descartan trabajos privados. Titular solo lee proyección pública.

## Validación ejecutada

Windows x64, Docker Desktop, Flutter **3.47.4**/Dart **3.13.3** (9584c6713b),
Supabase CLI **2.117.0**, Deno **2.2.12**, Node **24.14.0** para regresiones/herramientas
Web; Node host 22.14.0 para bootstrap previo. Foundry/Solidity y locks 9B intactos.
Anvil Linux congelado en contenedor/red propios, host binding 127.0.0.1, Edge
conectado a su DNS privado. Nuevo despliegue normal firmado, administrador y
operativo distintos, sin manifests sintéticos/históricos. No cámaras ni Sepolia.

| Comando/comprobación | Resultado local |
|---|---|
| dart format lib test tool; --output=none --set-exit-if-changed | PASS, sin cambios pendientes |
| flutter analyze | PASS, sin incidencias |
| flutter test (CERTICHAIN_TEST_CAMERA=0) | **228 PASS**, 12 SKIP: 11 cámara y 1 integración Supabase opt-in existente |
| Deno fmt/lint/check --frozen y test functions | **95 PASS** (81 previos + 14 nuevos); tipos/formato/lint sin errores |
| Supabase reconstrucción/test db del runner | **860 PASS** (825 previos + 35 nuevos), esquemas completos |
| Supabase db lint public,certichain_private --fail-on warning | PASS, sin errores de esquemas propios |
| run_phase9d.ps1, main.dart release HTTPS | **164 checks navegador**, 26 checks HTTP/Anvil, exit 0 |
| run_phase9d.ps1 -BackendOnly, comprobación adicional admin | **27 checks HTTP/Anvil PASS**, 860 SQL/lint y limpieza; no acredita Flutter por sí sola |
| public_verification_http.mjs | **296 PASS**, v1, Auth anónimo y presupuesto atómico real |
| hash_comparison_http.mjs | **255 PASS**, v1 y concurrencia/presupuesto compartido |
| certificate_pdf_http.mjs | **90 PASS**, Auth/permisos/suspensión y caducidad real de capacidad |
| private_storage.mjs | PASS, operaciones cliente denegadas y bytes privados conservados |
| release_verification_browser.mjs actualizado para reconocer v2 | **126 checks**, 11 verify y 24 compare POST, sin cámara; recarga/historial/fallos/cooldown/logout |
| Node browser_harness_test + edge_runtime_test | **10 PASS**, 1 callback de captura SKIP con motivo exacto |
| QR PNG generado por Flutter y verify_qr.mjs | PASS, decodificación estática independiente del enlace exacto |
| backend-abi.mjs --check; diff de blockchain/migración 9C/locks | PASS, protocolo/ABI/contrato/migraciones compartidas/dependencias intactos |
| actionlint workflows y git diff --check | PASS local; no ejecuta CI remoto |

Recorrido sobre **main.dart de producción**: Auth real → emitir por UI/7B →
solicitar anclaje desde Flutter (POST único, solicitado) → worker confiable del
harness, firmado/persistido/enviado fuera de Edge → refrescar estado confirmado
en Flutter → titular comparte QR/enlace existentes y consulta evidencia v2 →
obtiene/exporta apertura por acciones explícitas → navegador anónimo importa
esa exportación y selecciona original/copia alterada → match/PDF mismatch local,
sin POST adicional. No se acredita este recorrido mediante fakes.

Se pausó realmente el Anvil propio: v2 mantiene registry y unavailable, con
fecha original anterior; recuperación manual restaura evidencia. EVM snapshot/
revert real invalida bloque, conserva receipt y reincluye el mismo compromiso
por worker. EVM revoke técnico de fixture, con SQL activo, produce divergence:
**no** acredita revocación de producto 10. Opening/progreso deniegan al titular
ajeno, plataforma sin membresía, miembro retirado/suspendido; titular propio
con emisor suspendido conserva apertura. SQL prueba vínculo cruzado y permisos
API sin ampliar RLS.

Una respuesta de apertura autorizada **real** se retuvo en el proxy del harness,
se hizo logout, y después se entregó: no aparece en la cuenta/ruta posterior.
Renovación de token y scopes/dispose se prueban también mediante SDK/controladores;
el recorrido anterior mantiene aislamiento real de cuenta e historial. Parsers
rechazan DTOs/JSON malformados, duplicados escapados, fechas, enteros, límites,
contrato/código distintos y campos extra. Layout 320 px/texto ×2 sin overflow.

Evidencia sanitizada: `mobile/build/phase9d-evidence/result.json` con HEAD/dirty,
fecha, etapas y contadores (1 emisión, 1 anclaje, 2 apertura, 5 públicos); sin
JSON/capturas de apertura, H/S, PDFs privados, raw tx o credenciales. Inputs y
exportación sintéticos solo en directorio temporal propio y retirados en finally.
Se limpiaron Anvil/red/Edge/stack propios; no se reseteó el entorno habitual.

Fallos de desarrollo conservados como historia: sintaxis de resta jsonb del test
SQL (parentizada); skip de testWidgets exige bool, a diferencia de test (corregido,
con motivo impreso); callback opt-in del helper excluido de aceptación; interacción
de login/foco/viewport del harness ajustada; iterador Node/Deno de GET vacío
bloqueaba Rest (lectura solo de cuerpos reales); enlace seleccionable no se valida
por AX name, sino mediante Copiar enlace/clipboard real; tipo never al modificar
receipt en callback (lectura tipada posterior); const Text dinámico corregido;
un lock temporal de fichero durante compilaciones solapadas impidió un formateo,
repetido limpiamente. Ningún intento fallido se cuenta como PASS final.

## CI, configuración y pendientes

Registro histórico del 13/10/2026: base reconsultada por GitHub: runs **38316317965**, **38316317900**, **38316317855**,
intento 1, success y pasos/jobs ejecutados para e39dd401…; actualización en
[aceptación 9C](PHASE9C_ACCEPTANCE.md) preservando historia. **CI de 9D NOT_OBSERVED**:
no hay commit/publicación nueva, por instrucción del usuario. verification.yml
prepara Ubuntu 24.04, herramientas/SDK/acciones congeladas, SQL antes de fixtures,
Auth/Edge/Anvil/Flutter reales, parada always y resumen sanitizado exclusivo.
Sin continue-on-error, secretos reales, skips amplios, cámaras o testnet.

Operador: aplicar únicamente la migración nueva al proyecto local revisado;
registrar deployment vivo nuevo y configurar binding I/signer por la vía 9C;
poner EVM_ENVIRONMENT_ID y **EVM_RPC_URL lector solo en Edge/backend**, conectando
su red privada (anvil:8545). Mantener claves de administración/firma únicamente
en el host/entorno del worker confiable. Flutter conserva SUPABASE_URL,
SUPABASE_PUBLISHABLE_KEY y PUBLIC_VERIFICATION_BASE_URL; ninguna URL/clave EVM.
Ejecutar worker explícitamente; no activar cron remoto. Comandos detallados y
límites en [BLOCKCHAIN_VERIFICATION](BLOCKCHAIN_VERIFICATION.md) y
[BLOCKCHAIN_OPERATIONS](BLOCKCHAIN_OPERATIONS.md).

9E mantiene aceptación ampliada de fallos/recuperación y plataformas. JSON picker/
export nativos Android/iOS no demostrados en dispositivo; widgets y análisis sí,
recorrido Web real sí. La nueva CI Linux debe observarse para un SHA que publique
posteriormente el operador. No se repite toda la campaña Foundry/9C porque sus
fuentes no cambian; se verifican ABI/diff y anclaje/lectura reales. Sepolia/finality
PoS no ejecutadas. 10 conserva revocación Auth/SQL/EVM de producto pendiente.
Sin wallet EVM de alumno, NFT/token, autoservicio, backfill ni cron.

Cámara **SKIP/NOT_RUN**, CERTICHAIN_TEST_CAMERA=0:
«Omitidas por instrucción del usuario; no hay cámara física disponible».
Conservar funcionalidad/tests; solo se excluyen sus escenarios, incluidos dobles.
El hardware no bloquea 9D/9E ni reabre 8D.

**Dictamen: apto para iniciar 9E localmente**, con cliente/backend real, evidencia
honesta, apertura protegida y comprobación documental local. No hay bloqueo de
implementación abierto; publicación/CI y validaciones de plataforma indicadas
son pendientes explícitos, sin atribuirles ejecución ni aprobación remota.
