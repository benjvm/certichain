# Checklist del operador — cierre 8D y entrada 9A

Estado: 10/10/2026. Commit publicado evaluado:
`62354866e1c127e445c369bedee58742581ec2cd`. Esta revisión no hace commit, push,
merge, rerun remoto ni despliegue. Evidencia y matriz en
[PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md).

## Bloqueo técnico CI

- [ ] Abrir autenticado el [run 37373509169](https://github.com/benjvm/certichain/actions/runs/37373509169),
  intento 1, y conservar las tres anotaciones sanitizadas. Revisar
  [database](https://github.com/benjvm/certichain/actions/runs/37373509169/job/111976231865),
  [flutter](https://github.com/benjvm/certichain/actions/runs/37373509169/job/111976231713)
  y el [workflow](https://github.com/benjvm/certichain/actions/runs/37373509169/workflow).
  Ambos jobs: runner hosted no adquirido tras varios intentos; workflow: error
  interno, correlación `6242d09f-3d5d-4096-bdbb-8e8b882693e7`.
- [ ] Comprobar disponibilidad de GitHub Actions y reejecutar **como operador**.
  Si persiste el mismo mensaje, contactar soporte GitHub con run, intento,
  commit, ventana UTC 05/10 21:03:17–21:18:18 y correlación. No atribuirlo a
  facturación/cuotas sin un mensaje que lo indique. No ampliar timeouts ni retirar checks.
- [ ] Revisar/publicar los cambios locales por el procedimiento habitual. Después
  ejecutar el workflow para **ese nuevo SHA**; un rerun de 6235486 no valida el
  working tree posterior. El workflow se dispara por push a main o pull request.
- [ ] Confirmar success de **database y flutter**, con pasos ejecutados, para el
  SHA que vaya a aceptarse. Mantener Chrome platform tests y main.dart release.
  Un resultado local o el success 8C de 37350396753 intento 2 no basta.
- [ ] Descargar `phase8d-release-evidence` de ese run. Revisar result.json,
  versiones, etapas, tiempos, contadores y capturas sintéticas; comprobar que no
  contiene credenciales, URLs firmadas, config sensible ni payloads privados.
  El run cancelado no produjo este artefacto.

## Reproducción local y limpieza

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

- [ ] Android: emulador dedicado/read-only sin paquete com.example.mobile previo;
  probes PDF/cámara reales, imagen QR compatible con la base configurada y decoder
  real. Distinguir permiso, inicio, imagen capturada y código decodificado.
  Registrar timeout de póster como pendiente, nunca sustituir detección por UUID fake.
- [ ] Ejecutar en Android **main.dart completo** con cuentas sintéticas y HTTPS
  accesible al dispositivo: emisor→emisión→titular→descarga→QR→anónimo→comparación.
  Separarlo de probes aislados y compilación. No sobrescribir instalación personal.
- [ ] Cámara física Web/Android/iOS: denegar/conceder/revocar; QR impreso/otra
  pantalla; doble detección/confirmación, ocupada/ausente, fondo/regreso/cierre.
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

La aceptación técnica exige CI del SHA exacto y regresiones necesarias. La humana
requiere la revisión anterior. Documentar ambas por separado antes de declarar
«Base validada para iniciar 9A».
