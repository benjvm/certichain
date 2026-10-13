import {
  publicProjection,
  publicTimestamp,
} from "../verify-certificate/contract.ts";
import { decimal, fixedHex, object } from "../_shared/strict_json.ts";
import type { Deployment, Hex } from "../_shared/blockchain/domain/registry.ts";
import { certificateKey } from "../_shared/blockchain/application/commitment.ts";

export interface Evidence {
  state: "included" | "confirmed" | "reorged";
  finality: "unknown" | "not_applicable" | "finalized";
  chain_id: string;
  contract_address: Hex;
  protocol_version: 1;
  certificate_key: Hex;
  issuer_id: Hex;
  commitment: Hex;
  revoked: boolean;
  transaction_hash: Hex;
  block_number: string;
  block_hash: Hex;
  confirmations: string;
  checked_at: string;
  source: "persisted_receipt" | "backend_rpc";
  registered_at?: string;
}
export interface Snapshot {
  registry: Record<string, unknown>;
  anchor: null | {
    deployment: Deployment;
    K: Hex;
    I: Hex;
    C: Hex;
    state: string;
    hash: Hex | null;
    signer: Hex | null;
    previous: Evidence | null;
  };
}
export function openingProjection(input: unknown): boolean {
  try {
    const v = object(input, [
      "protocol_version",
      "credential_code",
      "issuer_id",
      "document_sha256",
      "salt",
      "chain_id",
      "contract_address",
    ]);
    return v.protocol_version === 1 && typeof v.credential_code === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
        v.credential_code,
      ) &&
      [v.issuer_id, v.document_sha256, v.salt].every((x) => fixedHex(x)) &&
      ["31337", "11155111"].includes(v.chain_id as string) &&
      fixedHex(v.contract_address, 20);
  } catch {
    return false;
  }
}
export async function snapshot(
  input: unknown,
  code: string,
  environment: string,
): Promise<Snapshot> {
  const v = object(input, ["registry", "anchor"]);
  if (!publicProjection(v.registry, code)) throw new Error("Projection");
  const registry = v.registry as Record<string, unknown>;
  if (registry.result === "not_found" || v.anchor === null) {
    if (registry.result === "not_found" && v.anchor !== null) {
      throw new Error("Privacy");
    }
    return { registry, anchor: null };
  }
  const a = object(v.anchor, [
    "deployment",
    "certificate_key",
    "issuer_id",
    "commitment",
    "state",
    "transaction_hash",
    "signer",
    "last_evidence",
  ]);
  const d = object(a.deployment, [
    "environment_id",
    "network",
    "chain_id",
    "contract_address",
    "protocol_version",
    "runtime_code_hash",
    "genesis_hash",
    "deployment_block",
    "deployment_hash",
  ]);
  if (
    d.environment_id !== environment ||
    !["anvil", "sepolia"].includes(d.network as string) ||
    d.chain_id !== (d.network === "anvil" ? "31337" : "11155111") ||
    d.protocol_version !== 1 ||
    !fixedHex(d.contract_address, 20) || !fixedHex(d.runtime_code_hash) ||
    !fixedHex(d.genesis_hash) ||
    !fixedHex(d.deployment_hash) || !decimal(d.deployment_block) ||
    d.deployment_block === "0" ||
    !fixedHex(a.certificate_key) || !fixedHex(a.issuer_id) ||
    !fixedHex(a.commitment) ||
    a.certificate_key !== await certificateKey(code) ||
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
    ].includes(a.state as string) ||
    (a.transaction_hash !== null && !fixedHex(a.transaction_hash)) ||
    (a.signer !== null && !fixedHex(a.signer, 20)) ||
    ((a.transaction_hash === null) !== (a.signer === null))
  ) throw new Error("Snapshot");
  const deployment: Deployment = {
    environmentId: environment,
    network: d.network as Deployment["network"],
    chainId: BigInt(d.chain_id as string),
    contractAddress: d.contract_address,
    protocolVersion: 1,
    runtimeCodeHash: d.runtime_code_hash,
    genesisHash: d.genesis_hash,
    deploymentBlock: {
      number: BigInt(d.deployment_block),
      hash: d.deployment_hash,
    },
  };
  let previous: Evidence | null = null;
  if (a.last_evidence !== null) {
    const p = object(a.last_evidence, [
      "state",
      "finality",
      "chain_id",
      "contract_address",
      "protocol_version",
      "certificate_key",
      "issuer_id",
      "commitment",
      "revoked",
      "transaction_hash",
      "block_number",
      "block_hash",
      "confirmations",
      "checked_at",
      "source",
    ]);
    if (
      !["included", "confirmed", "reorged"].includes(p.state as string) ||
      !["unknown", "not_applicable", "finalized"].includes(
        p.finality as string,
      ) ||
      p.chain_id !== d.chain_id || p.contract_address !== d.contract_address ||
      p.protocol_version !== 1 || p.certificate_key !== a.certificate_key ||
      p.issuer_id !== a.issuer_id || p.commitment !== a.commitment ||
      p.revoked !== false ||
      !fixedHex(p.transaction_hash) || !fixedHex(p.block_hash) ||
      !decimal(p.block_number) || !decimal(p.confirmations) ||
      !publicTimestamp(p.checked_at) || p.source !== "persisted_receipt" ||
      (p.finality === "finalized" &&
        (d.network !== "sepolia" || p.state !== "confirmed")) ||
      (p.finality === "not_applicable" && d.network !== "anvil")
    ) throw new Error("Previous evidence");
    previous = p as unknown as Evidence;
  }
  return {
    registry,
    anchor: {
      deployment,
      K: a.certificate_key,
      I: a.issuer_id,
      C: a.commitment,
      state: a.state as string,
      hash: a.transaction_hash as Hex | null,
      signer: a.signer as Hex | null,
      previous,
    },
  };
}
