# CertiChain

Aplicación móvil para emitir, custodiar y verificar títulos y certificados digitales. Los documentos y metadatos privados viven fuera de la blockchain; la cadena almacena únicamente la prueba de integridad y el estado de revocación.

## Objetivo del MVP

- Una institución autorizada emite un certificado y sube su PDF.
- El sistema calcula su hash SHA-256 y registra la prueba en una red EVM de pruebas.
- El estudiante consulta y comparte sus certificados mediante un QR.
- Cualquier verificador comprueba autenticidad, integridad, emisor y estado sin iniciar sesión.
- La institución puede revocar certificados emitidos por ella.

## Stack inicial

- Flutter y Dart para la aplicación móvil.
- Supabase Auth, PostgreSQL, Storage y Edge Functions.
- Solidity y Foundry para el registro blockchain.
- GitHub Actions para integración continua.

## Estructura

```text
certichain/
├── mobile/                 # Proyecto Flutter completo
├── supabase/
│   ├── migrations/         # Esquema, RLS y funciones SQL versionadas
│   ├── functions/          # Operaciones privilegiadas del servidor
│   └── seed.sql            # Datos locales no sensibles
├── blockchain/
│   ├── src/                # Contratos Solidity
│   ├── script/             # Despliegues
│   └── test/               # Pruebas de contratos
├── docs/                   # Especificaciones y decisiones
├── .github/workflows/      # CI
└── AGENTS.md               # Instrucciones permanentes para Codex
```

`mobile/` es el directorio del proyecto Flutter, no un contenedor adicional. Desde la raíz:

```bash
flutter create --org com.benjvm --project-name certichain mobile
```

Si `mobile/` ya existe y está vacío:

```bash
cd mobile
flutter create --org com.benjvm --project-name certichain .
```

## Orden de implementación

1. Requisitos, modelo de dominio y decisiones arquitectónicas.
2. Proyecto Supabase local, migraciones y RLS.
3. Esqueleto Flutter y autenticación.
4. Emisión, almacenamiento y consulta de certificados.
5. Verificación pública y QR.
6. Contrato, adaptador blockchain y revocación.
7. Pruebas de seguridad, integración y demostración del TFG.

## Documentación

- [Alcance y requisitos](docs/REQUIREMENTS.md)
- [Arquitectura](docs/ARCHITECTURE.md)
- [Modelo de datos](docs/DATABASE.md)
- [Integración blockchain](docs/BLOCKCHAIN.md)
- [Seguridad](docs/SECURITY.md)
- [Pruebas](docs/TESTING.md)
- [Flujo de desarrollo](docs/DEVELOPMENT.md)
- [Hoja de ruta](docs/ROADMAP.md)
- [Registro de decisiones](docs/adr/README.md)

## Estado

Fase inicial de diseño. No se consideran definitivos el esquema, el contrato ni la API hasta aprobar sus ADR correspondientes.
