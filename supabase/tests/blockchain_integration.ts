// Isolated harness: real Auth/Edge/Storage/PostgreSQL/Anvil, never a remote URL.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fixture } from "./local_issuance_fixture.mjs";
import { assertDisposableStack, sql } from "../scripts/local_supabase.mjs";
import { keccak256, Transaction, Wallet } from "ethers";
import { BlockchainBackend } from "../functions/_shared/blockchain/data/backend.ts";
import {
  abi,
  calldata,
  EvmRegistry,
  quantity,
} from "../functions/_shared/blockchain/data/evm_registry.ts";
import {
  bytes,
  digest,
  hex,
} from "../functions/_shared/blockchain/application/commitment.ts";
import {
  coordinate,
  dbHex,
  deployment,
  type Job,
} from "../functions/_shared/blockchain/application/coordinator.ts";
import {
  type Deployment,
  type Hex,
  RegistryError,
} from "../functions/_shared/blockchain/domain/registry.ts";

let checks = 0;
function check(value: unknown, label: string) {
  if (!value) throw new Error(label);
  checks++;
  console.log(JSON.stringify({ case: label, result: "PASS" }));
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
function freePort() {
  const listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
  const port = listener.addr.port;
  listener.close();
  return port;
}
console.log(JSON.stringify({ phase: "9c-harness-start" }));
const port = freePort();
const executable = Deno.env.get("CERTICHAIN_ANVIL_BIN") ??
  resolve(
    Deno.build.os === "windows"
      ? "blockchain/.tools/anvil-linux/anvil"
      : "blockchain/.tools/bin/anvil",
  );
assertDisposableStack();
const project = /^project_id\s*=\s*"([^"]+)"/m.exec(
  readFileSync("supabase/config.toml", "utf8"),
)![1];
const databaseContainer = `supabase_db_${project}`;
const ownedName = `certichain-9c-anvil-${crypto.randomUUID()}`;
const network = `${ownedName}-network`;
const ownedDocker = (args: string[]) => {
  const r = spawnSync("docker", args, {
    encoding: "utf8",
    timeout: 30000,
    windowsHide: true,
  });
  if (r.status !== 0) throw new Error("Owned Anvil Docker operation failed");
  return r.stdout.trim();
};
const image = ownedDocker([
  "inspect",
  `supabase_edge_runtime_${project}`,
  "--format",
  "{{.Image}}",
]);
let connected = false, started = false, networkCreated = false;
let fx: Awaited<ReturnType<typeof fixture>> | null = null;
try {
  ownedDocker(["network", "create", network]);
  networkCreated = true;
  // Reuse the immutable local Supabase Edge glibc image (Postgres is musl).
  const binaryFolder = resolve(executable, "..");
  ownedDocker([
    "run",
    "-d",
    "--name",
    ownedName,
    "--network",
    network,
    "--network-alias",
    "anvil",
    "--publish",
    `127.0.0.1:${port}:8545`,
    "--mount",
    `type=bind,source=${binaryFolder},target=/opt/phase9c,readonly`,
    "--entrypoint",
    "/opt/phase9c/anvil",
    image,
    "--host",
    "0.0.0.0",
    "--port",
    "8545",
    "--chain-id",
    "31337",
    "--hardfork",
    "cancun",
    "--timestamp",
    String(Math.floor(Date.now() / 1000)),
  ]);
  started = true;
  const admin = Wallet.createRandom(),
    signer = Wallet.createRandom(),
    deployer = Wallet.createRandom();
  const rpcUrl = `http://127.0.0.1:${port}`;
  const initial = {
    environmentId: "local",
    network: "anvil",
    chainId: 31337n,
  } as Deployment;
  const rpc = new EvmRegistry(rpcUrl, initial);
  rpc.deadline = Date.now() + 15000;
  for (let i = 0; i < 100; i++) {
    try {
      await rpc.rpc("eth_chainId");
      break;
    } catch {
      if (i === 99) throw new Error("Anvil readiness");
      await sleep(100);
    }
  }
  rpc.deadline = Infinity;
  check(
    BigInt(await rpc.rpc<Hex>("eth_chainId")) === 31337n,
    "owned Anvil reachable on loopback",
  );
  ownedDocker(["network", "connect", network, databaseContainer]);
  connected = true;
  const probe = JSON.parse(
    ownedDocker([
      "exec",
      databaseContainer,
      "curl",
      "--fail",
      "--silent",
      "--max-time",
      "5",
      "-H",
      "content-type: application/json",
      "--data",
      '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}',
      "http://anvil:8545",
    ]),
  );
  check(
    probe.result === "0x7a69",
    "container resolves private anvil service and reaches real RPC",
  );
  const wrongLoopback = spawnSync("docker", [
    "exec",
    databaseContainer,
    "curl",
    "--fail",
    "--silent",
    "--max-time",
    "2",
    `http://127.0.0.1:${port}`,
  ]);
  check(
    wrongLoopback.status !== 0,
    "container loopback cannot stand in for host RPC",
  );
  check(
    ownedDocker([
      "inspect",
      ownedName,
      "--format",
      '{{(index (index .NetworkSettings.Ports "8545/tcp") 0).HostIp}}',
    ]) === "127.0.0.1",
    "administrative Anvil RPC published only on host loopback",
  );
  for (const wallet of [admin, signer, deployer]) {
    await rpc.rpc("anvil_setBalance", [
      wallet.address,
      quantity(100000000000000000000n),
    ]);
  }
  const build = JSON.parse(
    readFileSync(
      new URL(
        "../../blockchain/out/CertificateRegistry.sol/CertificateRegistry.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  const deploymentRaw = await deployer.signTransaction({
    type: 2,
    chainId: 31337n,
    nonce: 0,
    data: build.bytecode.object + abi.encodeDeploy([admin.address]).slice(2),
    gasLimit: 2000000n,
    maxFeePerGas: 3000000000n,
    maxPriorityFeePerGas: 1000000000n,
  });
  const deployHash = await rpc.rpc<Hex>("eth_sendRawTransaction", [
    deploymentRaw,
  ]);
  let deployed: {
    contractAddress: Hex;
    blockNumber: Hex;
    blockHash: Hex;
    status: Hex;
  } | null = null;
  for (let i = 0; i < 100 && !deployed; i++) {
    deployed = await rpc.rpc("eth_getTransactionReceipt", [deployHash]);
    if (!deployed) await sleep(50);
  }
  if (!deployed) throw new Error("Deployment receipt timeout");
  check(
    deployed.status === "0x1",
    "normal 9B build deployed by signed transaction",
  );
  const manifest = {
    synthetic: false,
    environmentId: "local",
    network: "anvil" as const,
    chainId: "31337",
    contractAddress: deployed.contractAddress.toLowerCase() as Hex,
    protocolVersion: 1 as const,
    genesisHash: (await rpc.block("0x0")).hash,
    runtimeCodeHash: keccak256(
      await rpc.rpc<Hex>("eth_getCode", [deployed.contractAddress, "latest"]),
    ) as Hex,
    deploymentBlock: {
      number: BigInt(deployed.blockNumber).toString(),
      hash: deployed.blockHash,
    },
  };
  const d: Deployment = {
    ...manifest,
    chainId: 31337n,
    deploymentBlock: {
      number: BigInt(manifest.deploymentBlock.number),
      hash: manifest.deploymentBlock.hash,
    },
  };
  const registry = new EvmRegistry(rpcUrl, d, signer.privateKey);
  check(
    manifest.runtimeCodeHash ===
      JSON.parse(
        readFileSync(
          new URL(
            "../../blockchain/artifacts/build-reference.json",
            import.meta.url,
          ),
          "utf8",
        ),
      ).runtimeCodeHash,
    "runtime equals frozen 9B artifact",
  );
  await registry.validateDeployment(d);
  fx = await fixture();
  const f = fx;
  const backend = new BlockchainBackend(
    f.local.API_URL,
    f.local.SERVICE_ROLE_KEY,
  );
  sql(
    "UPDATE certichain_private.blockchain_deployments SET enabled=false WHERE enabled;",
  );
  const dep = await backend.rpc<string>("blockchain_register_deployment", {
    p_manifest: manifest,
  });
  const I = hex(crypto.getRandomValues(new Uint8Array(32)));
  const config = {
    kind: "set_issuer" as const,
    I,
    signer: signer.address.toLowerCase() as Hex,
    canIssue: true,
    canRevoke: true,
  };
  const configure = async (
    canIssue: boolean,
    canRevoke: boolean,
    key = crypto.randomUUID(),
    targetSigner = config.signer,
  ) =>
    backend.rpc<string>(
      "blockchain_configure_issuer",
      {
        p_actor: f.platform.id,
        p_deployment: dep,
        p_institution: f.verified,
        p_i: I,
        p_signer: targetSigner,
        p_issue: canIssue,
        p_revoke: canRevoke,
        p_payload: await digest(
          bytes(
            calldata({ ...config, signer: targetSigner, canIssue, canRevoke }),
          ),
        ),
        p_key: key,
      },
    );
  const administrativeKey = crypto.randomUUID();
  const administrative = await configure(true, true, administrativeKey);
  check(
    await configure(true, true, administrativeKey) === administrative,
    "administrative request recovers same immutable operation",
  );
  let administrativeConflict = false;
  try {
    await configure(false, true, administrativeKey);
  } catch (e) {
    administrativeConflict = e instanceof RegistryError && e.code === "busy";
  }
  check(
    administrativeConflict,
    "same administrative key with changed actual calldata conflicts",
  );
  const makeReady = (id: string) =>
    sql(
      `UPDATE certichain_private.blockchain_operations SET next_attempt_at=clock_timestamp()-interval '1 second',lease_until=CASE WHEN lease_token IS NULL THEN NULL ELSE clock_timestamp()-interval '1 second' END WHERE id='${id}';`,
    );
  const run = async (
    id: string,
    adminMode = false,
    options: Parameters<typeof coordinate>[3] = {},
  ) => {
    makeReady(id);
    const result = await coordinate(
      backend,
      id,
      (j) =>
        new EvmRegistry(
          rpcUrl,
          deployment(j),
          adminMode ? admin.privateKey : signer.privateKey,
        ),
      { admin: adminMode, ...options },
    );
    await sleep(100);
    return result;
  };
  const publish = async (title: string) => {
    const p = await f.issue(f.owner, {
      institution_id: f.verified,
      holder_id: f.holder.id,
      idempotency_key: crypto.randomUUID(),
      title,
    });
    check(p.status === 201, "publication " + title);
    const r = await request(f.owner, {
      certificate_id: p.data.certificate_id,
      idempotency_key: crypto.randomUUID(),
    });
    check(r.response.status === 202, "anchor request " + title);
    return r.data.operation_id as string;
  };
  await rpc.rpc("anvil_setBalance", [admin.address, "0x0"]);
  check(
    await run(administrative, true) === "insufficient_funds",
    "administrator insufficient funds blocks unsigned configuration",
  );
  await rpc.rpc("anvil_setBalance", [
    admin.address,
    quantity(100000000000000000000n),
  ]);
  const adminReauthorization = await backend.rpc<{ status: string }>(
    "blockchain_reauthorize",
    { p_actor: f.platform.id, p_operation: administrative },
  );
  check(
    adminReauthorization.status === "requested",
    "explicit platform administrator reauthorization is audited",
  );
  check(
    await run(administrative, true) === "submitted",
    "separate administrator signs durable setIssuer",
  );
  check(
    await run(administrative, true) === "confirmed",
    "administrative receipt reconciles binding",
  );
  const disabledConfiguration = await configure(false, true);
  await run(disabledConfiguration, true);
  check(
    await run(disabledConfiguration, true) === "confirmed",
    "new administrative config version disables issuer with durable signed receipt",
  );
  await run(administrative, true);
  check(
    sql(
      `SELECT sync_state||'/'||observed_can_issue::text FROM certichain_private.blockchain_issuers WHERE deployment_id='${dep}'`,
    ) === "synced/false",
    "historical administrative operation never overwrites current observed configuration",
  );
  const enabledConfiguration = await configure(true, true);
  await run(enabledConfiguration, true);
  check(
    await run(enabledConfiguration, true) === "confirmed",
    "explicit administrative config restores same opaque issuer binding",
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.blockchain_operations WHERE issuer_binding_id=(SELECT id FROM certichain_private.blockchain_issuers WHERE deployment_id='${dep}') AND kind='set_issuer'`,
    ) === "3",
    "three immutable administrative snapshots preserved",
  );
  const pub = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: crypto.randomUUID(),
    title: "Synthetic 9C",
  });
  check(
    pub.status === 201 && pub.data.status === "completed",
    "Auth real → publication 7B completed",
  );
  const certificate = pub.data.certificate_id;
  const request = (actor: { token?: string }, body: unknown) =>
    f.json("/functions/v1/anchor-certificate", actor.token!, body);
  const req = {
    certificate_id: certificate,
    idempotency_key: crypto.randomUUID(),
  };
  check(
    (await request(f.outsider, req)).response.status === 403,
    "outsider denied despite known certificate UUID",
  );
  check(
    (await request(f.owner, { ...req, actor: f.owner.id })).response.status ===
      400,
    "closed JSON rejects actor injection",
  );
  check(
    (await request(f.owner, { ...req, idempotency_key: "bad" })).response
      .status === 400,
    "canonical UUID required",
  );
  const requests = await Promise.all(
    Array.from({ length: 6 }, () => request(f.owner, req)),
  );
  check(
    requests.filter((r) => r.response.status === 202).length === 1 &&
      requests.filter((r) => r.response.status === 200).length === 5,
    "concurrent HTTP requests create one operation",
  );
  const operation = requests[0].data.operation_id;
  check(
    requests.every((r) =>
      r.data.operation_id === operation &&
      Object.keys(r.data).sort().join() === "operation_id,status"
    ),
    "minimal no-store DTO uses same operation",
  );
  check(
    requests.every((r) =>
      r.response.headers.get("cache-control") === "no-store"
    ),
    "anchor responses no-store",
  );
  const alternate = await request(f.owner, {
    ...req,
    idempotency_key: crypto.randomUUID(),
  });
  check(
    alternate.data.operation_id === operation,
    `another key recovers same anchor (HTTP ${alternate.response.status}, ${
      alternate.data.error ?? alternate.data.status
    })`,
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.certificate_anchors WHERE certificate_id='${certificate}'`,
    ) === "1",
    "salt/anchor unique in private database",
  );
  const another = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: crypto.randomUUID(),
    title: "Synthetic other 9C",
  });
  check(
    (await request(f.owner, {
      ...req,
      certificate_id: another.data.certificate_id,
    })).response.status === 409,
    "same idempotency key different payload conflicts",
  );
  const claim = await backend.rpc<Job>("blockchain_claim", {
    p_operation: operation,
  });
  let busy = false;
  try {
    await backend.rpc("blockchain_claim", { p_operation: operation });
  } catch (e) {
    busy = e instanceof RegistryError && e.code === "busy";
  }
  check(busy, "second worker cannot claim live lease");
  makeReady(operation);
  const newer = await backend.rpc<Job>("blockchain_claim", {
    p_operation: operation,
  });
  check(
    BigInt(newer.operation.generation) > BigInt(claim.operation.generation),
    "expired lease increments generation",
  );
  busy = false;
  try {
    await backend.rpc("blockchain_update_job", {
      p_operation: operation,
      p_token: claim.operation.lease_token,
      p_generation: claim.operation.generation,
      p_action: "release",
    });
  } catch (e) {
    busy = e instanceof RegistryError && e.code === "busy";
  }
  check(busy, "old token/generation CAS rejected");
  // Real process-crash boundaries: durable prepared tx but no broadcast.
  try {
    await run(operation, false, {
      barrier: (point) => {
        if (point === "stored") {
          return Promise.reject(new Error("HARNESS_CRASH"));
        }
        return Promise.resolve();
      },
    });
  } catch (e) {
    check(
      e instanceof Error && e.message === "HARNESS_CRASH",
      "crash after durable signature",
    );
  }
  const frozen = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${operation}')`),
  ) as Job;
  const signed = frozen.attempts[0];
  check(
    !!signed.raw_signed_tx &&
      Transaction.from(dbHex(signed.raw_signed_tx)).hash ===
        dbHex(signed.transaction_hash),
    "stored raw EIP1559 hash recovers standard signature",
  );
  check(
    (await registry.observe(dbHex(signed.transaction_hash))).kind === "unknown",
    "commit-before-send crash has no chain inclusion",
  );
  check(
    await run(operation) === "submitted",
    "restart broadcasts exact durable bytes",
  );
  try {
    await run(operation, false, {
      barrier: (point) => {
        if (point === "receipt") {
          return Promise.reject(new Error("HARNESS_CRASH"));
        }
        return Promise.resolve();
      },
    });
  } catch (e) {
    check(
      e instanceof Error && e.message === "HARNESS_CRASH",
      "crash before receipt commit",
    );
  }
  check(
    await run(operation) === "confirmed",
    "restart reconciles successful receipt/event/state",
  );
  const progress = await f.json(
    "/functions/v1/anchor-progress",
    f.owner.token,
    { operation_id: operation },
  );
  check(
    progress.data.status === "confirmed" &&
      Object.keys(progress.data).length === 2,
    "authenticated progress minimal",
  );
  check(
    (await f.json("/functions/v1/anchor-progress", f.holder.token, {
      operation_id: operation,
    })).response.status === 403,
    "holder cannot access operational progress or salt",
  );
  const anchorBefore = sql(
    `SELECT row_to_json(a) FROM certichain_private.certificate_anchors a WHERE certificate_id='${certificate}'`,
  );
  // Protected private synthetic backup stays only in process memory. Restored to
  // a distinct private schema under postgres; never printed or written to disk.
  const tables = [
    "blockchain_deployments",
    "blockchain_issuers",
    "certificate_anchors",
    "blockchain_operations",
    "blockchain_transaction_attempts",
    "blockchain_signer_nonces",
  ];
  sql(
    "CREATE SCHEMA certichain_restore_9c;" +
      tables.map((t) =>
        `CREATE TABLE certichain_restore_9c.${t} AS TABLE certichain_private.${t}; REVOKE ALL ON certichain_restore_9c.${t} FROM PUBLIC,anon,authenticated,service_role;`
      ).join("\n"),
  );
  check(
    sql(
      `SELECT (SELECT row_to_json(a)::text FROM certichain_restore_9c.certificate_anchors a WHERE certificate_id='${certificate}')=(SELECT row_to_json(a)::text FROM certichain_private.certificate_anchors a WHERE certificate_id='${certificate}')`,
    ) === "t",
    "private restoration preserves exact S/K/I/H/C",
  );
  check(
    (await request(f.owner, req)).data.operation_id === operation &&
      await run(operation) === "confirmed",
    "restored identity replay produces no duplicate issue",
  );
  sql("DROP SCHEMA certichain_restore_9c CASCADE;");
  // Actual reorg, unlike controlled lease clocks.
  const beforeReorg = await rpc.rpc<string>("evm_snapshot");
  const reorgPub = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: crypto.randomUUID(),
    title: "Synthetic reorg 9C",
  });
  const reorgRequest = await request(f.owner, {
    certificate_id: reorgPub.data.certificate_id,
    idempotency_key: crypto.randomUUID(),
  });
  const reorgOp = reorgRequest.data.operation_id;
  await run(reorgOp);
  check(
    await run(reorgOp) === "confirmed",
    "reorg fixture initially confirmed",
  );
  const oldInclusion = await rpc.block("latest");
  check(
    await rpc.rpc("evm_revert", [beforeReorg]),
    "Anvil canonical reorg executed",
  );
  await rpc.rpc("evm_setAutomine", [false]);
  const afterReorg = await run(reorgOp);
  check(
    afterReorg === "submitted",
    "lower canonical head invalidates orphaned receipt and resends original bytes",
  );
  check(
    sql(
      `SELECT canonical_attempt_id IS NULL AND confirmations=0 FROM certichain_private.blockchain_operations WHERE id='${reorgOp}'`,
    ) === "t",
    "missing inclusion height with proven lower head clears current evidence",
  );
  await rpc.rpc("evm_setNextBlockTimestamp", [
    quantity(BigInt(oldInclusion.timestamp) + 5n),
  ]);
  await rpc.rpc("evm_mine");
  await rpc.rpc("evm_setAutomine", [true]);
  check(
    (await rpc.block("latest")).hash !== oldInclusion.hash,
    "actual reinclusion uses a new canonical block hash",
  );
  check(
    await run(reorgOp) === "confirmed",
    "real reinclusion confirms same operation",
  );
  check(
    sql(
      `SELECT jsonb_array_length(receipt_observations) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${reorgOp}'`,
    ) === "3",
    "orphan and reinclusion preserve receipt history",
  );
  check(
    anchorBefore ===
      sql(
        `SELECT row_to_json(a) FROM certichain_private.certificate_anchors a WHERE certificate_id='${certificate}'`,
      ),
    "unrelated completed anchor preserved",
  );
  // Removed actor blocks new signatures, explicit current member reauthorization.
  const rejectSql = (statement: string) => {
    const project = /^project_id\s*=\s*"([^"]+)"/m.exec(
      readFileSync("supabase/config.toml", "utf8"),
    )![1];
    const r = spawnSync("docker", [
      "exec",
      "-i",
      `supabase_db_${project}`,
      "psql",
      "-X",
      "-q",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-v",
      "ON_ERROR_STOP=1",
    ], { input: statement, encoding: "utf8", windowsHide: true });
    return r.status !== 0;
  };
  check(
    rejectSql(
      `UPDATE certichain_private.certificate_anchors SET salt=decode(repeat('00',32),'hex') WHERE certificate_id='${certificate}'`,
    ),
    "salt identity immutable even to direct trusted SQL",
  );
  check(
    rejectSql(
      `UPDATE certichain_private.blockchain_operations SET requested_by='${f.holder.id}' WHERE id='${operation}'`,
    ),
    "original actor immutable",
  );
  check(
    rejectSql(
      `UPDATE certichain_private.blockchain_operations SET payload_digest=decode(repeat('01',32),'hex') WHERE id='${operation}'`,
    ),
    "payload immutable",
  );
  check(
    rejectSql(
      `DELETE FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${operation}'`,
    ),
    "receipt/attempt history cannot be deleted",
  );
  check(
    rejectSql(
      `UPDATE certichain_private.blockchain_transaction_attempts SET raw_signed_tx=NULL WHERE operation_id='${operation}'`,
    ),
    "raw capability cannot be purged before retention deadline",
  );
  check(
    rejectSql(
      `INSERT INTO certichain_private.certificate_anchors(certificate_id,issuance_operation_id,institution_id,deployment_id,issuer_binding_id,credential_code_snapshot,certificate_key,document_sha256,salt,commitment)
    SELECT c.id,c.issuance_operation_id,'${f.pending}',a.deployment_id,a.issuer_binding_id,c.credential_code::uuid,extensions.digest(uuid_send(gen_random_uuid()),'sha256'),a.document_sha256,a.salt,a.commitment FROM public.certificates c CROSS JOIN certichain_private.certificate_anchors a WHERE c.id='${another.data.certificate_id}' AND a.certificate_id='${certificate}'`,
    ),
    "composite FK rejects certificate/institution/binding crossing",
  );
  const blockedRequest = await request(f.issuer, {
    certificate_id: another.data.certificate_id,
    idempotency_key: crypto.randomUUID(),
  });
  const blockedOp = blockedRequest.data.operation_id;
  const signedPublication = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: crypto.randomUUID(),
    title: "Signed before membership withdrawal",
  });
  const signedRequest = await request(f.issuer, {
    certificate_id: signedPublication.data.certificate_id,
    idempotency_key: crypto.randomUUID(),
  });
  const signedPermissionOp = signedRequest.data.operation_id;
  check(
    await run(signedPermissionOp) === "submitted",
    "authorized issuer operation is signed before membership withdrawal",
  );
  await f.rpc("remove_institution_member", {
    p_institution: f.verified,
    p_member: f.issuer.id,
  }, f.owner.token);
  check(
    await run(signedPermissionOp) === "confirmed",
    "membership withdrawal cannot cancel already signed bytes; actual inclusion reconciled",
  );
  check(
    sql(
      `SELECT requested_by='${f.issuer.id}' AND jsonb_array_length(authorizations)=0 FROM certichain_private.blockchain_operations WHERE id='${signedPermissionOp}'`,
    ) === "t",
    "signed observation conserves original authorization without silently reauthorizing",
  );
  check(
    await run(blockedOp) === "authorization_denied",
    "removed member blocks unsigned operation",
  );
  check(
    (await request(f.owner, {
      certificate_id: another.data.certificate_id,
      idempotency_key: crypto.randomUUID(),
    })).data.status === "blocked",
    "retrieval never silently reauthorizes blocked operation",
  );
  check(
    (await f.json("/functions/v1/reauthorize-anchor", f.owner.token, {
      operation_id: blockedOp,
    })).data.status === "requested",
    "explicit real Auth reauthorization",
  );
  await run(blockedOp);
  check(
    await run(blockedOp) === "confirmed",
    "reauthorized operation retains anchor",
  );
  check(
    sql(
      `SELECT jsonb_array_length(authorizations) FROM certichain_private.blockchain_operations WHERE id='${blockedOp}'`,
    ) === "1",
    "original actor plus append-only authorization audit",
  );
  const lossOp = await publish("lost broadcast response");
  try {
    await run(lossOp, false, {
      barrier: (point) =>
        point === "broadcast"
          ? Promise.reject(new Error("HARNESS_CRASH"))
          : Promise.resolve(),
    });
  } catch (e) {
    check(
      e instanceof Error && e.message === "HARNESS_CRASH",
      "crash after raw broadcast before SQL acknowledgement",
    );
  }
  check(
    await run(lossOp) === "confirmed",
    "lost broadcast response recovered by local hash without new signature",
  );
  const concurrencyOp = await publish("workers concurrent");
  makeReady(concurrencyOp);
  const workers = await Promise.all([
    coordinate(
      backend,
      concurrencyOp,
      (j) => new EvmRegistry(rpcUrl, deployment(j), signer.privateKey),
    ),
    coordinate(
      backend,
      concurrencyOp,
      (j) => new EvmRegistry(rpcUrl, deployment(j), signer.privateKey),
    ),
  ]);
  check(
    workers.includes("busy") && workers.includes("submitted"),
    "two real workers serialize claim/signature",
  );
  await sleep(100);
  check(
    await run(concurrencyOp) === "confirmed",
    "concurrent workers preserve one signed operation",
  );
  const lossSaltOp = await publish("lost salt");
  const savedSalt = sql(
    `SELECT encode(salt,'hex') FROM certichain_private.certificate_anchors WHERE id=(SELECT anchor_id FROM certichain_private.blockchain_operations WHERE id='${lossSaltOp}')`,
  );
  const replaceSalt = (salt: string) =>
    sql(
      `ALTER TABLE certichain_private.certificate_anchors DISABLE TRIGGER blockchain_immutable; UPDATE certichain_private.certificate_anchors SET salt=decode('${salt}','hex') WHERE id=(SELECT anchor_id FROM certichain_private.blockchain_operations WHERE id='${lossSaltOp}'); ALTER TABLE certichain_private.certificate_anchors ENABLE TRIGGER blockchain_immutable;`,
    );
  replaceSalt("00".repeat(32));
  check(
    await run(lossSaltOp) === "opening_unavailable",
    "isolated salt corruption halts new signatures",
  );
  replaceSalt(savedSalt);
  check(
    (await f.json("/functions/v1/reauthorize-anchor", f.owner.token, {
      operation_id: lossSaltOp,
    })).data.status === "requested",
    "restore exact salt then explicit reauthorization",
  );
  await run(lossSaltOp);
  check(
    await run(lossSaltOp) === "confirmed",
    "restored exact private opening confirms unchanged commitment",
  );
  const commitOp = await publish("failed SQL signature commit");
  const beforeCommitNonce = await registry.latestNonce(
    signer.address.toLowerCase() as Hex,
  );
  sql(
    "ALTER TABLE certichain_private.blockchain_transaction_attempts ADD CONSTRAINT phase9c_reject_commit CHECK(false) NOT VALID;",
  );
  try {
    await run(commitOp);
  } finally {
    sql(
      "ALTER TABLE certichain_private.blockchain_transaction_attempts DROP CONSTRAINT phase9c_reject_commit;",
    );
  }
  check(
    sql(
      `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${commitOp}'`,
    ) === "0",
    "actual rejected SQL commit rolls back prepared signature",
  );
  check(
    await registry.latestNonce(signer.address.toLowerCase() as Hex) ===
      beforeCommitNonce,
    "failed signature persistence never broadcasts or consumes nonce",
  );
  await run(commitOp);
  check(
    await run(commitOp) === "confirmed",
    "SQL commit recovery reuses same reserved nonce and anchor",
  );
  const fundsOp = await publish("funds");
  await rpc.rpc("anvil_setBalance", [signer.address, "0x0"]);
  check(
    await run(fundsOp) === "insufficient_funds",
    "real insufficient funds blocks without signing",
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${fundsOp}'`,
    ) === "0",
    "no durable raw tx or broadcast on insufficient funds",
  );
  await rpc.rpc("anvil_setBalance", [
    signer.address,
    quantity(100000000000000000000n),
  ]);
  check(
    (await f.json("/functions/v1/reauthorize-anchor", f.owner.token, {
      operation_id: fundsOp,
    })).data.status === "requested",
    "funding requires explicit reauthorization",
  );
  await run(fundsOp);
  check(
    await run(fundsOp) === "confirmed",
    "funded recovery reuses logical nonce/anchor",
  );
  const pendingOp = await publish("replacement");
  await rpc.rpc("evm_setAutomine", [false]);
  check(
    await run(pendingOp) === "submitted",
    "real mempool pending transaction",
  );
  const beforeReplacement = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${pendingOp}')`),
  ) as Job;
  check(
    (await registry.observe(
      dbHex(beforeReplacement.attempts[0].transaction_hash),
    )).kind === "pending",
    "pending observed without treating null as dropped",
  );
  // Test-only clock override installed into THIS guarded disposable database.
  // No client/environment switch exists in migration or deployed functions.
  sql(
    `CREATE TABLE certichain_private.phase9c_clock_offset(seconds integer); INSERT INTO certichain_private.phase9c_clock_offset VALUES(0);
    CREATE FUNCTION certichain_private.phase9c_clock() RETURNS timestamptz LANGUAGE sql SECURITY DEFINER SET search_path='' AS 'SELECT clock_timestamp()+make_interval(secs=>seconds) FROM certichain_private.phase9c_clock_offset';
    REVOKE ALL ON FUNCTION certichain_private.phase9c_clock() FROM PUBLIC,anon,authenticated,service_role;
    DO $$ DECLARE fn record; BEGIN FOR fn IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','certichain_private') AND p.proname LIKE 'blockchain_%' LOOP EXECUTE replace(pg_get_functiondef(fn.oid),'clock_timestamp()','certichain_private.phase9c_clock()'); END LOOP; END $$;`,
  );
  for (let replacement = 1; replacement <= 3; replacement++) {
    sql(
      `UPDATE certichain_private.phase9c_clock_offset SET seconds=${
        replacement * 301
      };`,
    );
    const result = await run(pendingOp, false, {
      now: () => Date.now() + replacement * 301000,
    });
    check(
      result === "submitted",
      `real replacement ${replacement} with controlled age`,
    );
  }
  const replaced = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${pendingOp}')`),
  ) as Job;
  check(
    replaced.attempts.length === 4 &&
      replaced.attempts.every((t) =>
        t.nonce === replaced.attempts[0].nonce &&
        t.calldata === replaced.attempts[0].calldata &&
        t.signer === replaced.attempts[0].signer
      ),
    "three replacements same nonce/to/data/value and all hashes conserved",
  );
  check(
    replaced.attempts.slice(1).every((t, index) =>
      BigInt(t.max_fee_per_gas) * 100n >=
        BigInt(replaced.attempts[index].max_fee_per_gas) * 120n &&
      BigInt(t.max_priority_fee_per_gas) * 100n >=
        BigInt(replaced.attempts[index].max_priority_fee_per_gas) * 120n
    ),
    "each replacement raises both fees at least 20 percent",
  );
  await rpc.rpc("anvil_dropTransaction", [
    dbHex(replaced.attempts.at(-1)!.transaction_hash),
  ]);
  await rpc.rpc("eth_sendRawTransaction", [
    dbHex(replaced.attempts[0].raw_signed_tx!),
  ]);
  await rpc.rpc("evm_mine");
  await rpc.rpc("evm_setAutomine", [true]);
  check(
    await run(pendingOp) === "confirmed",
    "winning replacement receipt confirmed by actual chain",
  );
  check(
    sql(
      `SELECT canonical_attempt_id='${
        replaced.attempts[0].id
      }' FROM certichain_private.blockchain_operations WHERE id='${pendingOp}'`,
    ) === "t",
    "older signed attempt really wins after replacements; all hashes remain recoverable",
  );
  sql("UPDATE certichain_private.phase9c_clock_offset SET seconds=0;");
  // Private pg_dump/restore inside owned DB container, no dumps in workspace,
  // logs or CI artifacts. The cluster's roles exist in both synthetic databases.
  const project = /^project_id\s*=\s*"([^"]+)"/m.exec(
    readFileSync("supabase/config.toml", "utf8"),
  )![1];
  const container = `supabase_db_${project}`;
  const backupName = `phase9c_${crypto.randomUUID().replaceAll("-", "")}`;
  const dumpPath = `/tmp/${backupName}.dump`;
  const docker = (...args: string[]) => {
    const r = spawnSync("docker", ["exec", container, ...args], {
      encoding: "utf8",
      windowsHide: true,
    });
    if (r.status !== 0) {
      throw new Error("Private backup/restore command failed");
    }
    return r.stdout.trim();
  };
  try {
    docker(
      "sh",
      "-c",
      `umask 077; pg_dump -U postgres -Fc -f ${dumpPath} postgres`,
    );
    docker("createdb", "-U", "postgres", backupName);
    docker(
      "pg_restore",
      "-U",
      "supabase_admin",
      "--exit-on-error",
      "--no-owner",
      "-d",
      backupName,
      dumpPath,
    );
    const restored = docker(
      "psql",
      "-X",
      "-U",
      "postgres",
      "-d",
      backupName,
      "-Atc",
      `SELECT row_to_json(a) FROM certichain_private.certificate_anchors a WHERE certificate_id='${certificate}'`,
    );
    check(
      restored === anchorBefore,
      "actual protected pg_dump/pg_restore preserves exact anchor secrets",
    );
    check(
      docker(
        "psql",
        "-X",
        "-U",
        "postgres",
        "-d",
        backupName,
        "-Atc",
        `SELECT count(*) FROM certichain_private.blockchain_operations WHERE id='${operation}'`,
      ) === "1",
      "actual restore conserves operation identity",
    );
  } finally {
    docker("dropdb", "-U", "postgres", "--if-exists", backupName);
    docker("rm", "-f", dumpPath);
  }
  check(
    await run(operation) === "confirmed",
    "restoration reconciliation never duplicates original issue",
  );
  const recoverOp = await publish("original chain evidence");
  const recoverJob = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${recoverOp}')`),
  ) as Job;
  const recoverCommand = {
    kind: "issue" as const,
    K: dbHex(recoverJob.anchor!.certificate_key),
    C: dbHex(recoverJob.anchor!.commitment),
    I: dbHex(recoverJob.binding.issuer_id),
  };
  const originalTx = await registry.prepare(
    recoverCommand,
    (await registry.nonce()).latest,
    await registry.fees(recoverCommand),
  );
  await registry.broadcast(originalTx);
  await sleep(100);
  check(
    await run(recoverOp) === "recovered",
    "same K/C/I locates original real issue event with no SQL attempt",
  );
  check(
    await run(recoverOp) === "confirmed",
    "original receipt/raw signature imported and canonical evidence persisted",
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${recoverOp}'`,
    ) === "1",
    "event recovery emits no duplicate issue",
  );
  const rpcOp = await publish("RPC unavailable");
  makeReady(rpcOp);
  check(
    await coordinate(backend, rpcOp, (j) =>
      new EvmRegistry(
        "http://127.0.0.1:1",
        deployment(j),
        signer.privateKey,
      )) === "rpc_unavailable",
    "actual refused RPC connection preserves pending request",
  );
  check(
    sql(
      `SELECT state||'/'||last_error FROM certichain_private.blockchain_operations WHERE id='${rpcOp}'`,
    ) === "requested/rpc_unavailable",
    "RPC failure is never certificate absence",
  );
  await run(rpcOp);
  check(
    await run(rpcOp) === "confirmed",
    "real RPC recovery reuses immutable operation",
  );
  const slow = Deno.serve(
    { hostname: "127.0.0.1", port: 0, onListen() {} },
    async () => {
      await sleep(100);
      return Response.json({ jsonrpc: "2.0", id: 1, result: null });
    },
  );
  const slowRegistry = new EvmRegistry(`http://127.0.0.1:${slow.addr.port}`, d);
  const slowHead = (await registry.validateDeployment(d)).head;
  slowRegistry.deadline = Date.now() + 20;
  let realTimeout = false;
  try {
    await slowRegistry.read(recoverCommand.K, slowHead);
  } catch (e) {
    realTimeout = e instanceof RegistryError && e.code === "rpc_timeout";
  } finally {
    await slow.shutdown();
  }
  check(
    realTimeout,
    "actual delayed local HTTP RPC times out; read never reports canonical absence",
  );
  const actual = await registry.observe(dbHex(signed.transaction_hash));
  if (actual.kind !== "included") {
    throw new Error("Actual original receipt missing");
  }
  let incompatible = false;
  try {
    await registry.validateEvidence(
      {
        ...recoverCommand,
        K: dbHex(frozen.anchor!.certificate_key),
        C: `0x${"01".repeat(32)}`,
      },
      actual.receipt,
      signer.address.toLowerCase() as Hex,
    );
  } catch (e) {
    incompatible = e instanceof RegistryError &&
      e.code === "incompatible_evidence";
  }
  check(
    incompatible,
    "actual status=1 receipt with incompatible calldata/event never validates",
  );
  await backend.rpc("blockchain_close_local", { p_operation: operation });
  check(
    await backend.rpc("blockchain_purge_raw") === 0,
    "explicit local close retains raw for seven days",
  );
  sql("UPDATE certichain_private.phase9c_clock_offset SET seconds=604801;");
  check(
    await backend.rpc("blockchain_purge_raw") === 1,
    "controlled retention deadline purges only closed raw capability",
  );
  sql("UPDATE certichain_private.phase9c_clock_offset SET seconds=0;");
  check(
    sql(
      `SELECT transaction_hash IS NOT NULL AND raw_signed_tx IS NULL AND jsonb_array_length(receipt_observations)>0 FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${operation}'`,
    ) === "t",
    "purge conserves metadata and evidence",
  );
  const cliOp = await publish("trusted worker command");
  const runCli = () => {
    makeReady(cliOp);
    const cliEnv = {
      ...Deno.env.toObject(),
      SUPABASE_URL: f.local.API_URL,
      SUPABASE_SERVICE_ROLE_KEY: f.local.SERVICE_ROLE_KEY,
      EVM_RPC_URL: rpcUrl,
      EVM_SIGNER_PRIVATE_KEY: signer.privateKey,
      EVM_MAX_COST_WEI: "10000000000000000",
      EVM_ADMIN_PRIVATE_KEY: "",
    };
    return spawnSync(Deno.execPath(), [
      "run",
      "--allow-env",
      "--allow-net",
      "--frozen",
      "--config",
      "supabase/functions/deno.json",
      "supabase/admin/blockchain.ts",
      "worker",
      cliOp,
    ], { encoding: "utf8", timeout: 40000, windowsHide: true, env: cliEnv });
  };
  const cliSubmission = runCli();
  check(
    cliSubmission.status === 0 &&
      JSON.parse(cliSubmission.stdout).result === "submitted",
    "actual trusted CLI worker signs and submits without administrator key",
  );
  await sleep(100);
  const cliConfirmation = runCli();
  check(
    cliConfirmation.status === 0 &&
      JSON.parse(cliConfirmation.stdout).result === "confirmed",
    "actual second trusted CLI pass persists canonical confirmation",
  );
  const rotationOp = await publish("signer rotation after reconciled revert");
  const rotationOpening = sql(
    `SELECT encode(a.salt,'hex')||encode(a.certificate_key,'hex')||encode(a.commitment,'hex') FROM certichain_private.certificate_anchors a JOIN certichain_private.blockchain_operations o ON o.anchor_id=a.id WHERE o.id='${rotationOp}'`,
  );
  await rpc.rpc("evm_setAutomine", [false]);
  await run(rotationOp);
  const rotationJob = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${rotationOp}')`),
  ) as Job;
  await rpc.rpc("anvil_dropTransaction", [
    dbHex(rotationJob.attempts[0].transaction_hash),
  ]);
  const nextSigner = Wallet.createRandom();
  await rpc.rpc("anvil_setBalance", [
    nextSigner.address,
    quantity(100000000000000000000n),
  ]);
  const rotatedConfiguration = await configure(
    true,
    true,
    crypto.randomUUID(),
    nextSigner.address.toLowerCase() as Hex,
  );
  await run(rotatedConfiguration, true);
  await rpc.rpc("evm_mine");
  check(
    await run(rotatedConfiguration, true) === "confirmed",
    "durable administrator rotation keeps opaque issuer identity",
  );
  await rpc.rpc("eth_sendRawTransaction", [
    dbHex(rotationJob.attempts[0].raw_signed_tx!),
  ]);
  await rpc.rpc("evm_mine");
  await rpc.rpc("evm_setAutomine", [true]);
  check(
    await run(rotationOp) === "failed",
    "previous signer actual revert is reconciled after on-chain rotation",
  );
  check(
    (await f.json("/functions/v1/reauthorize-anchor", f.owner.token, {
      operation_id: rotationOp,
    })).data.status === "requested",
    "signer rotation retry requires current actor explicit reauthorization",
  );
  const runRotated = async () => {
    makeReady(rotationOp);
    const result = await coordinate(
      backend,
      rotationOp,
      (j) => new EvmRegistry(rpcUrl, deployment(j), nextSigner.privateKey),
    );
    await sleep(100);
    return result;
  };
  check(
    await runRotated() === "submitted",
    "fresh exclusive rotated signer uses its own known nonce zero",
  );
  check(
    await runRotated() === "confirmed",
    "same operation confirms with authorized new signer after resolved old nonce",
  );
  check(
    sql(
      `SELECT count(DISTINCT encode(signer,'hex'))=2 AND min(nonce)=0 FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${rotationOp}'`,
    ) === "t",
    "previous signer receipt and new signer attempt both retained",
  );
  check(
    rotationOpening ===
      sql(
        `SELECT encode(a.salt,'hex')||encode(a.certificate_key,'hex')||encode(a.commitment,'hex') FROM certichain_private.certificate_anchors a JOIN certichain_private.blockchain_operations o ON o.anchor_id=a.id WHERE o.id='${rotationOp}'`,
      ),
    "rotation recovery preserves exact private opening and commitment",
  );
  const nonceRecoveryOp = await publish(
    "receipt recovery with missing nonce history",
  );
  const nonceRecoveryJob = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${nonceRecoveryOp}')`),
  ) as Job;
  const nonceRecoveryCommand = {
    kind: "issue" as const,
    K: dbHex(nonceRecoveryJob.anchor!.certificate_key),
    C: dbHex(nonceRecoveryJob.anchor!.commitment),
    I,
  };
  const nextRegistry = new EvmRegistry(rpcUrl, d, nextSigner.privateKey);
  const nonceRecoveryTx = await nextRegistry.prepare(
    nonceRecoveryCommand,
    await nextRegistry.latestNonce(nextRegistry.signer),
    await nextRegistry.fees(nonceRecoveryCommand),
  );
  await nextRegistry.broadcast(nonceRecoveryTx);
  await sleep(100);
  // Deliberate partial private restore in this owned fixture only. A valid
  // receipt can be recovered, but never reconstruct the account ledger by
  // silently advancing through consumptions whose history has been lost.
  sql(
    `ALTER TABLE certichain_private.blockchain_signer_nonces DISABLE TRIGGER blockchain_immutable; DELETE FROM certichain_private.blockchain_signer_nonces WHERE deployment_id='${dep}' AND signer=decode('${
      nextRegistry.signer.slice(2)
    }','hex') AND active_operation_id IS NULL; ALTER TABLE certichain_private.blockchain_signer_nonces ENABLE TRIGGER blockchain_immutable;`,
  );
  const runNext = (id: string) => {
    makeReady(id);
    return coordinate(
      backend,
      id,
      (j) => new EvmRegistry(rpcUrl, deployment(j), nextSigner.privateKey),
    );
  };
  check(
    await runNext(nonceRecoveryOp) === "recovered",
    "actual original receipt recovered even when private nonce history is missing",
  );
  check(
    await runNext(nonceRecoveryOp) === "confirmed",
    "valid recovered certificate evidence does not invent account consumption history",
  );
  check(
    sql(
      `SELECT next_nonce=0 AND active_operation_id IS NULL FROM certichain_private.blockchain_signer_nonces WHERE deployment_id='${dep}' AND signer=decode('${
        nextRegistry.signer.slice(2)
      }','hex')`,
    ) === "t",
    "recovery never jumps a lost nonce ledger to observed transaction nonce",
  );
  const lostLedgerOp = await publish("lost nonce ledger remains blocked");
  check(
    await runNext(lostLedgerOp) === "nonce_conflict",
    "actual consumed nonce with lost private history stops fresh signatures",
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${lostLedgerOp}'`,
    ) === "0",
    "lost nonce history recovery sends no fresh issue transaction",
  );
  const returnedConfiguration = await configure(true, true);
  await run(returnedConfiguration, true);
  check(
    await run(returnedConfiguration, true) === "confirmed",
    "explicit administrator restores original signer without discarding snapshots",
  );
  const revertOp = await publish("permission race revert");
  await rpc.rpc("evm_setAutomine", [false]);
  await run(revertOp);
  const administrativeNonce = BigInt(
    await rpc.rpc<Hex>("eth_getTransactionCount", [admin.address, "latest"]),
  );
  // Privileged method is confined to the owned harness: mine administrator
  // first while the operational signed bytes remain outside its mempool.
  const revertJob = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${revertOp}')`),
  ) as Job;
  await rpc.rpc("anvil_dropTransaction", [
    dbHex(revertJob.attempts[0].transaction_hash),
  ]);
  const revokedConfig = { ...config, canIssue: false };
  const withdrawal = await admin.signTransaction({
    type: 2,
    chainId: 31337n,
    nonce: Number(administrativeNonce),
    to: d.contractAddress,
    data: calldata(revokedConfig),
    value: 0n,
    gasLimit: 150000n,
    maxFeePerGas: 3000000000n,
    maxPriorityFeePerGas: 1000000000n,
  });
  await rpc.rpc("eth_sendRawTransaction", [withdrawal]);
  await rpc.rpc("evm_mine");
  await run(administrative, true);
  check(
    sql(
      `SELECT sync_state||'/'||observed_can_issue::text FROM certichain_private.blockchain_issuers WHERE deployment_id='${dep}'`,
    ) === "pending/false",
    "configuration reconciliation detects actual withdrawn permission after historical receipt",
  );
  await rpc.rpc("eth_sendRawTransaction", [
    dbHex(revertJob.attempts[0].raw_signed_tx!),
  ]);
  await rpc.rpc("evm_mine");
  await rpc.rpc("evm_setAutomine", [true]);
  check(
    await run(revertOp) === "failed",
    "real status=0 receipt preserved after on-chain permission race",
  );
  check(
    sql(
      `SELECT receipt_status FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${revertOp}'`,
    ) === "0",
    "reverted receipt does not confirm",
  );
  check(
    sql(
      `SELECT c.status||'/'||o.status FROM public.certificates c JOIN public.certificate_issuance_operations o ON o.id=c.issuance_operation_id JOIN certichain_private.certificate_anchors a ON a.certificate_id=c.id JOIN certichain_private.blockchain_operations b ON b.anchor_id=a.id WHERE b.id='${revertOp}'`,
    ) === "active/completed",
    "EVM revert preserves publication and certificate status",
  );
  // Restore permission with explicit test administrator transaction.
  const restorePermission = await admin.signTransaction({
    type: 2,
    chainId: 31337n,
    nonce: Number(administrativeNonce + 1n),
    to: d.contractAddress,
    data: calldata(config),
    value: 0n,
    gasLimit: 150000n,
    maxFeePerGas: 3000000000n,
    maxPriorityFeePerGas: 1000000000n,
  });
  await rpc.rpc("eth_sendRawTransaction", [restorePermission]);
  await sleep(100);
  await run(administrative, true);
  check(
    sql(
      `SELECT sync_state FROM certichain_private.blockchain_issuers WHERE deployment_id='${dep}'`,
    ) === "synced",
    "configuration reconciliation verifies restored permission from current canonical head",
  );
  check(
    (await f.json("/functions/v1/reauthorize-anchor", f.owner.token, {
      operation_id: revertOp,
    })).data.status === "requested",
    "explicit audited retry after resolved revert",
  );
  await run(revertOp);
  check(
    await run(revertOp) === "confirmed",
    "resolved reverted nonce gets a new authorized attempt on the same anchor",
  );
  const incompatibleOp = await publish("incompatible persisted snapshot");
  await run(incompatibleOp);
  await run(incompatibleOp);
  const savedCommitment = sql(
    `SELECT encode(commitment,'hex') FROM certichain_private.certificate_anchors WHERE id=(SELECT anchor_id FROM certichain_private.blockchain_operations WHERE id='${incompatibleOp}')`,
  );
  const corruptCommitment = (c: string) =>
    sql(
      `ALTER TABLE certichain_private.certificate_anchors DISABLE TRIGGER blockchain_immutable; UPDATE certichain_private.certificate_anchors SET commitment=decode('${c}','hex') WHERE id=(SELECT anchor_id FROM certichain_private.blockchain_operations WHERE id='${incompatibleOp}'); ALTER TABLE certichain_private.certificate_anchors ENABLE TRIGGER blockchain_immutable;`,
    );
  corruptCommitment("01".repeat(32));
  try {
    check(
      await run(incompatibleOp) === "incompatible_evidence",
      "actual successful receipt with corrupted expected snapshot becomes divergence",
    );
  } finally {
    corruptCommitment(savedCommitment);
  }
  check(
    sql(
      `SELECT state||'/'||last_error||'/'||confirmations::text FROM certichain_private.blockchain_operations WHERE id='${incompatibleOp}'`,
    ) === "divergence/incompatible_evidence/0",
    "incompatible evidence invalidates current confirmation",
  );
  check(
    sql(
      `SELECT receipt_observations->-1->>'status'='1' AND receipt_observations->-1->>'validated_log_index' IS NULL FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${incompatibleOp}'`,
    ) === "t",
    "incompatible real receipt retained alongside previous evidence",
  );
  check(
    await run(incompatibleOp) === "divergence",
    "snapshot restoration never silently resolves divergence",
  );
  const differingOp = await publish("different commitment already on chain");
  const differingJob = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${differingOp}')`),
  ) as Job;
  const differentCommand = {
    kind: "issue" as const,
    K: dbHex(differingJob.anchor!.certificate_key),
    C: `0x${"02".repeat(32)}` as Hex,
    I,
  };
  const differentTx = await registry.prepare(
    differentCommand,
    await registry.latestNonce(signer.address.toLowerCase() as Hex),
    await registry.fees(differentCommand),
  );
  await registry.broadcast(differentTx);
  await sleep(100);
  check(
    await run(differingOp) === "divergence",
    "real existing K with different C stops operation without overwriting chain",
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${differingOp}'`,
    ) === "0",
    "divergent chain record never causes another issue attempt",
  );
  const unknownOp = await publish("unknown nonce");
  const nonce = BigInt(
    await registry.rpc<Hex>("eth_getTransactionCount", [
      signer.address,
      "latest",
    ]),
  );
  const foreign = await signer.signTransaction({
    type: 2,
    chainId: 31337n,
    nonce: Number(nonce),
    to: deployer.address,
    value: 0n,
    gasLimit: 21000n,
    maxFeePerGas: 3000000000n,
    maxPriorityFeePerGas: 1000000000n,
  });
  await rpc.rpc("eth_sendRawTransaction", [foreign]);
  await sleep(150);
  check(
    await run(unknownOp) === "nonce_conflict",
    "real unknown nonce consumption stops signer without skipping",
  );
  const invalidD = { ...d, genesisHash: `0x${"00".repeat(32)}` as Hex };
  let mismatch = false;
  try {
    await registry.validateDeployment(invalidD);
  } catch (e) {
    mismatch = e instanceof RegistryError && e.code === "deployment_mismatch";
  }
  check(mismatch, "wrong live manifest rejected");
  // Regression: completed/PDF/v1 independent of anchoring.
  check(
    (await backend.pdf(`${f.verified}/${certificate}.pdf`)).length > 0,
    "published private PDF conserved",
  );
  const code = sql(
    `SELECT credential_code FROM public.certificates WHERE id='${certificate}'`,
  );
  const publicResponse = await fetch(
    `${f.local.API_URL}/functions/v1/verify-certificate`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ credential_code: code }),
    },
  );
  const publicDto = await publicResponse.json();
  check(
    publicDto.schema_version === "1" && publicDto.result === "valid" &&
      !("blockchain" in publicDto),
    "public API v1 unchanged",
  );
  await rpc.rpc("anvil_reset", []);
  mismatch = false;
  try {
    await registry.validateDeployment(d);
  } catch (e) {
    mismatch = e instanceof RegistryError &&
      ["deployment_mismatch", "rpc_unavailable"].includes(e.code);
  }
  check(mismatch, "real Anvil reset invalidates manifest");
  console.log(JSON.stringify({
    suite: "phase9c-real",
    checks,
    head: spawnSync("git", ["rev-parse", "HEAD"], {
      encoding: "utf8",
      cwd: Deno.env.get("CERTICHAIN_SOURCE_ROOT") ?? Deno.cwd(),
    }).stdout
      .trim(),
    working_tree_dirty: spawnSync("git", ["status", "--porcelain"], {
      encoding: "utf8",
      cwd: Deno.env.get("CERTICHAIN_SOURCE_ROOT") ?? Deno.cwd(),
    }).stdout.trim().length > 0,
    camera: "NOT_RUN",
    camera_reason:
      "Omitidas por instrucción del usuario; no hay cámara física disponible",
  }));
} finally {
  // Whole disposable stack belongs to the caller; history guards intentionally
  // prevent deleting referenced certificates/actors through fixture teardown.
  if (connected) {
    ownedDocker(["network", "disconnect", network, databaseContainer]);
  }
  if (started) ownedDocker(["rm", "-f", ownedName]);
  if (networkCreated) ownedDocker(["network", "rm", network]);
  fx?.stopRuntime();
  // fixture Edge is terminated by local Supabase stop in the wrapper's finally.
  console.log(
    JSON.stringify({
      anvil_cleanup: "removed owned Anvil container and network",
    }),
  );
}
