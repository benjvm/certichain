# Aceptación específica 10D — Cliente y verificación de la revocación

18/10/2026. Base main/HEAD `bb17d346d1100ecf42b78f6ad3cae0abbe500c44`, árbol
inicial limpio. Cambios locales sin commit/push/merge/despliegue. Se conservan
10A–10C y los resultados históricos de [fase 10](PHASE10_ACCEPTANCE.md).
La ejecución nueva lleva dirty=true; no acredita Actions del futuro commit.

## Revisión y cambios

Ya existían feature revocation con tres capas, endpoints privados, claves por
ámbito, confirmación irreversible, permisos owner/admin verified/suspended,
badges wallet/detalle y lector público v3. Se completan esos componentes sin
rehacerlos ni cambiar backend, EVM, ABI, Solidity, ledger, coordinador, SQL,
RLS, migraciones o dependencias.

- Motivo NFC, CRLF/CR a LF, trim exclusivamente espacio/tab/LF y longitud
  1–500 puntos Unicode, como el handler/ADR-0018. Rechazo de C0 salvo tab/LF,
  DEL y surrogates inválidos; C1 se conserva como en el contrato vigente.
  Contador por puntos, validación accesible y diálogo desplazable con título/ID.
  Cancelar no hace POST; doble pulsación no repite el envío.
- Motivo canónico congelado solo en memoria y UUID persistido antes de HTTP
  por cuenta/institución/certificado. Obtenciones concurrentes comparten clave;
  clave corrupta da error sin sustitución silenciosa. Transporte incierto explica
  que SQL puede haber aceptado. Consulta o reenvío del mismo intento son explícitos.
- Retirada del refresco de workspace que desmontaba el panel cada 30 s. Lecturas
  al entrar, actualizar, cambiar sesión/ámbito o volver del segundo plano. Progreso
  manual sin polling, firma, encolado o reautorización implícitos.
- Reautorización con confirmación propia: continúa sincronización, no decide otra
  revocación. Errores en español, incluidos ocupado/reconciliación y conflictos,
  sin texto upstream. Denegación retira motivo/decisión/acciones. Generaciones
  protegen también callbacks onRevoked; diálogos en navegador privado.
- DTO privado cerrado: parseo saneado, coherencia activos/históricos, motivos
  canónicos, operaciones únicas y estados documentados. 202 solo para request.
- Titular: SELECT añade solo revoked_at ya autorizado. Fecha SQL UTC separada de
  emisión/EVM; ausencia histórica explícita. Badge mantiene texto/icono/color.
  Suspended permite revoke owner/admin, sin habilitar emisión/PDF institucional.
- Público: evidencia de emisión y revocación identificadas por separado. Comparar
  PDF v1 conserva ambos snapshots técnicos anteriores con fecha y etiqueta de
  evidencia no comprobada actualmente, sin consulta adicional. Versiones sin
  bloque de revocación declaran ese límite. Anvil: finalidad no aplicable.

## Privacidad y recuperación

Motivo representado como texto, nunca HTML. No motivo/actor/request_id privado,
H/S, rutas, nonces o raw en titular, público, PDF, QR, enlaces o logs. Preferencias
solo contienen ámbito/UUID, nunca motivo, auditoría, documento o credenciales.
La clave no caduca automáticamente para evitar otro intento tras una respuesta
perdida. Borrar datos del navegador puede perderla; progreso recupera la decisión
existente autorizada. Reconstruir no restaura el motivo: consultar primero o
reintroducir el original; otro contenido con la misma clave conflictúa y no
sobrescribe motivo/actor/fecha/request_id. No se promete retirar copias externas
ni capacidades PDF ya entregadas. Completed/documento/código/evidencia permanecen.

SQL revocado conserva precedencia durante pendiente, bloqueo, fallo, reorg,
divergencia e indisponibilidad EVM. 202 no acredita inclusión/finalidad. Integridad
PDF no acredita vigencia. No cambio de contratos cerrados v1/v2/v3.

## Evidencia nueva

**10D cerrada localmente para la demo Web/Chrome con los límites siguientes.**
Ejecución integral iniciada 16:57:41.391 UTC (18:57:41 Madrid); evaluación Web
17:01:43.556 UTC. Windows x64, Chrome 155.0.8059.84, Flutter 3.47.4/Dart 3.13.3
(revisión 9584c6713b324636289d067944a46fd6b49df14b), Node 24.14.0, CLI 2.117.0,
Deno 2.2.12, Docker 29.8.2, Foundry 1.8.5 y Solidity 0.8.37.

| Comprobación nueva realmente ejecutada | Resultado |
|---|---|
| Formato Dart lib/test | PASS, 136 archivos sin cambios en comprobación final |
| Flutter analyze | PASS, sin incidencias |
| Suite Flutter completa con cámara=0 | PASS, 266 pruebas; 12 SKIP existentes |
| Runner integral run_phase10.ps1, segunda pasada | PASS, 289 checks reales Auth/Edge/Storage/SQL/Anvil |
| Producción main.dart Web release/HTTPS | PASS, 183 aserciones Chrome |
| SQL/RLS | PASS, 978 pgTAP; preservación de históricos y lint PASS |
| Bootstrap fijado/build normal/artefactos/ABI backend | PASS, sin drift |
| Node harness navegador/readiness Edge | PASS, 17; 2 SKIP: cámara y fixture Unix en Windows |
| Sintaxis Node y formato Deno del harness modificado | PASS |
| Enlaces locales de diez documentos y git diff --check | PASS |
| Limpieza de ambos runners | PASS, destinos/red/Anvil/Edge/stack/directorios propios retirados |

