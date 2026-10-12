import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { cast, root } from "./common.mjs";
import { localRpc, quantity } from "./rpc.mjs";

export async function verifyManifest(rpc, manifest) {
  assert.equal(
    manifest.kind,
    "real-local-execution",
    "Synthetic example is not a deployment",
  );
  assert.equal(manifest.network, "anvil");
  assert.equal(manifest.chainId, "31337");
  assert.equal(manifest.protocolVersion, 1);
  assert.match(manifest.environmentId, /^anvil-[0-9a-f-]{36}$/);
  assert.equal(await rpc("eth_chainId"), quantity(31337));
  const genesis = await rpc("eth_getBlockByNumber", ["0x0", false]);
  assert.equal(
    genesis.hash,
    manifest.genesisHash,
    "Genesis changed: previous environment invalidated",
  );
  const code = await rpc("eth_getCode", [manifest.contractAddress, "latest"]);
  assert.notEqual(code, "0x", "Deployment missing after reset");
  assert.equal(cast("keccak", code), manifest.runtimeCodeHash);
  const version = await rpc("eth_call", [{
    to: manifest.contractAddress,
    data: cast("calldata", "protocolVersion()"),
  }, "latest"]);
  assert.equal(BigInt(version), 1n);
  const receipt = await rpc("eth_getTransactionReceipt", [
    manifest.deploymentTransactionHash,
  ]);
  assert(
    receipt && BigInt(receipt.status) === 1n,
    "Deployment receipt missing/reverted",
  );
  assert.equal(receipt.contractAddress.toLowerCase(), manifest.contractAddress);
  assert.equal(receipt.blockNumber, quantity(manifest.deploymentBlock.number));
  assert.equal(receipt.blockHash, manifest.deploymentBlock.hash);
  const block = await rpc("eth_getBlockByNumber", [receipt.blockNumber, false]);
  assert.equal(block.hash, manifest.deploymentBlock.hash);
  assert.equal(
    (await rpc("eth_getBlockByNumber", ["0x0", false])).hash,
    manifest.genesisHash,
  );
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === resolve(root, "scripts/verify-manifest.mjs")
) {
  assert.equal(
    process.argv.length,
    4,
    "Usage: node verify-manifest.mjs http://127.0.0.1:PORT /path/manifest.json",
  );
  await verifyManifest(
    localRpc(process.argv[2]),
    JSON.parse(readFileSync(process.argv[3])),
  );
  console.log("Local deployment identity verified by read-only RPC");
}
