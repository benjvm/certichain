# Demo local del ciclo completo

El recorrido usa `mobile/lib/main.dart` en Web release por HTTPS, Auth/SQL/Storage/Edge reales y un Anvil propio. El worker firma en un proceso confiable fuera de Flutter y del lector público. La [aceptación vigente](PHASE10_ACCEPTANCE.md) incluye emisión, apertura, verificación y revocación.

## Preparación

Instalar las versiones y resolver los requisitos de [DEVELOPMENT](DEVELOPMENT.md): Node 24.14.0, Supabase CLI 2.117.0, Flutter 3.47.4/Dart 3.13.3, PowerShell 7+, Docker Linux, Chrome y OpenSSL. Deno y la toolchain de contratos se invocan desde los wrappers fijados.

Mantener libres API/BD 55321/55322 y HTTPS 7360 sin parar servicios ajenos. Los runners mutables se ejecutan secuencialmente. No aportar usuarios, documentos o claves reales.

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
./supabase/tests/run_phase10.ps1 -VisibleBrowser
# Mismo recorrido sin ventana visible:
./supabase/tests/run_phase10.ps1
# Solo backend; no acredita Web:
./supabase/tests/run_phase10.ps1 -BackendOnly
```

El runner instala dependencias congeladas, verifica herramientas y artefactos, crea un stack fuera del checkout, ejecuta SQL antes de los fixtures, despliega un contrato nuevo y configura emisor/firmante sintéticos. Chrome y TLS son propios de la ejecución. Es automatizado: no pulsar simultáneamente sus controles.

## Recorrido mostrado

1. Una institución verified emite el PDF privado. El titular abre wallet/detalle y obtiene documento, código, QR/enlace y apertura autorizada.
2. Una solicitud explícita crea el anclaje; el worker firma, envía y confirma el issue real. Publicación SQL y evidencia blockchain se muestran separadas.
3. Owner/admin abre revocación, introduce un motivo privado, cancela una vez y confirma. La respuesta aceptada se descarta deliberadamente para demostrar recuperación con la misma clave.
4. Wallet y verificador muestran SQL revocado antes de confirmar revoke, también con el RPC temporalmente indisponible. Una coincidencia PDF nunca se presenta como vigencia.
5. Tras recuperar RPC/worker, actualizar manualmente muestra issue y revoke como operaciones/evidencias distintas. La finalidad PoS no aplica a Anvil.
6. Una respuesta privada retenida se entrega tras logout/cambio de cuenta y no reaparece en la UI. Las comprobaciones también cubren QR estático, archivo original/alterado y presupuesto público.
7. Se limpian los recursos propios y se finaliza la evidencia de esta pasada.

## Interpretación de fallos

| Síntoma | Acción |
|---|---|
| Toolchain preflight | Corregir la selección de versiones, sin desactivar el gate |
| Readiness Auth/REST | Consultar la categoría cerrada; no tratar cualquier 401 como un fallo temporal |
| Pending sin worker | Ejecutar el worker explícito; no fabricar confirmación |
| Blocked/failed | Corregir causa, reconciliar intentos y reautorizar con permisos actuales |
| Divergence/reset | Revisar identidad de deployment/cadena y evidencia; no reenviar a otro contrato |
| 429 | Respetar Retry-After; recuperación por acción manual |
| Cleanup fallido | Conservar FAIL y revisar exclusivamente recursos de esa ejecución |

Para contratos/recuperación usar [BLOCKCHAIN_OPERATIONS](BLOCKCHAIN_OPERATIONS.md) y [REVOCATION](REVOCATION.md). Los pasos alojados/testnet son manuales y no forman parte de esta demo.

## Evidencia y limpieza

Revisar `mobile/build/phase10-evidence/{run,preflight,result,full,browser}.json`: mismo run_id, SHA/dirty, modo y fechas, resultado final y stack_cleanup. `history/<nuevo-run_id>/` conserva el juego anterior. Un navegador antiguo no acredita la pasada actual. Backend-only no acredita Flutter.

No compartir dumps, PDF, aperturas, salts, tokens, raw transactions ni capturas privadas. Si se interrumpe el preparador, usar su ruta exacta:

```powershell
./supabase/tests/stop_disposable_local.ps1 -Root EXACT_DIRECTORY_RETURNED_BY_PREPARER
```

No resetear el stack habitual ni vaciar Temp global. La cadena nueva no reconstruye el anclaje previo; el manifiesto de una ejecución descartada es evidencia histórica.

Cámara SKIP/NOT_RUN: «Omitidas por instrucción del usuario; no hay cámara física disponible». Mantener `CERTICHAIN_TEST_CAMERA=0`. Códigos, enlaces, QR de imagen estática, PDF, Auth, SQL y blockchain conservan sus pruebas. El cierre Web no acredita Android/iOS completos, otros navegadores, accesibilidad humana, Supabase alojado o Sepolia.