Informes sanitizados: mobile/build/phase10-evidence/{full,browser,result}.json y
attempts.ndjson. Logs finales phase10d-full2.log, phase10d-flutter.log,
phase10d-analyze.log y phase10d-node.log bajo mobile/build. El full nuevo conserva
286 checks antes de los tres escenarios finales de reset: 289 totales. El runner
existente incluye esas regresiones propias; no se amplía la campaña 10E.

Web: una emisión, un anclaje, dos POST revoke con la misma clave (respuesta 202
descartada y recuperación 200 de la decisión original), tres aperturas y ocho
POST públicos. Página anónima v1=0/v2=0/v3=7/compare=0: no combina versiones ni
duplica consultas. QR estático decodificado, PDF original/alterado, wallet/detalle
revocados, motivo ausente del titular/público/preferencias, artefacto sin secretos,
RPC caído, refresh explícito y evidencia revoke independiente PASS. Sesión anterior
retenida y cambio owner→otra cuenta descartan la respuesta privada real.

Auth/privacidad/no-store del handler PASS; nueve excepciones genéricas previas del
gateway, diagnóstico estricto FAIL y política revisada de 10B PASS. No se vuelve
a modificar ni ampliar esa excepción. Foundry unitarios y suite Deno de backend
no se repiten en esta revisión del cliente; sus PASS históricos no se atribuyen
como ejecuciones nuevas. Sí se ejecutan build congelado y backend real anteriores.

Logs de desarrollo: mobile/build/phase10d-*.log. Incluyen intentos iniciales FAIL
de expectativas SELECT/refresco y fixtures nuevos; no se cuentan como PASS.
full.json/browser.json previos conservados en phase10-evidence/history/before-10d-*.

Comandos con Node 24.14.0 y toolchains fijadas, CERTICHAIN_TEST_CAMERA=0:

```powershell
# Desde mobile:
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
# Desde raíz:
node --check mobile/tool/blockchain_verification_browser.mjs
node --test mobile/tool/browser_harness_test.mjs supabase/tests/edge_runtime_test.mjs
./supabase/tests/run_phase10.ps1
```

Runner existente sobre stack/red/Anvil/Edge y destinos propios desechables.
La ampliación Web cubre cancelación, pérdida de cuerpo tras aceptación SQL real,
recuperación con misma clave, wallet/detalle, privacidad, RPC caído con SQL revocado,
recuperación y receipt revoke separado. Worker sin ejecutar durante observación
pendiente. Conserva código/enlace, QR de imagen estática, PDF, Auth, SQL y EVM.

El primer runner integral conservó 289 checks backend PASS pero Web FAIL (166
aserciones completadas): no apareció el aviso incierto dentro del deadline al
destruir el socket de respuesta en el proxy. Cleanup PASS; evidencia bajo
history/10d-first-full-fail y attempts.ndjson. La siguiente inyección descarta
el cuerpo completo tras el 202 real y entrega una respuesta vacía terminada,
para comprobar determinísticamente una respuesta ilegible sin ampliar timeouts.
Es pérdida inyectada en la frontera del proxy, no corte del proveedor ni prueba
de red móvil. Ese FAIL inicial no se transforma retroactivamente en PASS.

El lint Deno directo adicional sobre el harness Node informa 10 hallazgos
preexistentes: nueve no-inner-declarations y uno no-unsafe-finally. Se comparó
contra el archivo de HEAD: mismos 10/categorías, sin nuevos hallazgos; no se
reescribe ese código ajeno al alcance ni se afirma PASS de ese lint opcional.
La sintaxis Node y tests del harness se validan con sus comandos anteriores.

Cámara SKIP/NOT_RUN: «Omitidas por instrucción del usuario; no hay cámara física disponible».
Las 12 exclusiones Flutter incluyen además los opt-in locales existentes.
Android/iOS, Firefox/Safari, Sepolia/finalidad PoS, alojamiento, lector de pantalla
y revisión visual humana NOT_RUN. Widgets incluyen 320 px/texto x2/títulos largos,
teclado/foco y etiquetas; no sustituyen revisión humana. Se mantiene el diagnóstico
estricto FAIL y la excepción externa limitada del gateway aceptada en 10B.

10E necesita aceptación integral propia sobre commit final, CI de ese SHA y
guion/recuperación operativos con sus límites. Esta revisión no vuelve a cerrar 10E.

## Archivos

Producción bajo mobile/lib/features/: revocation/domain/revocation_reason.dart,
data/{revocation_key_preferences,supabase_revocation_repository}.dart,
presentation/{revocation_controller,revocation_panel}.dart;
institutions/data/supabase_institution_repository.dart y
presentation/institution_workspace.dart; certificates/domain/certificate_repository.dart,
data/supabase_certificate_repository.dart y presentation/{certificate_detail_screen,
holder_blockchain}.dart; verification/presentation/{verification_controller,
verification_screen,public_revocation_panel,blockchain_evidence_panel}.dart.

Pruebas: mobile/test/{phase10_test,phase10_adapters_test,phase10d_test,
wallet_repository_test,certificate_detail_test}.dart y
mobile/tool/blockchain_verification_browser.mjs. Documentación: esta aceptación,
PHASE10_ACCEPTANCE, REVOCATION, FLUTTER_ARCHITECTURE, STUDENT_WALLET,
INSTITUTION_ADMINISTRATION, PUBLIC_VERIFICATION, SECURITY, TESTING y ROADMAP.
Se aplica ADR-0018, sin decisión estructural nueva que requiera otro ADR.
