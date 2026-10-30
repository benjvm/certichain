# Wallet personal y detalle

## Navegación y ámbito

El área autenticada ofrece Inicio, Mis certificados y Mi perfil. Inicio muestra perfil real, total exacto y tres certificados recientes. Wallet lista hasta **50** registros por `issued_at DESC, id DESC`, con total/límite visibles y sin categorías inventadas. El avatar es genérico.

Una tarjeta abre el detalle interno por ID y titular actual. No es un deep link público. Volver conserva destino/desplazamiento; doble pulsación no abre dos detalles. Renovar sesión del mismo usuario conserva navegación; logout, cambio de identidad, expiración o error de sesión retiran el área privada.

## Lecturas y autorización

- Perfil: selección `id,full_name,role` filtrada por usuario. Ausencia/error ofrece reintento y salida segura.
- Wallet/detalle: selección mínima de certificado, fechas, estado, `revoked_at` y relación opcional de emisor; filtros explícitos `holder_id` y, en detalle, `id`. El detalle relee y usa ausencia uniforme «No existe o no tienes acceso».
- RLS autoriza en servidor. El filtro de titular sigue siendo necesario si el usuario también tiene membresía o rol plataforma con lecturas más amplias.
- Si RLS oculta la institución, mostrar «Institución no disponible» sin descartar el certificado. No ampliar políticas ni inventar emisor.
- Adaptadores traducen filas a dominio puro y rechazan identidad/estado desconocidos. Lecturas con timeout de 20 s; futuros/generaciones descartan respuestas obsoletas.
- Una selección personal no incluye ruta/hash privados, motivo/actor/auditoría ni ledger. El código compartible se obtiene por el repositorio autorizado específico.

## Documento y estados

El detalle muestra título, emisor opcional, emisión, expiración opcional y vigencia. `active`/`revoked` son SQL; expiración se deriva de fecha. El titular ve `revoked_at` cuando existe, sin motivo/actor privado. No confundirlo con timestamp EVM o checked_at.

Cada «Descargar PDF» obtiene autorización y capacidad nueva de 60 s mediante `certificate-pdf`, descarga y descarta la URL. No se persiste ni navega a ella; Chrome guarda un Blob temporal y Android/iOS usan adaptadores nativos. Histórico sin documento, objeto ausente o ajeno se presentan de forma segura. No hay preview inventada.

Revocar no elimina PDF, código o copias exportadas. El titular propio conserva la política de acceso con emisora suspended; pertenecer a plataforma u otra institución no concede acceso al PDF ajeno. [Contrato documental](SECURE_ISSUANCE.md).

## Evidencia, apertura y compartir

El titular consulta la evidencia pública **v3** mediante código propio autorizado. No accede al progreso institucional por ser titular. La UI distingue registro SQL, issue, revoke, finalidad y evidencia previa fechada. Obtener apertura Auth, copiar/exportar/importar y comparar PDF son acciones explícitas. Hash/salt/apertura permanecen solo en el contexto local; una coincidencia de PDF nunca acredita vigencia.

QR/enlace contienen solo URL pública `/#/verify/<credential_code>`. La base Web se valida por separado del backend; si falta, la consulta manual sigue disponible. No códigos improvisados ni QR con datos personales, PDF, apertura, hash, salt, motivo o JWT. Verificación pública funciona sin sesión y conserva su navegación/cooldown independientemente del área privada.

El perfil permite compartir voluntariamente el ID de titular con el emisor; no buscar/listar alumnos ni compartir credenciales. «Espacio institucional» aparece por membresía real y abre un ámbito distinto para emitir/listar/anclar/revocar, con permisos revalidados por backend.

## Ciclo de vida y comprobación

Reanudar/refrescar relee datos autorizados. La generación vigente, identidad/token, cancelación y mounted/dispose protegen respuestas y callbacks tardíos. El selector/hash no introduce bytes en preferencias; logout no promete borrar copias que el usuario exportó fuera de la aplicación.

Pruebas de repositorio, detalle, sesión, layout, compartición y revocación en `mobile/test/`; recorrido real en [demo](DEMO_BLOCKCHAIN_LOCAL.md). [Aceptación](PHASE10_ACCEPTANCE.md) y [guía de pruebas](TESTING.md). Paginación completa, edición de perfil, notificaciones y revisión humana quedan en [ROADMAP](ROADMAP.md).
