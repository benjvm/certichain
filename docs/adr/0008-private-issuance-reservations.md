# ADR-0008 — Reserva persistente y PDF privado para emisión

Fecha: 30/09/2026. Estado: aceptada para 7A.

## Decisión

Separamos la identidad de una emisión en
`public.certificate_issuance_operations`, con clave UUID única por institución,
actor y titular explícitos, huellas SHA-256 hex minúsculas, certificado objetivo
reservado y estados de avance. Un certificado nuevo de 7B debe referenciar la
operación; las FK compuestas impiden cruzar instituciones, actores, titulares,
objetivos o hashes. La clave identifica un intento lógico; claves distintas
pueden producir certificados distintos para el mismo contenido.

El PDF final vive en el bucket privado `certificates`, limitado a 8 MiB y
`application/pdf`, con ruta `<institution_id>/<certificate_id>.pdf`, creada
sin upsert. Las políticas restrictivas niegan todas las operaciones directas
de objetos a los roles cliente. Los PDF emitidos se conservan, incluso si el
certificado se revoca; solo se considera limpieza de huérfanos comprobados.

## Motivos y límites

La operación permite recuperar una respuesta perdida y registrar un fallo
entre PostgreSQL y Storage, que no comparten transacción. Una clave UNIQUE
por sí sola no coordina subida, commit ni limpieza. 7B debe comparar huella
y actor, bloquear la reserva, revalidar permisos y estado institucional al
publicar, verificar bytes finales mediante Storage API y reconciliar fallos.

Las filas históricas quedan sin operación y no se reescriben. La nueva
constraint solo afecta a certificados vinculados a una operación; el formato
anterior desconocido se revisará caso por caso. El bucket también se declara
en `config.toml` para la reconstrucción local. Esta decisión depende de
Supabase Storage para objetos; el esquema de operaciones usa PostgreSQL.
