import { PublicEvmReader } from "../_shared/blockchain/data/public_reader.ts";
import { RegistryError } from "../_shared/blockchain/domain/registry.ts";
import type { Snapshot } from "./contract.ts";

export async function observe(
  snapshot: Snapshot,
  rpcUrl: string | undefined,
  deadline: number,
) {
  const a = snapshot.anchor;
  if (!a) {
    return {
      state: "off_chain_only",
      finality: "unknown",
      checked_at: snapshot.registry.checked_at,
      source: "certichain_registry",
    };
  }
  const previous = a.previous ? { last_evidence: a.previous } : {};
  const fallback = (state: string, source = "unavailable") => ({
    state,
    finality: "unknown",
    checked_at: new Date().toISOString(),
    source,
    ...previous,
  });
  try {
    if (!rpcUrl) throw new RegistryError("rpc_unavailable");
    const reader = new PublicEvmReader(rpcUrl, a.deployment);
    reader.deadline = deadline;
    const chain = await reader.validateDeployment(a.deployment);
    // A previously validated block must still be canonical. Null alone is not
    // evidence of reorg; canonical() also checks a stable lower head.
    if (a.previous) {
      await reader.canonical({
        number: BigInt(a.previous.block_number),
        hash: a.previous.block_hash,
      });
    }
    const record = await reader.read(a.K, chain.head);
    if (record && (record.C !== a.C || record.I !== a.I)) {
      throw new RegistryError("divergence");
    }
    if (!record) {
      if (a.previous) throw new RegistryError("divergence");
      return fallback(
        a.state === "divergence" ? "divergence" : "pending",
        "backend_rpc",
      );
    }
    // Recover a public receipt read-only if persisted attempts are absent or
    // another replacement won. Search is bounded, never queues a worker.
    let hash = a.hash;
    let observation = hash ? await reader.observe(hash) : null;
    if (observation?.kind !== "included" || observation.receipt.status !== 1) {
      let cursor = a.deployment.deploymentBlock.number;
      for (let page = 0; page < 4 && cursor <= chain.head.number; page++) {
        const found = await reader.findIssue(a.K, cursor, chain.head.number);
        cursor = found.cursor;
        if (found.hash) {
          hash = found.hash;
          observation = await reader.observe(hash);
          break;
        }
      }
    }
    if (
      !hash || observation?.kind !== "included" ||
      observation.receipt.status !== 1
    ) throw new RegistryError("rpc_unavailable");
    const receipt = await reader.validateEvidence(
      { kind: "issue", K: a.K, C: a.C, I: a.I },
      observation.receipt,
      observation.receipt.from,
    );
    if (hash === a.hash && receipt.from !== a.signer) {
      throw new RegistryError("incompatible_evidence");
    }
    if (
      receipt.timestamp !== record.registeredAt ||
      receipt.block.number > chain.head.number
    ) throw new RegistryError("divergence");
    // Bind every log to this inclusion, not just its decoded payload.
    const raw = await reader.rpc<
      {
        transactionHash: string;
        blockHash: string;
        blockNumber: string;
        status: string;
        from: string;
        to: string;
        transactionIndex: string;
        logs: {
          transactionHash: string;
          blockHash: string;
          blockNumber: string;
          logIndex: string;
        }[];
      }
    >("eth_getTransactionReceipt", [hash]);
    if (
      !raw || raw.transactionHash !== hash ||
      raw.status !== "0x1" || raw.from !== receipt.from ||
      raw.to !== receipt.to ||
      BigInt(raw.transactionIndex) !== receipt.transactionIndex ||
      raw.blockHash !== receipt.block.hash ||
      BigInt(raw.blockNumber) !== receipt.block.number ||
      raw.logs.some((l) =>
        l.transactionHash !== hash || l.blockHash !== receipt.block.hash ||
        BigInt(l.blockNumber) !== receipt.block.number
      )
    ) throw new RegistryError("incompatible_evidence");
    const confirmations = chain.head.number - receipt.block.number + 1n;
    const confirmed =
      confirmations >= (a.deployment.network === "anvil" ? 1n : 12n);
    let finality = a.deployment.network === "anvil"
      ? "not_applicable"
      : "unknown";
    if (
      confirmed && chain.finalized &&
      chain.finalized.number >= receipt.block.number &&
      chain.finalized.number <= chain.head.number
    ) {
      await reader.canonical(chain.finalized);
      finality = "finalized";
    }
    await reader.canonical(chain.head);
    await reader.canonical(receipt.block);
    const revoked = record.revokedAt > 0n;
    const state = (revoked !== (snapshot.registry.result === "revoked") ||
        a.state === "divergence")
      ? "divergence"
      : confirmed
      ? "confirmed"
      : "included";
    const seconds = record.registeredAt;
    if (seconds <= 0n || seconds > 253402300799n) {
      throw new RegistryError("incompatible_evidence");
    }
    return {
      state,
      finality: state === "divergence" ? "unknown" : finality,
      chain_id: a.deployment.chainId.toString(),
      contract_address: a.deployment.contractAddress,
      protocol_version: 1,
      certificate_key: a.K,
      issuer_id: a.I,
      commitment: a.C,
      revoked,
      transaction_hash: hash,
      block_number: receipt.block.number.toString(),
      block_hash: receipt.block.hash,
      confirmations: confirmations.toString(),
      registered_at: new Date(Number(seconds) * 1000).toISOString(),
      checked_at: new Date().toISOString(),
      source: "backend_rpc",
      ...previous,
    };
  } catch (e) {
    const code = e instanceof RegistryError ? e.code : "rpc_unavailable";
    const observedError = ["reorg", "divergence", "incompatible_evidence"]
      .includes(code);
    return fallback(
      code === "reorg"
        ? a.previous?.finality === "finalized" ? "divergence" : "reorged"
        : ["divergence", "incompatible_evidence", "deployment_mismatch"]
            .includes(code)
        ? "divergence"
        : "unavailable",
      observedError ? "backend_rpc" : "unavailable",
    );
  }
}
