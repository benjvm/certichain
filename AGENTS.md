# AGENTS.md — CertiChain

Estas reglas se aplican a todo el repositorio. Las instrucciones de un `AGENTS.md` más cercano pueden concretarlas, pero no contradecir las reglas de seguridad.

## Contexto

CertiChain permite emitir y verificar certificados académicos o profesionales. Es un TFG con intención de evolucionar a producto. La prioridad es entregar un MVP claro, demostrable, seguro y mantenible; no construir una plataforma excesiva.

## Arquitectura obligatoria

- Mantener el monorepo dividido en `mobile/`, `supabase/`, `blockchain/` y `docs/`.
- En Flutter usar organización feature-first y separación `presentation`, `domain` y `data`.
- El dominio no puede importar Supabase, Flutter, PostgREST ni librerías Web3.
- La UI no realiza consultas directas a Supabase ni contiene reglas de negocio.
- Toda infraestructura se accede mediante contratos propios: repositorios, gateways o servicios.
- Las operaciones privilegiadas —emitir, revocar, escribir en blockchain y usar secretos— se ejecutan en backend, nunca desde Flutter.
- No añadir una abstracción sin un caso de uso concreto. Preferir la solución más pequeña que conserve los límites anteriores.

## Flutter

- Usar Dart estable, null safety y análisis estricto.
- Agrupar por funcionalidad: `auth`, `certificates`, `issuance`, `verification`, `institutions` y `profile`.
- Mantener entidades y casos de uso independientes del formato JSON.
- Los modelos de datos traducen entre infraestructura y dominio.
- Centralizar rutas, configuración, errores y temas compartidos.
- No incorporar dependencias nuevas sin explicar necesidad, mantenimiento y alternativa estándar.
- Nunca incluir secretos ni una clave privada blockchain en la app.
- Ejecuta comandos de Flutter que necesiten funcionar de manera confiable a través de `sandbox_permissions: "require_escalated"`; siempre incluye una breve justificación y solicita una `prefix_rule` estrecha para el comando exacto, como `flutter --version`, `flutter analyze`, `flutter test`, o `dart format`.

## Base de datos y Supabase

- Todo cambio de esquema, constraint, índice, función, trigger o política RLS debe hacerse mediante una migración nueva.
- No editar una migración aplicada o compartida. Crear otra que avance el esquema.
- No usar el editor visual como fuente de verdad.
- Usar `auth.users` para identidad y una tabla pública `profiles` para datos de aplicación.
- Habilitar RLS en cada tabla expuesta y crear políticas de mínimo privilegio.
- Mantener SQL portable siempre que sea razonable y documentar cada dependencia específica de Supabase.
- No guardar contraseñas, tokens, secretos ni datos personales en seeds.

## Blockchain

- No almacenar nombres, correos, documentos, rutas, DNI ni otros datos personales on-chain.
- Registrar identificadores opacos, hash del documento, emisor, fecha y estado mínimo necesario.
- El PDF se hashea sobre sus bytes exactos con SHA-256.
- Ocultar la red EVM detrás de `BlockchainRegistry` o una interfaz equivalente.
- Probar autorización, duplicados, revocación, eventos y casos de fallo del contrato.
- Las claves de despliegue y firma se suministran mediante secretos del entorno del backend/CI.

## Seguridad y privacidad

- Aplicar mínimo privilegio y denegar por defecto.
- Validar tipo real, tamaño y extensión de archivos en servidor.
- Los buckets de documentos son privados; usar URLs firmadas de duración corta.
- La verificación pública expone solo los campos definidos en `docs/SECURITY.md`.
- No registrar documentos, hashes de IP sin necesidad, tokens, claves o PII en logs.
- No comprometer `.env`, credenciales ni archivos generados con secretos.

## Calidad

- Antes de cambiar código, leer los documentos relevantes y exponer supuestos.
- Realizar cambios pequeños, focalizados y coherentes con el alcance solicitado.
- Añadir o actualizar pruebas para cada comportamiento modificado.
- Ejecutar formateo, análisis y pruebas del área afectada antes de finalizar.
- No afirmar que una prueba pasó si no se ejecutó; informar claramente lo no verificado.
- No modificar archivos generados manualmente si existe un comando generador.
- Actualizar documentación y ADR cuando cambie una decisión estructural.

## Criterios de finalización

Una tarea termina cuando el comportamiento está implementado, sus errores relevantes están tratados, las pruebas necesarias pasan y la documentación afectada está actualizada. La seguridad y el modelo de permisos forman parte de la funcionalidad, no son una fase opcional posterior.
