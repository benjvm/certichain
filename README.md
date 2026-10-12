# CertiChain

Aplicación móvil para emitir, custodiar y verificar títulos y certificados digitales. Los documentos y metadatos privados viven fuera de la blockchain; el futuro anclaje EVM registrará únicamente evidencia de integridad y revocación.

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
- [Contrato vigente de emisión y acceso privado al PDF](docs/SECURE_ISSUANCE.md)
- [Contrato, verificación pública y QR y comparación 8A–8C](docs/PUBLIC_VERIFICATION.md)
- [Pruebas](docs/TESTING.md)
- [Flujo de desarrollo](docs/DEVELOPMENT.md)
- [Hoja de ruta](docs/ROADMAP.md)
- [Wallet y detalle autenticados](docs/STUDENT_WALLET.md)
- [Fundamentos visuales Flutter y referencia Figma](docs/FLUTTER_UI_FOUNDATIONS.md)
- [Registro de decisiones](docs/ADR_README.md)

## Estado

Entregadas Auth/wallet/detalle, autorización, administración institucional y
7A–7D: emisión autenticada sin blockchain, PDF privado, SHA-256, idempotencia,
recuperación, interfaz institucional y descarga autorizada. El cierre de 7D
cuenta con evidencia de CI previamente observada en la
[ejecución 37218682263](https://github.com/benjvm/certichain/actions/runs/37218682263).
Esa ejecución no acredita los cambios nuevos de 8A.

8A añade backend público por `credential_code`, proyección mínima y presupuesto
global PostgreSQL, exclusivamente local. Estado y pruebas en
[PUBLIC_VERIFICATION.md](docs/PUBLIC_VERIFICATION.md) y [TESTING.md](docs/TESTING.md).
8B añade interfaz pública independiente de Auth, enlaces Web hash y QR/copia
desde el certificado propio, comprobados en local. 8C añade escáner con decoder
local y comparación privada de bytes PDF mediante hash candidato. 8D está
implementada y publicada en `6235486` («8D stage»). El run
[37373509169, intento 1](https://github.com/benjvm/certichain/actions/runs/37373509169)
falló antes de ejecutar: GitHub no adquirió runners hosted y notificó un error
interno. Su aceptación CI sigue pendiente; el success 8C en d31a273 no la valida.
Blockchain, nuevo flujo de revocación y despliegue permanecen pendientes.

## Probar verificación y QR en Chrome local

Preparar un stack descartable según [PUBLIC_VERIFICATION.md](docs/PUBLIC_VERIFICATION.md)
y arrancar functions serve allí. Desde mobile, con su clave **pública** local:

```powershell
Push-Location tool
npm ci --ignore-scripts
node prepare_decoder.mjs
Pop-Location
flutter run -d chrome --web-hostname=localhost --web-port=7357 --dart-define=SUPABASE_URL=http://127.0.0.1:55321 --dart-define=SUPABASE_PUBLISHABLE_KEY=CLAVE_PUBLICA_LOCAL --dart-define=PUBLIC_VERIFICATION_BASE_URL=http://localhost:7357
```

Abrir Verificar certificado o `http://localhost:7357/#/verify/<credential_code>`.
Como titular, abrir certificado propio publicado por 7B → Mostrar QR y enlace
→ Copiar enlace; pegar en ventana privada sin sesión y recargar. Histórico sin
vínculo informa ausencia. Estados del registro y fechas UTC; no se comprueba
la identidad del presentador. Escanear QR identifica y pide confirmar el código;
Comparar mi PDF calcula el hash local y mantiene separado el estado del certificado.

SUPABASE_URL es backend; PUBLIC_VERIFICATION_BASE_URL es la base de la app Web,
nunca la Edge Function. Sin base válida no se comparte, pero funciona la consulta
manual. localhost solo en el mismo equipo, sin prometer acceso desde teléfonos
externos. HTTPS requerido fuera de desarrollo loopback. Configuración, pruebas
automáticas descartables y límites en
[PUBLIC_VERIFICATION.md](docs/PUBLIC_VERIFICATION.md),
[TESTING.md](docs/TESTING.md) y [ADR-0012](docs/adr/0012-public-web-navigation-and-credential-sharing.md).


La fase 8D dispone de demo técnica local sobre main.dart Web release con HTTPS y
stack descartable: [guion reproducible](docs/DEMO_VERIFICATION.md) y
[aceptación/plataformas pendientes](docs/PHASE8_ACCEPTANCE.md). Las herramientas
Node están fijadas a 24.14.0 en .node-version. Estado vigente, resultados fechados
y acciones del operador en [checklist 8D](docs/PHASE8_OPERATOR_CHECKLIST.md).
Esta revisión trabaja solo en local; las ediciones posteriores necesitan CI del
SHA que publique el operador.

Dictamen al 10/10/2026: **Diseño 9A posible con aceptación 8D pendiente**.
La revalidación local conserva CI bloqueada por infraestructura, QR nativo,
recorrido Android completo, cámaras físicas y accesibilidad humana pendientes.
