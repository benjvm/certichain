# Estrategia de pruebas

## Pirámide

- Muchas pruebas unitarias para entidades, casos de uso, mapeos y estados.
- Pruebas de integración para PostgreSQL/RLS, Storage, Edge Functions y adaptadores.
- Pocas pruebas end-to-end sobre los recorridos críticos.
- Pruebas específicas del contrato con Foundry.

## Flutter

Ejecutar como mínimo:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Casos prioritarios:

- redirección según sesión y estado de perfil;
- lista separada por usuario e institución;
- mapeo de fallos de red a errores de dominio;
- estados loading/empty/error/success;
- QR inválido, desconocido, válido, expirado y revocado;
- accesibilidad básica de pantallas principales.

## Base de datos y RLS

Probar con identidades distintas, no solo con `service_role`:

- estudiante A no puede leer el PDF o fila de B;
- una institución no lee ni revoca certificados de otra;
- miembro `viewer` no emite;
- institución suspendida no emite;
- anónimo solo recibe el DTO público;
- constraints rechazan fechas, estados y hashes inválidos;
- una misma idempotency key no crea dos certificados.

`supabase db reset` debe reconstruir el esquema completo y cargar seeds sin intervención manual.

## Blockchain

Ejecutar:

```bash
forge fmt --check
forge test
```

Cubrir permisos, duplicados, eventos, revocación irreversible, consultas, fuzzing y consumo de gas relevante. Las pruebas de integración deben desplegar en Anvil y no depender de una testnet externa.

## End-to-end crítico

1. Administrador aprueba institución.
2. Institución emite certificado con PDF.
3. Proceso blockchain queda confirmado.
4. Estudiante lo ve y genera QR.
5. Anónimo obtiene resultado válido.
6. Copia modificada falla por integridad.
7. Institución revoca.
8. El mismo QR devuelve revocado.

## CI

En cada pull request:

- formato y análisis de Dart;
- unit/widget tests de Flutter;
- recreación local de base y pruebas SQL/RLS;
- formato, build y tests de Foundry;
- escaneo de secretos y dependencias.

Las pruebas que requieren credenciales externas se separan y nunca bloquean el desarrollo local sin una alternativa determinista.

## Definición de terminado

Un cambio incluye pruebas del comportamiento nuevo, mantiene los límites de autorización, actualiza fixtures/seeds si corresponde y deja documentado cualquier riesgo o comprobación manual pendiente.
