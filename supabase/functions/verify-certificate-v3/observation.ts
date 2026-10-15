import { decimal, fixedHex, object } from "../_shared/strict_json.ts";
import { publicTimestamp } from "../verify-certificate/contract.ts";
import type { Snapshot } from "../verify-certificate-v2/contract.ts";
import { PublicEvmReader } from "../_shared/blockchain/data/public_reader.ts";
import {
  type Hex,
  RegistryError,
} from "../_shared/blockchain/domain/registry.ts";

export function revocationSnapshot(input: unknown, s: Snapshot) {
  if (s.registry.result === "not_found") {
    if (input !== null) throw new Error();
    return null;
  }
  const r = object(input, [
    "revoked_at",
    "expected",
    "state",
    "transaction_hash",
    "signer",
    "previous",
  ]);
  if (
    (r.revoked_at !== null && !publicTimestamp(r.revoked_at)) ||
    (r.revoked_at !== null) !== (s.registry.result === "revoked") ||
    typeof r.expected !== "boolean" ||
    (r.state !== null &&
      ![
        "requested",
        "prepared",
        "submitted",
        "included",
        "confirmed",
        "reorged",
        "blocked",
        "failed",
        "divergence",
      ].includes(r.state as string)) ||
    r.expected !== (r.state !== null) ||
    (r.transaction_hash !== null && !fixedHex(r.transaction_hash)) ||
    (r.signer !== null && !fixedHex(r.signer, 20)) ||
    ((r.signer === null) !== (r.transaction_hash === null)) ||
    (r.expected && (!s.anchor || r.revoked_at === null))
  ) throw new Error();
  if (r.previous !== null) {
    const p = object(r.previous, [
      "transaction_hash",
      "block_number",
      "block_hash",
      "checked_at",
    ]);
    if (
      !fixedHex(p.transaction_hash) || !fixedHex(p.block_hash) ||
      !decimal(p.block_number) || !publicTimestamp(p.checked_at)
    ) throw new Error();
  }
  return r;
}
export async function observeRevocation(
  s: Snapshot,
  r: ReturnType<typeof revocationSnapshot>,
  rpcUrl: string | undefined,
  deadline: number,
) {
  if (!r) return null;
  const fallback = (state: string, source = "backend_rpc") => ({
    state,
    revoked_at: r.revoked_at,
    checked_at: new Date().toISOString(),
    source,
    evidence: null,
    last_evidence: r.previous,
  });
  if (!r.expected) {
    return fallback(
      r.revoked_at === null ? "not_requested" : "not_applicable",
      "certichain_registry",
    );
  }
  try {
    if (!rpcUrl || !s.anchor) throw new RegistryError("rpc_unavailable");
    const a = s.anchor, reader = new PublicEvmReader(rpcUrl, a.deployment);
    reader.deadline = deadline;
    const chain = await reader.validateDeployment(a.deployment);
    if (r.previous) {
      const p = r.previous as Record<string, string>;
      await reader.canonical({
        number: BigInt(p.block_number),
        hash: p.block_hash as Hex,
      });
    }
    const record = await reader.read(a.K, chain.head);
    if (record && (record.C !== a.C || record.I !== a.I)) {
      throw new RegistryError("divergence");
    }
    if (r.state === "divergence") throw new RegistryError("divergence");
    if (!record || record.revokedAt === 0n) {
      return fallback(
        r.state === "reorged"
          ? "reorged"
          : ["blocked", "failed"].includes(r.state as string)
          ? "blocked"
          : "pending",
      );
    }
    let hash = r.transaction_hash as Hex | null;
    let observation = hash ? await reader.observe(hash) : null;
    if (observation?.kind !== "included" || observation.receipt.status !== 1) {
      let cursor = a.deployment.deploymentBlock.number;
      for (let page = 0; page < 4 && cursor <= chain.head.number; page++) {
        const found = await reader.findRevoke(a.K, cursor, chain.head.number);
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
      { kind: "revoke", K: a.K },
      observation.receipt,
      observation.receipt.from,
    );
    const at = await reader.read(a.K, receipt.block);
    if (
      !at || at.C !== a.C || at.I !== a.I ||
      record.revokedAt !== receipt.timestamp ||
      at.revokedAt !== receipt.timestamp ||
      (hash === r.transaction_hash && receipt.from !== r.signer) ||
      receipt.block.number > chain.head.number
    ) throw new RegistryError("incompatible_evidence");
    const count = chain.head.number - receipt.block.number + 1n,
      confirmed = count >= (a.deployment.network === "anvil" ? 1n : 12n);
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
    const current = fallback(confirmed ? "confirmed" : "included");
    return {
      ...current,
      evidence: {
        transaction_hash: hash,
        block_number: receipt.block.number.toString(),
        block_hash: receipt.block.hash,
        confirmations: count.toString(),
        revoked_at: new Date(Number(record.revokedAt) * 1000).toISOString(),
        checked_at: current.checked_at,
        finality,
      },
    };
  } catch (e) {
    const code = e instanceof RegistryError ? e.code : "rpc_unavailable";
    return fallback(
      code === "reorg"
        ? "reorged"
        : ["divergence", "incompatible_evidence", "deployment_mismatch"]
            .includes(code)
        ? "divergence"
        : "unavailable",
      ["rpc_unavailable", "rpc_timeout"].includes(code)
        ? "unavailable"
        : "backend_rpc",
    );
  }
}
