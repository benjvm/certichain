# ADR-0011: proyección pública del registro y presupuesto compartido

- Date: 2026-10-04
- Status: accepted (implementación local 8A)

## Contexto

7A–7D publican certificados sin blockchain con evidencia de PDF/hash y operación
completed. Un tercero debe verificar sin Auth y sin obtener datos del titular,
documento ni infraestructura privada. El esquema ya contiene credential_code
aleatorio, único e inmutable para publicaciones 7B.

## Decisión

Reutilizar credential_code UUID con entrada canónica y normalización de caso;
igualdad con el índice UNIQUE actual. No añadir public_id, logo ni índices.
POST verify-certificate tiene verify_jwt=false exclusivamente; emisión y descarga
mantienen su autenticación. Dos RPC técnicos de EXECUTE exclusivo service_role,
SECURITY DEFINER/search_path vacío: proyección elegible y consumo de presupuesto.
Ningún cliente obtiene acceso directo a tablas o Storage.

Publicar contrato v1 cerrado de nueve campos, issuer.name como único dato
institucional, fechas con microsegundos y fuente certichain_registry. Not_found
solo expone schema_version/result. Elegibilidad exige completed, IDs/vínculos,
hashes y ruta coherentes. Históricos se conservan sin backfill.

Prioridad: revoked > expired inclusivo > issuer_unavailable > valid; un instante
servidor para caducidad/checked_at. Suspensión institucional no implica revocación.
No incorporar pending sin un proceso blockchain.

Presupuesto global 60 POST/60 s, una fila privada con bloqueo transaccional y
reloj leído después del lock. Consumir antes de validar; incluir desconocidos e
inválidos, excluir OPTIONS. Retry-After servidor; no IP, eventos ni parámetros
controlados por cliente. Fallar cerrado si la infraestructura no responde.

## Alternativas y consecuencias

Un contador en memoria no coordina instancias. Un límite por IP requiere un
límite de confianza de proxy y política de datos que 8A no tiene; no se confía
en X-Forwarded-For. Un presupuesto global es pequeño y comprobable localmente,
pero puede agotarse para todos y permite ráfagas de frontera: no resuelve el
abuso/equidad de producción. Debe revisarse antes de despliegue.

Abrir RLS/SELECT anónimo expondría más columnas y caminos de consulta que el
contrato. Descargar PDF en cada petición amplificaría coste/abuso; 8A comprueba
evidencia del registro publicada por 7B, no bytes actuales en Storage. `valid`
no prueba identidad del presentador, integridad de su copia ni blockchain.

El nombre institucional es el actual. Cambios futuros del esquema/DTO requieren
revisar exposición y versionar el contrato. 8B–8D conectarán UI/QR/copia sin
ensanchar silenciosamente esta proyección. Detalles y pruebas:
[PUBLIC_VERIFICATION.md](../PUBLIC_VERIFICATION.md), [TESTING.md](../TESTING.md).
