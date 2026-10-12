# ADR-0016 — Adaptador EVM y nonce revertido

- Estado: accepted para backend local 9C.
- Fecha: 2026-10-12.

Ethers 6.15.0, exacto en deno.lock, aporta Interface/Wallet/Transaction para
ABI, EIP-1559/RLP/secp256k1/Keccak. Las APIs Web no ofrecen Ethereum; criptografía
propia o CLI en Edge ampliarían mantenimiento y frontera de proceso. Revisar
releases/avisos al actualizar, junto con lock y pruebas de firma/ABI/runtime.
[Documentación oficial](https://docs.ethers.org/v6/single-page/) y
[release](https://github.com/ethers-io/ethers.js/releases/tag/v6.15.0).

ABI y runtime se generan desde 9B con backend-abi.mjs; --check detecta drift.
Dominio puro, puerto operacional y contrato de persistencia propios. Worker
en host fuera de Edge, presupuesto temporal/financiero y administración separada.
Anvil en contenedor/red propios conforme a 9A, host binding 127.0.0.1 y prueba
real de DNS/RPC entre contenedores. En Windows se reutiliza el archive Linux 9B
verificado; la imagen del contenedor es el ID local inmutable de Supabase.

Un revert incluido consume el nonce. Tras reconciliarlo y reautorizar de forma
explícita, puede haber un intento con nonce posterior de la misma EOA o con nonce
conocido de otra EOA exclusiva autorizada mediante rotación durable. El orden
de intentos no se deduce de nonces entre cuentas distintas. No es replacement
del nonce ya minado. Misma operación/anchor/salt/
payload/actor original, receipt fallido conservado y actor de firma registrado.
Replacements de nonce sin resolver conservan nonce/to/data/value: máximo tres.
Límite de 64 reautorizaciones y 256 intentos; failed no se reintenta solo.

Crear otro anchor perdería idempotencia/identidad; reusar nonce consumido no
funciona. Un lease no cancela firmas ni da fencing criptográfico: el CAS protege
BD. Nonce desconocido bloquea; null RPC no prueba dropped ni permite saltos.
Fault injection/reloj son exclusivos del harness aislado, sin parámetros remotos.
Recuperar un receipt no reconstruye el historial perdido del firmante ni permite
saltar nonces desconocidos. Sin ledger previo, la cuenta empieza en cero;
evidencia compatible puede confirmarse, pero nuevas firmas quedan bloqueadas
hasta recuperar/resolver el historial de esa EOA.
