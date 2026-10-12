import { commitment, digest } from "./commitment.ts";
import {
  type Deployment,
  type Fees,
  type Hex,
  type OperationalRegistry,
  type PreparedTx,
  type RegistryCommand,
  RegistryError,
} from "../domain/registry.ts";
export interface AnchoringStore {
  deadline: number;
  rpc<T>(name: string, args?: Record<string, unknown>): Promise<T>;
  pdf(path: string): Promise<Uint8Array>;
}
export interface Attempt {
  id: string;
  transaction_hash: string;
  raw_signed_tx: string | null;
  nonce: string;
  signer: string;
  calldata: string;
  calldata_digest: string;
  gas_limit: string;
  max_fee_per_gas: string;
  max_priority_fee_per_gas: string;
  block_number: string | null;
  block_hash: string | null;
  state: string;
  created_at: string;
}
export interface Job {
  operation: {
    id: string;
    kind: string;
    state: string;
    lease_token: string;
    generation: string;
    authorized_by: string;
    canonical_attempt_id: string | null;
    target_signer: string | null;
    target_can_issue: boolean;
    target_can_revoke: boolean;
    event_cursor: string | null;
    payload_digest: string;
  };
  deployment: {
    id: string;
    environment_id: string;
    network: "anvil" | "sepolia";
    chain_id: string;
    contract_address: string;
    runtime_code_hash: string;
    protocol_version: 1;
    deployment_block: string;
    deployment_hash: string;
    genesis_hash: string;
    enabled: boolean;
    writes_stopped: boolean;
  };
  binding: {
    issuer_id: string;
    signer: string;
    desired_can_issue: boolean;
    sync_state: string;
    institution_id: string;
  };
  anchor: {
    certificate_key: string;
    commitment: string;
    document_sha256: string;
    salt: string;
    credential_code_snapshot: string;
    certificate_id: string;
  } | null;
  attempts: Attempt[];
}
export const dbHex = (v: string): Hex =>
  (v.startsWith("\\x") ? `0x${v.slice(2)}` : v) as Hex;
