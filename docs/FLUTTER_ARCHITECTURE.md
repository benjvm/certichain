# Arquitectura Flutter

La aplicación móvil usa una organización **feature-first** inspirada en Clean
Architecture. El objetivo es mantener límites claros sin introducir
abstracciones hasta que exista un caso de uso que las necesite.

## Estructura general

- `app/` contiene la configuración global de Flutter: widget raíz, navegación y
  tema visual. No contiene reglas de negocio.
- `core/` contiene código reutilizable por varias features, como constantes,
  errores, utilidades, servicios comunes y widgets compartidos. No debe incluir
  comportamiento específico de una feature.
- `features/` agrupa cada capacidad del producto de forma independiente. Las
  features iniciales son `auth`, `certificates`, `institutions`, `verification`
  y `profile`.

## Capas de una feature

Cada feature se divide solo cuando lo necesita en:

- `domain/`: entidades, contratos de repositorio y casos de uso. Es Dart puro y
  no depende de Flutter, Supabase, formatos JSON ni librerías blockchain.
- `data/`: fuentes de datos, DTO/modelos, mapeos e implementaciones de los
  contratos definidos por el dominio. Aquí se integrarán posteriormente
  Supabase, APIs o almacenamiento local.
- `presentation/`: páginas, widgets y providers/controladores de estado. Puede
  depender del dominio, pero no consulta directamente infraestructura ni
  contiene reglas de negocio.

La dirección de dependencias es `presentation -> domain <- data`. Las
operaciones privilegiadas y el uso de secretos permanecen en backend.

## Añadir una nueva feature

Una nueva capacidad se crea bajo `mobile/lib/features/<feature>/`. Deben
añadirse únicamente las carpetas y capas que requiera su primer caso de uso,
manteniendo sus conceptos de dominio independientes de Flutter e
infraestructura. Si la decisión altera límites estructurales o responsabilidades
existentes, debe actualizarse la documentación arquitectónica y valorarse un
ADR.

## Auth — Phase 4B

`main` es la raíz de composición: valida `AppConfig`, inicializa Supabase e
inyecta `SupabaseAuthRepository` en `CertiChainApp`. `AuthRepository` y sus tipos
son Dart puro. Las pantallas reciben el contrato por constructor; el router
propaga esa dependencia. `AuthController` (ChangeNotifier del SDK Flutter)
observa una única suscripción y coordina sesión/logout. El widget raíz sustituye
el navegador al cambiar el estado de autenticación o la identidad. La UI no
consulta Supabase directamente. No se añaden service locators ni gestores externos.
Los tests inyectan un repositorio falso. Detalles en [AUTHENTICATION.md](AUTHENTICATION.md).

## Perfil y certificados — Fase 4C

`main` inyecta también `ProfileRepository` y `CertificateRepository` con sus
adaptadores Supabase. `features/profile` y `features/certificates` separan
entidades/contratos Dart, traducción de filas en data y widgets de lectura en
presentation. La vigencia pertenece al dominio `Certificate.validityAt`.
`app/AuthenticatedArea` compone ambas features, coordina futuros, reintentos,
temporizadores y destinos `AuthenticatedSection`. El navegador ligado a la sesión
destruye los datos visibles al cambiar la identidad. No hay dependencias nuevas
ni cambio de decisión arquitectónica que requiera ADR.

Los futuros se comparten entre inicio, wallet y perfil dentro de esa área;
FutureBuilder oculta datos anteriores durante una nueva lectura e ignora
completados de solicitudes sustituidas. Detalles en [STUDENT_WALLET.md](STUDENT_WALLET.md).

## Fundamentos visuales y detalle — Fase 4D

Los tokens permanecen en `app/theme/`: colores, tipografía, espaciado, radios,
tamaños e iconografía. Inter 4.1 se incorpora como asset local con su licencia,
sin dependencias Dart nuevas ni descargas de fuentes durante la ejecución.
`core/widgets` aporta `AppTopBar`, `AppBottomNavigation`, `AppButton` y estados
de lectura. `CertificateCard`, `StatusBadge`, `CertificatePreview` y
`CertificateDetailScreen` pertenecen a la presentación de certificados.

`AppRouter.certificateDetail` crea `/certificates/detail` con un ID como argumento,
el titular de la sesión y el contrato inyectado. Es una ruta interna, sin deep
links. La pantalla consulta `CertificateRepository.readCertificate(userId, id)`;
el adaptador reutiliza el mapeo existente y añade filtros de ID y titular. No
hay consultas de infraestructura desde la presentación.

El detalle posee su futuro, reintento, observador de reanudación y temporizador
de expiración. Las lecturas sustituidas se ignoran; no se presenta `snapshot.data`
mientras una nueva lectura está pendiente. La sustitución del navegador por
identidad/estado Auth también destruye el detalle. El regreso conserva el destino
y el desplazamiento del origen; renovar el token del mismo usuario conserva la ruta.

No se alteran límites de capas, backend, RLS ni decisiones estructurales; no
se necesita un ADR nuevo. Véase [FLUTTER_UI_FOUNDATIONS.md](FLUTTER_UI_FOUNDATIONS.md).
