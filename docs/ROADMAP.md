# Hoja de ruta del MVP

## Fases de implementación

Estos incrementos registran entregas reales; su numeración es independiente de
las etapas conceptuales del MVP descritas más abajo.

### Fase 4D — Fundamentos visuales y detalle Flutter (entregada)

Fundamentos visuales basados en Figma, Inter local, cabecera y navegación
compartidas; Inicio con perfil real, total y recientes; wallet de hasta 50
certificados; consulta de perfil y cierre de sesión. Las tarjetas abren un
detalle leído por ID y titular con carga, ausencia/inaccesibilidad, error y reintento.
Se conserva el aislamiento por sesión, incluido el detalle.
No equivale a completar la fase de blockchain del roadmap conceptual inferior.
Alcance, permisos y pruebas en [STUDENT_WALLET.md](STUDENT_WALLET.md).
Referencia y adaptaciones visuales en [FLUTTER_UI_FOUNDATIONS.md](FLUTTER_UI_FOUNDATIONS.md).

4D no añadió escrituras. Emisión y descarga de PDF se incorporan en 7B/7C;
siguen pendientes paginación completa, QR/verificación, autoservicio de
aprobación institucional, revocación y blockchain.

### Fase 5 — Cierre de autorización y preparación de emisión segura

**Objetivo:** cerrar la emisión y revocación por la API de tablas hasta disponer
de un backend confiable, manteniendo wallet y detalle de 4D.

**Alcance:** Supabase local, grants, RLS, pruebas de integración y documentación.
Se preservan datos, columnas, enums y políticas SELECT. No incluye pantallas,
endpoints, Storage, emisión, QR, verificación pública ni blockchain.

**Entregables:**

- Migración nueva `20260928202802_close_direct_certificate_writes.sql`: elimina
  INSERT/UPDATE de certificados por RLS, retira sus grants de escritura para
  `authenticated`, `anon` y PUBLIC, y conserva SELECT para `authenticated`.
- Cierre de TRUNCATE en las cuatro tablas privadas; retirada de REFERENCES y
  TRIGGER innecesarios. El trigger histórico de certificados conserva su guarda;
  se retira su grant EXECUTE a clientes.
- Pruebas con roles API y claims: titulares, `owner`/`admin`/`issuer` en todos los
  estados institucionales, administrador global, otra institución y anónimo;
  aislamiento, lecturas 4D e integridad tras escrituras rechazadas.
- [Contrato de emisión confiable](SECURE_ISSUANCE.md) y documentación de permisos
  efectivos y verificación local.

**Criterios de aceptación:** ningún `authenticated`, incluido `platform_admin`,
puede insertar, actualizar/revocar, hacer upsert o borrar certificados por la
API de tablas; `anon` no obtiene acceso; las lecturas legítimas se conservan;
la migración no borra ni altera datos; reset, SQL/RLS y lint del código propio
pasan localmente.

**Estado al 28/09/2026: implementada y verificada localmente.** Reconstrucción
completa, 242 comprobaciones SQL y lint de `public`/`certichain_private` superados.
El lint global informa incidencias de la extensión pgTAP; véase [TESTING.md](TESTING.md).
No se ha aplicado a un proyecto remoto. Esta fase **no habilita emisión ni
revocación**: ambas permanecen cerradas para clientes y sus endpoints están pendientes.

### Fase 6 — Administración, membresías y aprobación institucional

**Objetivo:** recorrido administrado desde una identidad Auth existente hasta
una institución con propietario, revisión y gestión de miembros, sin abrir emisión.

**Entregables:**

- Migración nueva `20260928210000_institution_administration.sql`: RPC protegidos
  para alta atómica `pending` + primer `owner`, datos, estados y membresías;
  cierre del DML institucional directo y de la eliminación institucional.
- Bootstrap y altas adicionales de `platform_admin` solo mediante SQL confiable,
  con UUID objetivo confirmado y contador esperado; sin credenciales en Git,
  metadatos de autorización ni promociones por actualización de perfil.
- Gestión de miembros por `owner`/`platform_admin`; `admin` institucional edita
  datos, pero no miembros ni `verification_status`. Protección de último owner,
  incluida concurrencia y cascadas de perfiles/Auth.
- 187 comprobaciones pgTAP nuevas, conservación de las 242 anteriores y ocho
  escenarios concurrentes en copia temporal del esquema sin datos de aplicación.
