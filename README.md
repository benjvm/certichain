# CertiChain

Aplicación móvil para emitir, custodiar y verificar títulos y certificados digitales. Los documentos y metadatos privados viven fuera de la blockchain; el futuro anclaje EVM registrará únicamente evidencia de integridad y revocación.

## Objetivo del MVP

- Una institución autorizada emite un certificado y sube su PDF.
- El sistema calcula SHA-256 exacto del PDF; el futuro anclaje registra un
  compromiso con salt privado en Sepolia, sin publicar el hash documental.
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
│   ├── scripts/            # Bootstrap, despliegue Anvil y artefactos
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
- [Especificación técnica del protocolo 9A](docs/PHASE9A_BLOCKCHAIN_SPEC.md)
- [Contrato Foundry/Anvil y comandos 9B](blockchain/README.md)
- [Aceptación local y límites 9B](docs/PHASE9B_ACCEPTANCE.md)
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
implementada y publicada inicialmente en `6235486` («8D stage»). El fallo externo
histórico de Actions 37373509169 se conserva en la aceptación. CI posterior:
[38280055013, intento 1](https://github.com/benjvm/certichain/actions/runs/38280055013)
success en database/flutter/android para
`2066e908af30913462cf3daf77324eab2a63dfc4`, sin acreditar cámara física ni blockchain.
9A entrega decisiones/ABI objetivo/protocolo/persistencia futura, con Anvil,
Sepolia y Foundry. 9B implementa el contrato y valida localmente unit/fuzz/
invariantes, cobertura/gas, despliegue/smoke Anvil real y artefactos reproducibles.
CI blockchain independiente preparada, sin ejecución remota observada del nuevo
SHA. Backend 9C, cliente 9D, aceptación 9E y revocación completa 10 siguen pendientes.
Sin despliegue remoto; el Anvil de pruebas propio se resetea y descarta.

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

Dictamen al 12/10/2026: **9B validada localmente; blockchain aún no integrada**.
Comportamiento actual, DTO v1, códigos/enlaces/QR y PDF conservados. Omitir desde
ahora todas las pruebas de cámara, con CERTICHAIN_TEST_CAMERA=0 y registro
SKIP/NOT_RUN: «Omitidas por instrucción del usuario; no hay cámara física disponible».
Conservar funcionalidad/tests y verificaciones de códigos, imagen QR estática,
PDF, Auth, backend y SQL. Hardware no bloquea fases siguientes ni reabre 8D.
Otros límites de plataformas/revisión humana se conservan en aceptación/checklist.

Blockchain aportará evidencia externa de compromiso y revocación; comprobar un
PDF contra ese compromiso requiere apertura autorizada. Supabase sigue a cargo
de identidad, membresías, PDF, metadatos y atribución institucional. La comparación
pública actual sigue confiando en su hash esperado privado.

Para reproducir 9B desde un checkout limpio: `node blockchain/scripts/bootstrap.mjs`
y `node blockchain/scripts/validate.mjs`. El contrato registra compromisos opacos
y revocación; no demuestra que un commitment arbitrario corresponda a un PDF.
Revoke probado en contrato no habilita revocación Auth/SQL/EVM desde la app.
