# Checklist del operador — cierre 8D y entrada 9A

Estado: 12/10/2026. Commit publicado evaluado:
`2066e908af30913462cf3daf77324eab2a63dfc4`. Esta revisión no hace commit, push,
merge, rerun remoto ni despliegue. Evidencia y matriz en
[PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md).

## CI técnica vigente e historia

- [x] Confirmado [run 38280055013](https://github.com/benjvm/certichain/actions/runs/38280055013),
  intento 1, SHA `2066e908af30913462cf3daf77324eab2a63dfc4`: database
  114914890741, flutter 114914890996, android 114914891175 success con pasos
  ejecutados. Run/intento/jobs reconsultados; CERTICHAIN_TEST_CAMERA='0'.
  Android acredita build debug, no recorrido real; no blockchain ni cámara física.
- [x] Se conserva el fallo histórico [run 37373509169](https://github.com/benjvm/certichain/actions/runs/37373509169),
  intento 1, con las tres anotaciones sanitizadas documentadas y enlaces históricos:
  [database](https://github.com/benjvm/certichain/actions/runs/37373509169/job/111976231865),
  [flutter](https://github.com/benjvm/certichain/actions/runs/37373509169/job/111976231713)
  y el [workflow](https://github.com/benjvm/certichain/actions/runs/37373509169/workflow).
  Ambos jobs: runner hosted no adquirido tras varios intentos; workflow: error
  interno, correlación `6242d09f-3d5d-4096-bdbb-8e8b882693e7`.
- [ ] Si se publican cambios posteriores por encargo separado, obtener CI de ese
  SHA. Este encargo 9A no autoriza commit/push/rerun y no requiere repetir 8D.
  No reejecutar el fallo histórico únicamente por pendientes de cámara.
- [ ] Revisar `phase8d-release-evidence` del run success si se necesita aceptación
  detallada de sus artefactos (no descargados en 9A). Revisar result.json,
  versiones, etapas, tiempos, contadores y capturas sintéticas; comprobar que no
  contiene credenciales, URLs firmadas, config sensible ni payloads privados.
  El run cancelado no produjo este artefacto.

## Reproducción local y limpieza

Solo cuando una tarea requiera regresiones ejecutables: CERTICHAIN_TEST_CAMERA=0
en todos los harnesses. Cámara SKIP/NOT_RUN con motivo exacto
«Omitidas por instrucción del usuario; no hay cámara física disponible».
La configuración antigua opt-in no autoriza activarla. En suites mixtas excluir
solo escenarios de captura/permisos/ciclo de vida; mantener códigos, enlaces,
QR/imagen estática, PDF, Auth y SQL. No resets ni nueva reproducción por 9A.

- [ ] Usar PowerShell 7, Node 24.14.0, Flutter 3.47.4/Dart 3.13.3,
  Supabase CLI 2.117.0 y Deno 2.2.12; Docker Linux, Chrome y OpenSSL disponibles.
- [ ] Desde raíz ejecutar `./supabase/tests/run_phase8d.ps1` y la validación
  ampliada `./supabase/tests/run_phase8d.ps1 -Full`. Registrar exit/etapa real;
  si se ejecutan etapas sueltas, no afirmar que pasó el comando completo.
- [ ] Identificar el nuevo directorio `certichain-8d-<GUID>` y project_id
  `certichain_8d_<8 hex>` antes de detener/borrar. Puertos 55320–55329/9083/7358.
  **Nunca db reset sobre certichain habitual/54321**. No suites simultáneas
  que alteren fixtures o presupuesto. Preservar estado inicial y volúmenes habituales.
- [ ] Confirmar finally: proceso serve/navegador propios terminados, fixtures y
  presupuesto restaurados, solo stack propio eliminado. Si stop falla, conservar
  su directorio e inspeccionar; usar `stop_disposable_local.ps1 -Root <ruta propia>`.
- [ ] Temporal Edge histórico pendiente:
  `C:\Users\bensa\AppData\Local\Temp\certichain-release-8d-467qzA`.
  El 10/10 se verificaron fecha 05/10, archivos sintéticos y perfil propio, sin
  procesos chrome/edge/node con esa ruta. El borrado volvió a ser rechazado
  automáticamente («blocked by policy»). Cerrar procesos asociados si aparecen,
  comprobar **esa ruta exacta** y eliminarla manualmente desde el Explorador.
  Contiene clave TLS local/perfil; no compartir su contenido. No vaciar Temp global.
- [ ] La limpieza final de estos archivos propios también fue rechazada
  automáticamente («blocked by policy»); no se volvió a intentar con otra herramienta:
  `C:\Users\bensa\AppData\Local\Temp\certichain-closure-emulator-out.log`,
  `C:\Users\bensa\AppData\Local\Temp\certichain-closure-emulator-error.log` y
  `C:\Users\bensa\AppData\Local\Temp\certichain-closure-emulator-pid.txt`.
  Verificar que la instancia propia terminó antes de quitar **solo esos archivos**
  manualmente. Un PID guardado puede reutilizarse; no matar procesos por él sin
  confirmar identidad. La imagen local de smoke `certichain-cdp-linux-closure`
  queda como caché propia (la orden de limpieza conjunta no se ejecutó); el
  operador puede quitar solo ese tag con `docker image rm certichain-cdp-linux-closure`.
  Contenedores/volúmenes descartables y emulador están detenidos/eliminados;
  los volúmenes certichain e internhub ajenos se preservaron.

## Aceptación humana y plataformas

- [ ] Android: pruebas independientes de cámara en entorno dedicado, conservando
  PDF/Auth/códigos/manual/enlaces/QR de imagen estática. Probes de cámara y QR
  nativo **NOT_RUN** por instrucción vigente; timeout histórico conservado.
- [ ] Ejecutar en Android **main.dart completo** con cuentas sintéticas y HTTPS
  accesible al dispositivo: emisor→emisión→titular→descarga→QR→anónimo→comparación.
  Separarlo de probes aislados y compilación. No sobrescribir instalación personal.
- [ ] Cámara Web/Android/iOS, física o emulada: **SKIP/NOT_RUN**, nunca PASS.
  «Omitidas por instrucción del usuario; no hay cámara física disponible».
- [ ] Selector: cancelar/cambiar/salir durante lectura/hash/consulta; vacío,
  8 MiB y 8 MiB+1; conservar original, comprobar copia propia liberada.
- [ ] A 320 px y texto ×2, recorrer con Tab/Shift+Tab/Enter, revisar foco visible y
  orden lógico, lector de pantalla y anuncios de carga/errores/resultados.
  Verificar alternativa manual y distinguir «Certificado revocado» de «El PDF coincide».
  Un error debe identificar resultado y checked_at anteriores.
- [ ] Registrar Firefox/Safari/iOS solo si se ejecutan en sus entornos. No convertir
  tests semánticos ni cámara emulada en revisión humana/cámara física PASS.
- [ ] Detener únicamente emulador/procesos propios, desinstalar solo paquete de prueba
  y quitar fixtures propios; no guardar snapshot read-only ni borrar datos personales.

## Limitación futura de lanzamiento

El límite global compartido 60 POST/60 s sirve a la demo; cualquiera puede agotar
el cupo de todos. Antes de lanzamiento público diseñar protección de ingress,
equidad, concurrencia, carga y observabilidad mínima. No bloquea el diseño aislado
9A, pero no es aceptación de tráfico público. Blockchain, revocación de producto
y recuperación de contraseña siguen fuera de este cierre.

Base técnica validada por CI del SHA indicado para iniciar 9A; diseño 9A entregado.
Aceptación humana/lanzamiento conservan sus límites. Cámara omitida no bloquea
fases siguientes ni reabre 8D; no atribuirle PASS por success de otros checks.
