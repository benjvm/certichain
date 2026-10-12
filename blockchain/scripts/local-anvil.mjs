// Disposable integration harness. Unlocked accounts are confined to its own Anvil process.
// Never accepts an operator-supplied endpoint, key, mnemonic, fork or account dump.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { bin, cast, root, run, sha256, verifyVersions } from "./common.mjs";
import { generateArtifacts } from "./artifacts.mjs";
import { decimal, localRpc, quantity, words } from "./rpc.mjs";
import { verifyManifest } from "./verify-manifest.mjs";

assert.equal(
  process.argv.length,
  2,
  "No external RPC or deployment arguments accepted",
);
verifyVersions();
const { build, reference } = generateArtifacts(true);
const fixture = JSON.parse(
  readFileSync(resolve(root, "fixtures/protocol-v1.json")),
);
const environmentId = `anvil-${randomUUID()}`;
const directory = resolve(root, "deployments", environmentId);
mkdirSync(directory, { recursive: true });
const listener = createServer();
listener.listen(0, "127.0.0.1");
await once(listener, "listening");
const port = listener.address().port;
await new Promise((done, reject) =>
  listener.close((error) => error ? reject(error) : done())
);
const endpoint = `http://127.0.0.1:${port}`;
const rpc = localRpc(endpoint);
// Random ephemeral accounts change genesis allocation between executions.
const genesisTimestamp = Math.floor(Date.now() / 1000);
const child = spawn(bin("anvil"), [
  "--host",
  "127.0.0.1",
  "--port",
  String(port),
  "--chain-id",
  "31337",
  "--hardfork",
  "cancun",
  "--accounts",
  "4",
  "--mnemonic-random",
  "--timestamp",
  String(genesisTimestamp),
  "--silent",
], {
  cwd: root,
  windowsHide: true,
  stdio: "ignore",
  env: Object.fromEntries(
    Object.entries(process.env).filter(([name]) =>
      !/^(ANVIL_|ETH_|EVM_|FOUNDRY_|DAPP_)/i.test(name)
    ),
  ),
});
let processError;
child.on("error", (error) => {
  processError = error;
});
let interrupted = false;
const interrupt = () => {
  interrupted = true;
};
process.on("SIGINT", interrupt);
process.on("SIGTERM", interrupt);
let stage = "startup";
let manifest;
let completed = false;
const receipts = [];
const checks = [];
function check(name, condition) {
  assert(condition, name);
  checks.push({ name, result: "PASS" });
}
try {
  let ready = false;
  for (let n = 0; n < 100; n++) {
    if (processError || child.exitCode !== null || interrupted) {
      throw new Error("Owned Anvil failed to start");
    }
    try {
      ready = (await rpc("eth_chainId")) === quantity(31337);
      if (ready) break;
    } catch (error) {
      // Only readiness transport failure is retryable, never a transaction.
      if (error.rpcError) throw error;
    }
    await delay(100);
  }
  check("Anvil ready on chain 31337", ready);
  const genesis = await rpc("eth_getBlockByNumber", ["0x0", false]);
  check(
    "Owned genesis timestamp",
    BigInt(genesis.timestamp) === BigInt(genesisTimestamp),
  );
  check("Anvil client", /anvil/i.test(await rpc("web3_clientVersion")));
  const [admin, signer, rotated, outsider] = (await rpc("eth_accounts")).map((
    a,
  ) => a.toLowerCase());
  check(
    "Separate administrator and operational signers",
    admin !== signer && signer !== rotated,
  );
  async function guard() {
    assert(
      !interrupted && child.exitCode === null && !processError,
      "Owned Anvil stopped",
    );
    assert.equal(await rpc("eth_chainId"), quantity(31337));
    assert.equal(
      (await rpc("eth_getBlockByNumber", ["0x0", false])).hash,
      genesis.hash,
    );
  }
  async function receipt(hash) {
    for (let n = 0; n < 100; n++) {
      const result = await rpc("eth_getTransactionReceipt", [hash]);
      if (result) {
        assert.equal(result.transactionHash, hash);
        const block = await rpc("eth_getBlockByNumber", [
          result.blockNumber,
          false,
        ]);
        assert.equal(result.blockHash, block.hash, "Noncanonical receipt");
        const transaction = await rpc("eth_getTransactionByHash", [hash]);
        assert.equal(transaction.hash, hash);
        assert.equal(transaction.blockHash, block.hash);
        assert.equal(transaction.from.toLowerCase(), result.from.toLowerCase());
        assert.equal(
          transaction.to?.toLowerCase() ?? null,
          result.to?.toLowerCase() ?? null,
        );
        receipts.push(result);
        return result;
      }
      await delay(100);
    }
    throw new Error("Receipt deadline exceeded");
  }
  async function send(from, data, to, success = true, value = "0x0") {
    await guard();
    const hash = await rpc("eth_sendTransaction", [{
      from,
      ...(to ? { to } : {}),
      data,
      gas: quantity(3_000_000),
      value,
    }]);
    const result = await receipt(hash);
    assert.equal(result.from.toLowerCase(), from);
    assert.equal(result.to?.toLowerCase() ?? null, to ?? null);
    assert.equal(BigInt(result.status), success ? 1n : 0n);
    if (!success) assert.equal(result.logs.length, 0);
    return result;
  }
  stage = "deploy";
  const constructor = cast("abi-encode", "constructor(address)", admin);
  const deployment = await send(
    admin,
    build.bytecode.object + constructor.slice(2),
  );
  const address = deployment.contractAddress.toLowerCase();
  const calldata = (signature, ...args) =>
    cast("calldata", signature, ...args.map(String));
  const call = (data) => rpc("eth_call", [{ to: address, data }, "latest"]);
  const transact = (from, signature, args = [], success = true) =>
    send(from, calldata(signature, ...args), address, success);
  async function expectRevert(from, data, expected) {
    let caught;
    try {
      await rpc("eth_call", [{ to: address, from, data }, "latest"]);
    } catch (error) {
      caught = error;
    }
    assert(caught?.rpcError, "Expected eth_call revert");
    assert.equal(caught.rpcError.data, expected, "Wrong custom error");
  }
  function event(result, signature, topics, data) {
    const expected = [cast("keccak", signature), ...topics];
    const logs = result.logs.filter((log) =>
      log.address.toLowerCase() === address && log.topics[0] === expected[0]
    );
    assert.equal(logs.length, 1);
    assert.deepEqual(logs[0].topics, expected);
    assert.equal(logs[0].data, data);
    assert.equal(logs[0].transactionHash, result.transactionHash);
    assert.equal(logs[0].blockHash, result.blockHash);
    assert.equal(logs[0].removed, false);
  }
  const topicAddress = (a) => "0x" + a.slice(2).padStart(64, "0");
  const encoded = (signature, ...args) =>
    cast("abi-encode", signature, ...args.map(String));
  const blockTime = async (r) =>
    decimal(
      (await rpc("eth_getBlockByNumber", [r.blockNumber, false])).timestamp,
    );
  const runtime = await rpc("eth_getCode", [address, "latest"]);
  check(
    "Normal compiled runtime equals eth_getCode",
    runtime === build.deployedBytecode.object,
  );
  check(
    "Runtime Keccak matches build reference",
    cast("keccak", runtime) === reference.runtimeCodeHash,
  );
  check(
    "Protocol v1 via RPC",
    BigInt(await call(calldata("protocolVersion()"))) === 1n,
  );
  check(
    "Administrator via RPC",
    words(await call(calldata("owner()")))[0] === topicAddress(admin),
  );
  const K = fixture.certificate_key,
    C = fixture.commitment,
    I = fixture.issuer_id;
  const K2 = "0x" + "02".repeat(32);
  check(
    "Absent key via RPC",
    BigInt(await call(calldata("exists(bytes32)", K))) === 0n,
  );
  stage = "configure";
  const config = await transact(admin, "setIssuer(bytes32,address,bool,bool)", [
    I,
    signer,
    true,
    true,
  ]);
  event(config, "IssuerConfigured(bytes32,address,bool,bool)", [
    I,
    topicAddress(signer),
  ], encoded("f(bool,bool)", true, true));
  check(
    "Issuer permissions via RPC",
    (await call(calldata("getIssuer(bytes32)", I))) ===
      encoded("f(address,bool,bool)", signer, true, true),
  );
  const noOp = await transact(admin, "setIssuer(bytes32,address,bool,bool)", [
    I,
    signer,
    true,
    true,
  ]);
  check("Identical configuration emits no log", noOp.logs.length === 0);
  stage = "issue";
  const issued = await transact(signer, "issue(bytes32,bytes32,bytes32)", [
    K,
    C,
    I,
  ]);
  const registeredAt = await blockTime(issued);
  event(issued, "CertificateIssued(bytes32,bytes32,bytes32,address,uint64)", [
    K,
    I,
  ], encoded("f(bytes32,address,uint64)", C, signer, registeredAt));
  const original = await call(calldata("getCertificate(bytes32)", K));
  check(
    "Issued state exact",
    original ===
      encoded("f(bytes32,bytes32,uint64,uint64)", C, I, registeredAt, 0),
  );
  check(
    "Explicit exists after issue",
    BigInt(await call(calldata("exists(bytes32)", K))) === 1n,
  );
  stage = "rejections";
  const unauthorized = (i, caller) =>
    calldata("IssuerUnauthorized(bytes32,address)", i, caller);
  await expectRevert(
    outsider,
    calldata("revoke(bytes32)", K),
    unauthorized(I, outsider),
  );
  await transact(outsider, "revoke(bytes32)", [K], false);
  await expectRevert(
    signer,
    calldata("issue(bytes32,bytes32,bytes32)", K, C, I),
    calldata("CertificateAlreadyExists(bytes32)", K),
  );
  await transact(signer, "issue(bytes32,bytes32,bytes32)", [K, C, I], false);
  await expectRevert(
    outsider,
    calldata("issue(bytes32,bytes32,bytes32)", K2, C, I),
    unauthorized(I, outsider),
  );
  await transact(outsider, "issue(bytes32,bytes32,bytes32)", [K2, C, I], false);
  await send(admin, calldata("protocolVersion()"), address, false, "0x1");
  check(
    "Rejected operations preserve issued record",
    (await call(calldata("getCertificate(bytes32)", K))) === original,
  );
  check(
    "Rejected operations create no record",
    BigInt(await call(calldata("exists(bytes32)", K2))) === 0n,
  );
  stage = "rotation";
  const rotation = await transact(
    admin,
    "setIssuer(bytes32,address,bool,bool)",
    [I, rotated, true, true],
  );
  event(rotation, "IssuerConfigured(bytes32,address,bool,bool)", [
    I,
    topicAddress(rotated),
  ], encoded("f(bool,bool)", true, true));
  await expectRevert(
    signer,
    calldata("revoke(bytes32)", K),
    unauthorized(I, signer),
  );
  await transact(signer, "revoke(bytes32)", [K], false);
  await expectRevert(
    signer,
    calldata("issue(bytes32,bytes32,bytes32)", K2, C, I),
    unauthorized(I, signer),
  );
  await transact(signer, "issue(bytes32,bytes32,bytes32)", [K2, C, I], false);
  check(
    "Rotation preserves earlier certificate",
    (await call(calldata("getCertificate(bytes32)", K))) === original,
  );
  await transact(rotated, "issue(bytes32,bytes32,bytes32)", [K2, C, I]);
  stage = "revoke";
  const revoked = await transact(rotated, "revoke(bytes32)", [K]);
  const revokedAt = await blockTime(revoked);
  event(
    revoked,
    "CertificateRevoked(bytes32,bytes32,address,uint64)",
    [K, I],
    encoded("f(address,uint64)", rotated, revokedAt),
  );
  const finalRecord = await call(calldata("getCertificate(bytes32)", K));
  check(
    "Revoked record preserves C/I/registeredAt",
    finalRecord ===
      encoded(
        "f(bytes32,bytes32,uint64,uint64)",
        C,
        I,
        registeredAt,
        revokedAt,
      ),
  );
  check("Revocation timestamp positive", BigInt(revokedAt) > 0n);
  await expectRevert(
    rotated,
    calldata("revoke(bytes32)", K),
    calldata("CertificateAlreadyRevoked(bytes32)", K),
  );
  await transact(rotated, "revoke(bytes32)", [K], false);
  const withdrawal = await transact(
    admin,
    "setIssuer(bytes32,address,bool,bool)",
    [I, "0x" + "00".repeat(20), false, false],
  );
  event(withdrawal, "IssuerConfigured(bytes32,address,bool,bool)", [
    I,
    "0x" + "00".repeat(32),
  ], encoded("f(bool,bool)", false, false));
  await transact(rotated, "revoke(bytes32)", [K2], false);
  check(
    "Withdrawal preserves public reading and irreversible revocation",
    (await call(calldata("getCertificate(bytes32)", K))) === finalRecord,
  );
  check(
    "No normal ETH accepted",
    BigInt(await rpc("eth_getBalance", [address, "latest"])) === 0n,
  );
  stage = "manifest";
  const gitHead = run("git", ["rev-parse", "HEAD"]);
  const dirty = run("git", ["status", "--porcelain"]).length > 0;
  manifest = {
    schemaVersion: 1,
    kind: "real-local-execution",
    evmHardfork: "cancun",
    network: "anvil",
    chainId: "31337",
    contractAddress: address,
    protocolVersion: 1,
    runtimeCodeHash: cast("keccak", runtime),
    deploymentTransactionHash: deployment.transactionHash,
    deploymentBlock: {
      number: decimal(deployment.blockNumber),
      hash: deployment.blockHash,
    },
    genesisHash: genesis.hash,
    environmentId,
    administrator: admin,
    initialSigner: signer,
    rotatedSigner: rotated,
    versions: {
      foundry: reference.foundry,
      compiler: reference.compiler,
      dependencies: reference.dependencies,
    },
    buildReference: "artifacts/build-reference.json",
    buildReferenceSha256: sha256(
      readFileSync(resolve(root, "artifacts/build-reference.json")),
    ),
    abiSha256: reference.abiSha256,
    sourceReference: {
      gitHead,
      workingTreeDirty: dirty,
      sources: reference.sources,
      settings: reference.settings,
    },
    observedAt: new Date().toISOString(),
    finality: "not_applicable",
    confirmations: "1",
    lifecycle: "discarded-after-smoke",
    reusableAfterReset: false,
  };
  writeFileSync(
    resolve(directory, "manifest.json"),
    JSON.stringify(manifest, null, 2) + "\n",
  );
  writeFileSync(
    resolve(directory, "receipts.json"),
    JSON.stringify(receipts, null, 2) + "\n",
  );
  await verifyManifest(rpc, manifest);
  check("Manifest validated against live chain", true);
  stage = "reset-invalidation";
  await rpc("anvil_reset"); // Only this harness-owned disposable process.
  await assert.rejects(verifyManifest(rpc, manifest));
  check("Previous manifest invalidated by real Anvil reset", true);
  const result = {
    schemaVersion: 1,
    status: "PASS",
    environmentId,
    endpoint,
    checks,
    receiptCount: receipts.length,
    successfulReceipts: receipts.filter((r) => BigInt(r.status) === 1n).length,
    rejectedReceipts: receipts.filter((r) => BigInt(r.status) === 0n).length,
    synthetic: true,
    certificateKey: K,
    commitment: C,
    issuerId: I,
    registeredAt,
    revokedAt,
    camera: {
      status: "NOT_RUN",
      reason:
        "Omitidas por instrucción del usuario; no hay cámara física disponible",
    },
  };
  writeFileSync(
    resolve(directory, "smoke.json"),
    JSON.stringify(result, null, 2) + "\n",
  );
  completed = true;
  console.log(
    `Anvil RPC smoke PASS: ${checks.length} checks, ${receipts.length} canonical receipts; ${directory}`,
  );
} catch (error) {
  writeFileSync(
    resolve(directory, "failure.json"),
    JSON.stringify(
      {
        status: "FAIL",
        stage,
        environmentId,
        checkedAt: new Date().toISOString(),
      },
      null,
      2,
    ) + "\n",
  );
  throw error;
} finally {
  process.removeListener("SIGINT", interrupt);
  process.removeListener("SIGTERM", interrupt);
  if (child.exitCode === null) {
    const exited = once(child, "exit");
    child.kill();
    let timer;
    try {
      await Promise.race([
        exited,
        new Promise((_, reject) => {
          timer = setTimeout(
            () => reject(new Error("Owned Anvil cleanup deadline exceeded")),
            6000,
          );
        }),
      ]);
    } finally {
      clearTimeout(timer);
    }
  }
  // Only public sanitized execution evidence is copied; no account dumps/logs/broadcast trees.
  if (completed) {
    const evidence = resolve(root, "evidence/anvil");
    mkdirSync(evidence, { recursive: true });
    for (const file of ["manifest.json", "receipts.json", "smoke.json"]) {
      writeFileSync(
        resolve(evidence, file),
        readFileSync(resolve(directory, file)),
      );
    }
    writeFileSync(
      resolve(evidence, "cleanup.json"),
      JSON.stringify(
        {
          status: "PASS",
          ownedProcessExited: child.exitCode !== null ||
            child.signalCode !== null,
        },
        null,
        2,
      ) + "\n",
    );
  }
}
