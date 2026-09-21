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
consulta Supabase ni perfiles. No se añaden service locators ni gestores externos.
Los tests inyectan un repositorio falso. Detalles en [AUTHENTICATION.md](AUTHENTICATION.md).