- Workflow `.github/workflows/database.yml` para PR y push a `main`: stack local,
  reset, SQL, concurrencia, preservación de certificados y lint de esquemas propios.
- [Guion operativo](INSTITUTION_ADMINISTRATION.md) y
  [ADR-0007](adr/0007-managed-institution-administration.md). El autoservicio de
  solicitudes institucionales y la UI Flutter institucional quedan pendientes.

**Criterios de aceptación:** solo plataforma crea/aprueba/suspende; alta y owner
atómicos; cada institución conserva un owner; ni miembros ni perfiles pueden
escalar permisos; bajas/degradaciones concurrentes no dejan instituciones huérfanas;
permisos SQL comprobables por CI en nuevos commits; certificados siguen sin
INSERT/UPDATE directos y las lecturas de wallet/detalle 4D se conservan.

**Estado al 28/09/2026: implementada y verificada localmente.** Reset de cinco
migraciones, 429 comprobaciones SQL, ocho escenarios concurrentes, ejecución de
scripts operativos en base temporal, preservación histórica y lint propio pasan.
El workflow está creado con acciones fijadas por SHA y CLI 2.117.0; la
[ejecución de GitHub Actions 36491581655](https://github.com/benjvm/certichain/actions/runs/36491581655)
terminó correctamente. No se ha aplicado
a un proyecto remoto ni asignado un administrador real. Las comprobaciones
operativas/manuales del bootstrap siguen a cargo del operador.

### Fase 7 — Emisión segura sin blockchain (entregada)

Depende de la administración institucional de fase 6. 7A y 7B entregan backend
autorizado, PDF privado con validación real y límites, SHA-256 de bytes finales,
idempotencia persistente y recuperación de fallos parciales. Sus nuevas
migraciones y pruebas habilitan la emisión solo por backend;
véase [SECURE_ISSUANCE.md](SECURE_ISSUANCE.md). No incluye todavía blockchain.

- **7A — datos, idempotencia y Storage privado: entregada localmente el
  30/09/2026.** La migración nueva añade operaciones persistentes con clave por
  institución, huellas SHA-256 en hex minúsculo, estados de recuperación,
  vínculos comprobables y certificado final inmutable. El bucket `certificates`
  es privado, admite solo PDF y limita a 8 MiB; los roles API no operan objetos
  directamente. Se conservaron los certificados anteriores sin normalizarlos.
  Reset, 468 pruebas SQL (429 anteriores y 39 nuevas), ocho escenarios de
  concurrencia, preservación histórica, pruebas HTTP Storage, lint propio y
  diff check pasaron localmente. Su CI observado falló en el harness HTTP de
  Storage; véase 7B. No hubo despliegue remoto.
- **7B — backend de emisión, validación PDF, autorización transaccional,
  conciliación y limpieza: entregada localmente el 30/09/2026.**
  Edge Function autenticada, entrada cerrada, huella v1 exacta, parser PDF acotado,
  lease exclusivo, Storage sin upsert y publicación atómica con revalidación.
  Limpieza terminal explícita y reintento recuperable sin cron. Migración nueva;
  históricos y revocación preservados. Pasan 493 SQL (468 previas + 25 nuevas),
  17 tests de función, 368 aserciones HTTP con Auth real, 14 carreras concurrentes,
  reset, preservación, lint, formato/tipos y diff check. Workflow ampliado y
  corregido para usar CLI instalada. CI de 7A observado: ejecución
  [36696424479](https://github.com/benjvm/certichain/actions/runs/36696424479),
  fallo del harness Storage tras reset/SQL correctos. El CI del último commit 7B
  `b7310c8dafda03bd043876d4ebb51a250be2d6e2`, ejecución
  [36707359039](https://github.com/benjvm/certichain/actions/runs/36707359039),
  se observó terminado con **success** el 30/09/2026.
  Contrato/límites PDF y recuperación en [SECURE_ISSUANCE.md](SECURE_ISSUANCE.md).
  No se despliega al remoto.
- **7C — interfaz de emisión y acceso autorizado al PDF: entregada localmente
  el 30/09/2026.** Espacio institucional por membresías reales, selección de
  institución, formulario Datos → Documento → Confirmar, ID de titular compartido
  voluntariamente, reintentos con solicitud inmutable y recibos acotados por
  identidad, listado institucional separado de wallet/detalle personal.
  Endpoint PDF autenticado, titulares y miembros owner/admin/issuer actuales de
  institución verified; capacidad de 60 segundos y descarga Chrome/Android/iOS.
  Sin cambios de grants SELECT ni apertura de Storage. Pasan localmente 500 SQL
  (las 493 anteriores + 7), 28 tests Deno, 368 aserciones HTTP de 7B, 86 nuevas
  del PDF, Storage, 14 carreras y preservación histórica. Flutter incluye pruebas
  de dominio, adaptadores, widgets y tamaños/texto ampliado; resultados de Chrome
  y build en [TESTING.md](TESTING.md). CI observado el 04/10/2026 para el commit
  `7830bf56af61344ee7011bac9b594630bea11c00`:
  [ejecución 37206437013](https://github.com/benjvm/certichain/actions/runs/37206437013),
  jobs `database` y `flutter` completed/**success**. Sin despliegue remoto. Decisiones en
  [ADR-0010](adr/0010-institutional-client-and-document-capabilities.md).
- **7D — pruebas integrales y endurecimiento del flujo: entregada localmente
  el 04/10/2026.** Flutter Web usa Auth, Edge y Storage reales: estados
  institucionales, validación, envío único, pérdida de respuesta, recibo y
  reconstrucción con la misma clave, wallet correcta y PDF privado íntegro.
  Barreras de PostgreSQL para doble envío/takeover; comprobación de filas,
  objetos y hashes finales; compatibilidad PDF y carga de hasta cuatro peticiones
  simultáneas. Corregida la entrega de lecturas institucionales tras cambiar o
  renovar sesión, con regresiones unitarias y respuestas reales retenidas.
  Build Android y diálogos nativos en emulador comprobados; iOS, dispositivos
  físicos y emisión completa nativa no verificados. Workflow ampliado; cierre de
  7D acreditado por evidencia previamente observada:
  [ejecución 37218682263](https://github.com/benjvm/certichain/actions/runs/37218682263),
  database/flutter success. No es CI de 8A.
  Evidencias, comandos y límites en [TESTING.md](TESTING.md).
  Sin migraciones nuevas ni despliegue remoto; QR, verificación pública,
  blockchain y nuevo flujo de revocación siguen fuera del alcance.

### Fase 8 — Verificación pública incremental

- **8A — contrato y backend público seguro: completada localmente el 04/10/2026.**
  Reutiliza credential_code UUID único/inmutable, consulta técnica service_role
  con evidencia completed/coherente, DTO v1 cerrado y sin titular/PDF/hash.
  Prioridad revoked > expired inclusivo > issuer_unavailable > valid; ausencia
  uniforme. POST público sin JWT/apikey y presupuesto global atómico 60/60 s,
  fail closed, una fila privada sin IP/eventos. SQL/Deno/HTTP y workflow ampliados.
  No se despliega al remoto. Contrato: [PUBLIC_VERIFICATION.md](PUBLIC_VERIFICATION.md).
  Reconstrucción de nueve migraciones; 557 SQL (500 anteriores + 57), 44 Deno
  (28 anteriores + 16), 296 aserciones HTTP públicas, regresiones HTTP 7B/7C/7D,
  Storage, 14 carreras, tres pruebas de preservación y lint propio superados.
  Entorno habitual preservado; no hay CI nuevo de 8A observado, push ni merge.
- **8B — pantalla pública, enlaces Web y QR: completada localmente el 04/10/2026.**
  Implementación del contrato
  v1 mediante HTTP independiente de Auth, formulario, estados y errores,
  navegación hash con recarga/historial y compartición del código propio.
  Evidencia final y comandos en [TESTING.md](TESTING.md).
- **8C — escáner y comparación de copia: completada localmente el 05/10/2026.**
  Cámara por acción, QR canónico de confianza/UUID estricto, decoder local sin
  CDN y ciclo de vida; selección acotada de 8 MiB, SHA-256 exacto sin upload.
  Endpoint independiente y snapshot SQL común, v1 intacto y presupuesto 60/60
  compartido; estado separado de integridad. Migración nueva/ADR-0013 y CI ampliada.
  182 Flutter, 611 SQL, 65 Deno, HTTP 255/296 y Web real con cámara emulada
  superados localmente. Harness 7D/8B corregidos y revalidados; smoke CDP Windows
  y Ubuntu 24.04. El fallo histórico Actions 37234444550 no se reprodujo ni se
  confirma su excepción concreta. Actions 37350396753 intento 2 observado posteriormente: success en 8C.
  Despliegue, cámaras físicas e iOS pendientes; evidencia en [TESTING.md](TESTING.md).
- **8D implementada y validada localmente el 05/10/2026.** Contratos públicos
  estrictos, readiness del proceso actual, cancelación/recursos y resultados anteriores
  explícitos; Node 24.14.0 fijado. main.dart Web release con HTTPS y stack descartable
  cubre emisión, descarga, QR/copia, cámara emulada/decoder real, comparación,
  errores/carreras y renovación temporal real. 198 tests Flutter y 68 Deno; suites
  SQL/HTTP y harness anteriores conservados. CI 8D y despliegue no observados.
  Plataformas/cámara física/validación humana pendientes, sin marcarlas como PASS:
  [PHASE8_ACCEPTANCE.md](PHASE8_ACCEPTANCE.md). Demo/limpieza reproducibles en
  [DEMO_VERIFICATION.md](DEMO_VERIFICATION.md).

La ejecución Actions 37350396753 intento 2 validó 8C en d31a273, no estos cambios.
El cierre local 8D no incorpora blockchain ni un nuevo flujo completo de revocación.

El reparto autorizado de 8B corrige la asignación documental de QR/enlaces a 8C
introducida en 8A (`e3f42255c459e57e73f16b9677722add7590227e`). Se conserva arriba
la entrega/evidencia histórica de 8A, sin atribuirle interfaz o CI posterior.

### Orden recomendado de los incrementos posteriores (pendientes)

1. Validar CI 8D, cámaras físicas y plataformas/validación humana pendientes de la matriz.
2. Anclaje blockchain: contrato, adaptador de backend, estados e idempotencia.
3. Revocación completa y endurecimiento: backend, sincronización blockchain,
   reconciliación, seguridad, recuperación y pruebas del recorrido completo.

## Etapas conceptuales del MVP

El plan original siguiente describe capacidades objetivo, no entregas completadas.
La antigua «Fase 5 — Revocación y endurecimiento» se denomina ahora **Etapa 5**;
no debe confundirse con la Fase 5 de implementación anterior.

### Etapa 0 — Diseño y entorno

- Aprobar requisitos, actores y límites del MVP.
- Crear wireframes y flujo de navegación.
- Aprobar ADR iniciales de Supabase, arquitectura, red y storage.
- Inicializar Flutter, Supabase local, Foundry y CI.

**Salida:** repositorio reproducible, documentación base y pantallas navegables sin lógica real.

### Etapa 1 — Identidad e instituciones

- Auth, recuperación y perfiles.
- Instituciones, miembros y aprobación administrativa mínima.
- Políticas RLS y pruebas de aislamiento.

**Salida:** usuarios e instituciones acceden solo a lo autorizado.

### Etapa 2 — Certificados sin blockchain

- Migraciones de certificados y tipos.
- Upload privado, validación, SHA-256 y estados.
- Wallet del estudiante y panel de institución.

**Salida:** emisión off-chain completa y segura.

### Etapa 3 — Verificación y QR

- URL/código público estable.
- DTO público mínimo.
- QR, escáner y verificación opcional de archivo.
- Rate limit y registro prudente de eventos.

**Salida:** un tercero verifica sin cuenta y detecta un PDF alterado.

### Etapa 4 — Blockchain

- Contrato probado en Anvil.
- Despliegue en testnet.
- Edge Function/adaptador, idempotencia y reconciliación.
- UI de pendiente, confirmado y fallo.

**Salida:** emisión anclada y comprobable on-chain.

### Etapa 5 — Revocación y endurecimiento

- Flujo de revocación completo.
- Pruebas E2E, seguridad y accesibilidad.
- Observabilidad, recuperación ante fallos y límites.
- Datos y guion de demo reproducibles.

**Salida:** MVP defendible como TFG.

### Etapa 6 — Memoria y entrega

- Diagramas definitivos, decisiones y resultados.
- Métricas de pruebas y limitaciones.
- Vídeo/demo y manual de instalación.
- Backlog de evolución: API propia, emisión masiva, identidad verificable, eIDAS.

## Criterio de priorización

Si el calendario se complica, conservar en este orden: verificación, autorización/RLS, emisión segura, QR, blockchain, revocación, extras visuales. No sacrificar seguridad o reproducibilidad para añadir funciones secundarias.
