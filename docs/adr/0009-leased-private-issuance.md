# ADR-0009 — Emisión con leases y limpieza terminal

- Estado: aceptada para 7B.
- Fecha: 30/09/2026.

## Contexto

7A conserva intención y resultado pero no fija transiciones, propiedad de upload
ni recuperación entre PostgreSQL y Storage. Un lease vencido no puede detener
una subida de red antigua. Comprobar que no exista certificado antes de DELETE
no basta si otra transacción puede publicarlo después del chequeo.

## Decisión

Añadir metadatos normalizados inmutables, token aleatorio de propiedad y lease
de 120 segundos por operación, mediante migración nueva. Reservar y avanzar solo
con RPC service_role; bloquear institución antes de operación, revalidando el
estado verified y membresía owner/admin/issuer al publicar. Auth verificado
aporta actor al cliente técnico, nunca metadatos/entrada. Publicación y completed
son atómicos. Mantener literalmente fingerprint v1 y los bytes de entrada.

Permitir takeover exclusivo de uploading/finalizing vencidos con reenvío del
PDF/metadatos. Las escrituras Storage usan ruta única inmutable sin upsert;
colisiones requieren lectura y comparación de bytes/hash/estructura. El token
anterior no puede finalizar. completed solo se recupera si el actor conserva
permiso vigente; la retirada de membresía deniega también el resultado.

La limpieza es terminal: cleanup_pending → failed, nunca vuelta a uploading.
Obtener lease técnico y comprobar referencia en BD antes de Storage DELETE;
confirmar ausencia antes de failed. Conservar failed para barrer objetos de
subidas tardías en futuras conciliaciones explícitas. Una clave nueva inicia
otro intento después de descarte. No añadir cron implícito ni SQL de objetos.

Para el MVP usar pdf-lib 1.17.1 fijado, inspección estricta complementaria,
PDF clásico de una revisión y recursos acotados. Rechazar contenido activo,
adjuntos/cifrado y formas no inspeccionables. Titular: Auth confirmado/no
anónimo/no bloqueado/no eliminado y perfil holder. No ampliar búsqueda de perfiles.

## Alternativas y consecuencias

Reabrir una operación limpiada permitiría publicar mientras un DELETE de Storage
está en vuelo. Un mero timestamp sin token no protege un proceso antiguo. Mantener
SQL abierto durante Storage retendría locks y seguiría sin atomicidad distribuida.
Limpieza terminal sacrifica reutilizar la misma clave a cambio de una prueba clara
de que no puede publicarse el objeto borrado. Un operador debe ejecutar la
conciliación; si nunca lo hace, el huérfano permanece privado y registrado.

La política PDF rechaza documentos legítimos fuera del subconjunto MVP; ampliarla
requiere nuevas pruebas/mediciones, no reparación silenciosa. No es antivirus.
No cambian revocación histórica, filas antiguas ni alcance de 7A. Esta ADR completa
la decisión de estados/recuperación que 0008 dejó para 7B.

## Validación

Vectores byte a byte y SHA-256 conocido; Auth/Edge/Storage locales, concurrencia
con locks observados, takeover simultáneo, publicación revertida íntegra,
respuesta perdida y lápidas de limpieza. Contrato y comandos en
[SECURE_ISSUANCE.md](../SECURE_ISSUANCE.md) y resultados en [TESTING.md](../TESTING.md).
