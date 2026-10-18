import { calldata, EvmRegistry } from "./evm_registry.ts";
import { registryRuntimeHash } from "./registry_abi.ts";
import {
  type Deployment,
  type Hex,
  type Receipt,
  RegistryError,
} from "../domain/registry.ts";

const hex = (b: string, size = 32) => `0x${b.repeat(size)}` as Hex;
const deployment: Deployment = {
  environmentId: "local",
  network: "anvil",
  chainId: 31337n,
  contractAddress: hex("11", 20),
  protocolVersion: 1,
  runtimeCodeHash: registryRuntimeHash,
  genesisHash: hex("22"),
  deploymentBlock: { number: 1n, hash: hex("33") },
};
async function rejects(action: () => Promise<unknown>, code: string) {
  try {
    await action();
  } catch (e) {
    if (e instanceof RegistryError && e.code === code) return;
    throw e;
  }
  throw new Error("Expected closed registry failure");
}
for (
  const field of [
    "contractAddress",
    "genesisHash",
    "deploymentBlock",
    "chainId",
    "environmentId",
  ] as const
) {
  Deno.test(`deployment identity refuses another ${field} before RPC or signing`, async () => {
    const registry = new EvmRegistry("http://127.0.0.1:1", deployment);
    registry.rpc = () => {
      throw new Error("Unexpected RPC for incompatible binding");
    };
    const expected = { ...deployment };
    if (field === "deploymentBlock") {
      expected.deploymentBlock = { number: 1n, hash: hex("44") };
    } else if (field === "chainId") expected.chainId = 11155111n;
    else {expected[field] = field === "contractAddress"
        ? hex("44", 20)
        : hex("44");}
    await rejects(
      () => registry.validateDeployment(expected),
      "deployment_mismatch",
    );
  });
}
for (
  const mismatch of [
    "missing",
    "status",
    "blockHash",
    "from",
    "to",
    "transactionIndex",
  ] as const
) {
  Deno.test(`second revoke receipt read ${mismatch} cannot supply current evidence`, async () => {
    const registry = new EvmRegistry("http://127.0.0.1:1", deployment);
    const command = { kind: "revoke" as const, K: hex("55") };
    const receipt: Receipt = {
      hash: hex("66"),
      status: 1,
      from: hex("77", 20),
      to: deployment.contractAddress,
      block: { number: 2n, hash: hex("88") },
      transactionIndex: 0n,
      logIndex: null,
      timestamp: 10n,
      data: calldata(command),
      nonce: 0n,
      gasUsed: 50000n,
    };
    const raw = {
      transactionHash: receipt.hash,
      status: "0x1",
      from: receipt.from,
      to: receipt.to,
      blockNumber: "0x2",
      blockHash: receipt.block.hash,
      transactionIndex: "0x0",
      logs: [],
    };
    if (mismatch !== "missing") {
      raw[mismatch] = mismatch === "status" || mismatch === "transactionIndex"
        ? "0x0f"
        : hex("99");
    }
    registry.rpc = <T>() =>
      Promise.resolve((mismatch === "missing" ? null : raw) as T);
    await rejects(
      () => registry.validateEvidence(command, receipt, receipt.from),
      mismatch === "missing" ? "rpc_unavailable" : "incompatible_evidence",
    );
  });
}