export function deployment(job: Job): Deployment {
  const d = job.deployment;
  return {
    environmentId: d.environment_id,
    network: d.network,
    chainId: BigInt(d.chain_id),
    contractAddress: dbHex(d.contract_address),
    protocolVersion: d.protocol_version,
    runtimeCodeHash: dbHex(d.runtime_code_hash),
    deploymentBlock: {
      number: BigInt(d.deployment_block),
      hash: dbHex(d.deployment_hash),
    },
    genesisHash: dbHex(d.genesis_hash),
  };
}
export function command(job: Job): RegistryCommand {
  if (job.operation.kind === "set_issuer") {
    return {
      kind: "set_issuer",
      I: dbHex(job.binding.issuer_id),
      signer: dbHex(job.operation.target_signer!),
      canIssue: job.operation.target_can_issue,
      canRevoke: job.operation.target_can_revoke,
    };
  }
  if (!job.anchor || job.operation.kind !== "issue") {
    throw new RegistryError("authorization_denied");
  }
  return {
    kind: "issue",
    K: dbHex(job.anchor.certificate_key),
    C: dbHex(job.anchor.commitment),
    I: dbHex(job.binding.issuer_id),
  };
}
export function txJson(tx: PreparedTx) {
  return {
    hash: tx.hash,
    raw: tx.rawSignedTx,
    signer: tx.signer,
    nonce: tx.nonce.toString(),
    data: tx.data,
    digest: tx.calldataDigest,
    gas: tx.gasLimit.toString(),
    fee: tx.maxFeePerGas.toString(),
    tip: tx.maxPriorityFeePerGas.toString(),
  };
}
function prepared(job: Job, attempt: Attempt): PreparedTx {
  if (!attempt.raw_signed_tx) throw new RegistryError("opening_unavailable");
  return {
    hash: dbHex(attempt.transaction_hash),
    rawSignedTx: dbHex(attempt.raw_signed_tx),
    signer: dbHex(attempt.signer),
    nonce: BigInt(attempt.nonce),
    data: dbHex(attempt.calldata),
    calldataDigest: dbHex(attempt.calldata_digest),
    chainId: BigInt(job.deployment.chain_id),
    to: dbHex(job.deployment.contract_address),
    gasLimit: BigInt(attempt.gas_limit),
    maxFeePerGas: BigInt(attempt.max_fee_per_gas),
    maxPriorityFeePerGas: BigInt(attempt.max_priority_fee_per_gas),
  };
}
export interface CoordinatorOptions {
  admin?: boolean;
  deadline?: number;
  // Injection only by code in the isolated harness; never environment/HTTP parameters.
  barrier?: (point: "stored" | "broadcast" | "receipt") => Promise<void>;
  now?: () => number;
}
export async function coordinate(
  backend: AnchoringStore,
  id: string,
  registryFactory: (job: Job) => OperationalRegistry,
  options: CoordinatorOptions = {},
) {
  let job: Job;
  backend.deadline = Math.min(Date.now() + 30000, options.deadline ?? Infinity);
  try {
    job = await backend.rpc<Job>("blockchain_claim", { p_operation: id });
  } catch (e) {
    if (e instanceof RegistryError && e.code === "busy") return "busy";
    throw e;
  }
  const fence = {
    p_operation: id,
    p_token: job.operation.lease_token,
    p_generation: job.operation.generation,
  };
  const update = async (
    action: string,
    detail: Record<string, unknown> = {},
  ) => {
    job = await backend.rpc<Job>("blockchain_update_job", {
      ...fence,
      p_action: action,
      p_detail: detail,
    });
  };
  const registry = registryFactory(job);
  registry.deadline = backend.deadline;
  let renewed = (options.now ?? Date.now)();
  const renew = async () => {
    if ((options.now ?? Date.now)() - renewed >= 30000) {
      await update("renew");
      renewed = (options.now ?? Date.now)();
    }
  };
  try {
    if ((job.operation.kind === "set_issuer") !== !!options.admin) {
      await update("release");
      return "different_signer";
    }
    const cmd = command(job);
    const chain = await registry.validateDeployment(deployment(job));
    if (job.operation.state === "divergence") {
      await update("release");
      return "divergence";
    }
    // Validate the previously canonical block even when receipt RPC now returns null.
    const canonical = job.attempts.find((t) =>
      t.id === job.operation.canonical_attempt_id
    );
    if (canonical?.block_hash && canonical.block_number !== null) {
      try {
        await registry.canonical({
          number: BigInt(canonical.block_number),
          hash: dbHex(canonical.block_hash),
        });
      } catch (e) {
        if (e instanceof RegistryError && e.code === "reorg") {
          await update("reorg");
          if (job.operation.state === "divergence") {
            await update("release");
            return "divergence";
          }
        } else throw e;
      }
    }
    // Every hash is observed; an earlier replacement may win. Permission changes
    // never prevent reconciliation of bytes already signed.
    for (const [attemptIndex, attempt] of job.attempts.entries()) {
      await renew();
      const observation = await registry.observe(
        dbHex(attempt.transaction_hash),
      );
      if (observation.kind === "included") {
        let receipt;
        try {
          receipt = await registry.validateEvidence(
            cmd,
            observation.receipt,
            dbHex(attempt.signer),
          );
        } catch (e) {
          if (
            e instanceof RegistryError && e.code === "incompatible_evidence"
          ) {
            await update("incompatible", {
              hash: observation.receipt.hash,
              status: observation.receipt.status,
              block_number: observation.receipt.block.number.toString(),
              block_hash: observation.receipt.block.hash,
              transaction_index: observation.receipt.transactionIndex
                .toString(),
            });
            await update("release");
            return "incompatible_evidence";
          }
          throw e;
        }
        if (
          receipt.status === 0 && attempt.state === "reverted" &&
          (job.operation.state === "requested" ||
            job.attempts.slice(attemptIndex + 1).some((t) =>
              t.signer !== attempt.signer ||
              BigInt(t.nonce) > BigInt(attempt.nonce)
            ))
        ) continue;
        const confirmations = observation.chain.head.number -
          receipt.block.number + 1n;
        let finality = "unknown";
        if (job.deployment.network === "anvil") finality = "not_applicable";
        else if (
          confirmations >= 12n && observation.chain.finalized &&
          observation.chain.finalized.number >= receipt.block.number
        ) {
          await registry.canonical(receipt.block);
          await registry.canonical(observation.chain.finalized);
          finality = "finalized";
        }
        await options.barrier?.("receipt");
        await update("receipt", {
          hash: receipt.hash,
          status: receipt.status,
          block_number: receipt.block.number.toString(),
          block_hash: receipt.block.hash,
          transaction_index: receipt.transactionIndex.toString(),
          validated_log_index: receipt.logIndex?.toString() ?? null,
          head_number: observation.chain.head.number.toString(),
          head_hash: observation.chain.head.hash,
          confirmations: confirmations.toString(),
          finality,
          finalized_number: observation.chain.finalized?.number.toString() ??
            null,
          finalized_hash: observation.chain.finalized?.hash ?? null,
        });
        if (cmd.kind === "set_issuer") {
          const observed = await registry.issuer(cmd.I, observation.chain.head);
          await update("configuration", {
            signer: observed.signer,
            can_issue: observed.canIssue,
            can_revoke: observed.canRevoke,
            block_number: observation.chain.head.number.toString(),
            block_hash: observation.chain.head.hash,
          });
        }
        if (cmd.kind === "issue" && receipt.status === 1) {
          const latest = await registry.read(cmd.K, observation.chain.head);
          if (
            !latest || latest.C !== cmd.C || latest.I !== cmd.I ||
            latest.revokedAt !== 0n
          ) throw new RegistryError("divergence");
        }
        await update("release");
        return job.operation.state;
      }
      await update(observation.kind, { hash: dbHex(attempt.transaction_hash) });
    }
    if (cmd.kind === "issue") {
      const record = await registry.read(cmd.K, chain.head);
      if (record) {
        if (
          record.C !== cmd.C || record.I !== cmd.I || record.revokedAt !== 0n
        ) throw new RegistryError("divergence");
        let cursor = BigInt(
          job.operation.event_cursor ?? job.deployment.deployment_block,
        );
        // Four pages per pass, each <=2,000 blocks; durable cursor.
        for (let page = 0; page < 4 && cursor <= chain.head.number; page++) {
          await renew();
          const found = await registry.findIssue(
            cmd.K,
            cursor,
            chain.head.number,
          );
          if (found.hash) {
            const observed = await registry.observe(found.hash);
            if (observed.kind !== "included") {
              throw new RegistryError("incompatible_evidence");
            }
            const recovered = await registry.recoverPrepared(found.hash);
            await registry.validateEvidence(
              cmd,
              observed.receipt,
              recovered.signer,
            );
            job = await backend.rpc<Job>("blockchain_recover_attempt", {
              ...fence,
              p_tx: txJson(recovered),
            });
            await update("release");
            return "recovered";
          }
          cursor = found.cursor;
          await update("cursor", { cursor: cursor.toString() });
        }
        if (cursor > chain.head.number) {
          throw new RegistryError("incompatible_evidence");
        }
        await update("release");
        return "searching";
      }
    }
    if (job.operation.state === "divergence") {
      await update("release");
      return "divergence";
    }
    // Signed bytes can be resent regardless of subsequent SQL membership changes.
    let last = job.attempts.at(-1);
    if (last?.state === "reverted" && job.operation.state === "requested") {
      last = undefined;
    }
    if (last) {
      const latest = await registry.latestNonce(dbHex(last.signer));
      if (latest > BigInt(last.nonce)) {
        throw new RegistryError("nonce_conflict");
      }
      if (!last.raw_signed_tx) throw new RegistryError("opening_unavailable");
      if (
        (options.now ?? Date.now)() - Date.parse(last.created_at) < 300000 ||
        ["blocked", "failed"].includes(job.operation.state)
      ) {
        try {
          await registry.broadcast(prepared(job, last));
        } catch (e) {
          if (!(e instanceof RegistryError && e.code === "nonce_conflict")) {
            throw e;
          }
        }
        await update("submitted", { hash: dbHex(last.transaction_hash) });
        await update("release");
        return "submitted";
      }
      if (job.attempts.filter((t) => t.nonce === last!.nonce).length >= 4) {
        throw new RegistryError("insufficient_funds");
      }
    }
    await backend.rpc("blockchain_authorize_job", fence);
    if (cmd.kind === "issue") {
      if (!job.anchor?.salt) throw new RegistryError("opening_unavailable");
      const actual = await commitment(
        job.anchor.credential_code_snapshot,
        cmd.I,
        dbHex(job.anchor.document_sha256),
        dbHex(job.anchor.salt),
      );
      if (actual.K !== cmd.K || actual.C !== cmd.C) {
        throw new RegistryError("opening_unavailable");
      }
      const pdf = await backend.pdf(
        `${job.binding.institution_id}/${job.anchor.certificate_id}.pdf`,
      );
      if (await digest(pdf) !== dbHex(job.anchor.document_sha256)) {
        throw new RegistryError("divergence");
      }
      const issuer = await registry.issuer(cmd.I, chain.head);
      if (!issuer.canIssue || issuer.signer !== registry.signer) {
        throw new RegistryError("authorization_denied");
      }
    } else {
      const owner = await registry.owner(chain.head);
      if (
        owner !== registry.signer ||
        registry.signer === dbHex(job.binding.signer)
      ) throw new RegistryError("authorization_denied");
    }
    const counts = await registry.nonce();
    const nonce = BigInt(
      await backend.rpc<string>("blockchain_reserve_nonce", {
        ...fence,
        p_signer: registry.signer,
        p_latest: counts.latest.toString(),
        p_pending: counts.pending.toString(),
      }),
    );
    const previous: Fees | undefined = last
      ? {
        gasLimit: BigInt(last.gas_limit),
        maxFeePerGas: BigInt(last.max_fee_per_gas),
        maxPriorityFeePerGas: BigInt(last.max_priority_fee_per_gas),
      }
      : undefined;
    const fees = await registry.fees(cmd, previous);
    await renew();
    await backend.rpc("blockchain_authorize_job", fence);
    const tx = await registry.prepare(cmd, nonce, fees);
    job = await backend.rpc<Job>("blockchain_store_prepared", {
      ...fence,
      p_tx: txJson(tx),
    });
    await options.barrier?.("stored");
    // Commit failure above terminates before this send.
    last = job.attempts.at(-1)!;
    await registry.broadcast(prepared(job, last));
    await options.barrier?.("broadcast");
    await update("submitted", { hash: tx.hash });
    await update("release");
    return "submitted";
  } catch (e) {
    const code = e instanceof RegistryError ? e.code : "rpc_unavailable";
    // A barrier exception represents abrupt process death in the harness: it
    // intentionally bypasses cleanup/CAS. Production has no injected barriers.
    if (e instanceof Error && e.message === "HARNESS_CRASH") throw e;
    try {
      await update("error", {
        error:
          ["duplicate_key", "already_revoked", "key_conflict", "invalid_input"]
              .includes(code)
            ? "incompatible_evidence"
            : code,
      });
    } catch (fenced) {
      if (!(fenced instanceof RegistryError && fenced.code === "busy")) {
        throw fenced;
      }
    }
    return code;
  }
}
