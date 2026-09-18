# Flujo de desarrollo

## Requisitos locales

- Flutter SDK estable y Android Studio/Xcode según plataforma.
- Supabase CLI y Docker.
- Foundry.
- Git.

Fijar versiones del SDK y herramientas en el repositorio cuando comience la implementación.

## Arranque del repositorio

Desde la raíz `certichain/`:

```bash
flutter create --org com.benjvm --project-name certichain mobile
supabase init
mkdir -p blockchain docs/adr
```

Para Foundry, ejecutar su inicialización dentro de `blockchain/` evitando crear un repositorio Git anidado.

## Entornos

- `local`: Supabase local + Anvil; datos ficticios.
- `staging`: proyecto Supabase separado + testnet EVM.
- `production`: futuro; no reutiliza secretos ni datos de staging.

Flutter recibe configuración pública con `--dart-define` o un mecanismo tipado equivalente. Los secretos solo se configuran en funciones/backend y CI.

## Git

- `main` debe permanecer ejecutable y protegido.
- Crear ramas cortas: `feature/auth`, `feature/issue-certificate`, `fix/rls-student-access`.
- Commits pequeños con intención clara.
- Pull request con alcance, capturas si hay UI, migraciones, pruebas y riesgos.
- No es necesario mantener `develop` para un proyecto individual si añade ceremonia sin beneficio.

## Migraciones

1. Crear migración con Supabase CLI.
2. Escribir tabla, constraints, índices, RLS y políticas.
3. Ejecutar `supabase db reset` desde cero.
4. Ejecutar pruebas de permisos con varios roles.
5. Revisar diff y documentación.
6. Aplicar al entorno remoto solo mediante el flujo acordado.

Nunca corregir producción manualmente en el panel. Si ocurre una emergencia, reproducir inmediatamente el cambio en una migración y documentarlo.

## Trabajo con Codex

Solicitar incrementos verificables, por ejemplo:

> Implementa únicamente la migración inicial de profiles e institutions siguiendo AGENTS.md y docs/DATABASE.md. Incluye RLS y pruebas de permisos. No implementes certificados todavía. Ejecuta la reconstrucción local y reporta resultados.

Antes de aceptar una propuesta de Codex:

- comprobar que leyó `AGENTS.md` y documentos relevantes;
- revisar el plan y los supuestos;
- impedir cambios fuera de alcance;
- exigir pruebas ejecutadas y diff final;
- revisar personalmente migraciones, RLS, secretos y contratos.

Evitar prompts como «crea la app completa». Un incremento debería poder revisarse y revertirse de manera independiente.

## Convenciones

- Inglés para código, nombres de tablas, commits y APIs.
- Español o inglés consistente para documentación académica; este set empieza en español.
- Fechas en UTC y columnas `timestamptz`.
- UUID internos y públicos no secuenciales.
- Errores de dominio estables; no exponer mensajes crudos del proveedor a UI.

## Checklist de pull request

- [ ] Alcance pequeño y descrito.
- [ ] Sin secretos ni PII.
- [ ] Migración nueva si cambia la base.
- [ ] RLS y autorización probadas.
- [ ] Formato, análisis y tests ejecutados.
- [ ] Documentación/ADR actualizados.
- [ ] Estados de error y carga tratados.
- [ ] No se introdujo dependencia innecesaria de Supabase o EVM en dominio.
