import { Wallet } from "ethers";
import { sql } from "../scripts/local_supabase.mjs";
import {
  coordinate,
  dbHex,
  type Job,
} from "../functions/_shared/blockchain/application/coordinator.ts";
import {
  bytes,
  digest,
} from "../functions/_shared/blockchain/application/commitment.ts";
import {
  calldata,
  quantity,
} from "../functions/_shared/blockchain/data/evm_registry.ts";
import {
  type Hex,
  RegistryError,
} from "../functions/_shared/blockchain/domain/registry.ts";
import type { phase9dEnvironment } from "./phase9d_environment.ts";

export async function phase10Faults(
  env: Awaited<ReturnType<typeof phase9dEnvironment>>,
  check: (v: unknown, label: string) => void,
) {
  const { f, backend } = env;
  const post = (ep: string, body: unknown) =>
    f.json(`/functions/v1/${ep}`, f.owner.token, body);
  const job = (id: string) =>
    JSON.parse(sql(`SELECT certichain_private.blockchain_job('${id}')`)) as Job;
  const expire = (id: string) =>
    sql(
      `UPDATE certichain_private.blockchain_operations SET lease_until=clock_timestamp()-interval '1 second',next_attempt_at=clock_timestamp()-interval '1 second' WHERE id='${id}'`,
    );
  async function ready(actor = f.owner) {
    const issued = await f.issue(f.owner, {
      institution_id: f.verified,
      holder_id: f.holder.id,
      idempotency_key: crypto.randomUUID(),
      title: "Phase10 fault fixture",
    });
    if (issued.status !== 201) throw new Error("Fault publication failed");
    const certificate = issued.data.certificate_id as string;
    const anchor = await post("anchor-certificate", {
      certificate_id: certificate,
      idempotency_key: crypto.randomUUID(),
    });
    const issue = anchor.data.operation_id as string;
    await env.run(issue);
    await env.run(issue);
    const request = await f.json(
      "/functions/v1/revoke-certificate",
      actor.token,
      {
        certificate_id: certificate,
        idempotency_key: crypto.randomUUID(),
        reason: "Private synthetic fault audit",
      },
    );
    check(
      request.response.status === 202,
      "10 fault decision already irreversible before worker",
    );
    return {
      certificate,
      issue,
      operation: request.data.synchronization[0].operation_id as string,
      sqlDate: request.data.revoked_at as string,
    };
  }
  const reauthorize = async (id: string) => {
    const r = await post("reauthorize-revocation", { operation_id: id });
    check(
      r.response.status === 200,
      "10 fault recovery explicitly reauthorized",
    );
  };
  const binding = JSON.parse(
    sql(
      `SELECT row_to_json(b) FROM certichain_private.blockchain_issuers b WHERE institution_id='${f.verified}'`,
    ),
  );
  async function configure(signer: Hex, canRevoke: boolean) {
    const cmd = {
      kind: "set_issuer" as const,
      I: dbHex(binding.issuer_id),
      signer,
      canIssue: true,
      canRevoke,
    };
    const id = await backend.rpc<string>("blockchain_configure_issuer", {
      p_actor: f.platform.id,
      p_deployment: binding.deployment_id,
      p_institution: f.verified,
      p_i: cmd.I,
      p_signer: signer,
      p_issue: true,
      p_revoke: canRevoke,
      p_key: crypto.randomUUID(),
      p_payload: await digest(bytes(calldata(cmd))),
    });
    await env.run(id, true);
    await env.run(id, true);
  }
  for (const point of ["stored", "broadcast", "receipt"] as const) {
    const { operation, certificate, sqlDate } = await ready();
    if (point === "receipt") await env.run(operation);
    try {
      await env.run(operation, false, {
        barrier: (at) => {
          if (at === point) throw new Error("HARNESS_CRASH");
          return Promise.resolve();
        },
      });
    } catch (e) {
      if (!(e instanceof Error) || e.message !== "HARNESS_CRASH") throw e;
    }
    const old = job(operation);
    check(
      old.attempts.length === 1,
      `10 revoke ${point} crash keeps one durable attempt`,
    );
    expire(operation);
    env.restartWorker(operation);
    env.restartWorker(operation);
    check(
      job(operation).operation.state === "confirmed" &&
        job(operation).attempts.length === 1,
      `10 separate worker recovers revoke ${point} without duplicate signature`,
    );
    let fenced = false;
    try {
      await backend.rpc("blockchain_update_job", {
        p_operation: operation,
        p_token: old.operation.lease_token,
        p_generation: old.operation.generation,
        p_action: "release",
      });
    } catch (e) {
      fenced = e instanceof RegistryError && e.code === "busy";
    }
    check(fenced, `10 revoke ${point} stale CAS fenced`);
    check(
      (await post("revocation-progress", { certificate_id: certificate })).data
        .revoked_at === sqlDate,
      "10 crashes preserve original SQL date",
    );
  }
  {
    const admin = await f.user("signed-revoke-admin");
    await f.rpc("set_institution_member", {
      p_institution: f.verified,
      p_member: admin.id,
      p_role: "admin",
    }, f.owner.token);
    const { operation } = await ready(admin);
    try {
      await env.run(operation, false, {
        barrier: (point) => {
          if (point === "stored") throw new Error("HARNESS_CRASH");
          return Promise.resolve();
        },
      });
    } catch (e) {
      if (!(e instanceof Error) || e.message !== "HARNESS_CRASH") throw e;
    }
    await f.rpc("remove_institution_member", {
      p_institution: f.verified,
      p_member: admin.id,
    }, f.owner.token);
    expire(operation);
    await env.run(operation);
    await env.run(operation);
    check(
      job(operation).operation.state === "confirmed" &&
        job(operation).attempts.length === 1,
      "10 human permission loss still allows reconciliation of already signed revoke",
    );
  }
  {
    const { operation } = await ready();
    let persisted = false;
    const store = {
      deadline: Infinity,
      pdf: backend.pdf.bind(backend),
      rpc: <T>(name: string, args?: Record<string, unknown>): Promise<T> => {
        if (name === "blockchain_store_prepared") {
          persisted = true;
          throw new RegistryError("rpc_unavailable");
        }
        return backend.rpc<T>(name, args);
      },
    };
    const before = (await env.registry.nonce()).latest;
    check(
      await coordinate(store, operation, () => env.registry) ===
          "rpc_unavailable" && persisted,
      "10 signature persistence failure closes before broadcast",
    );
    env.registry.deadline = Infinity;
    check(
      job(operation).attempts.length === 0 &&
        (await env.registry.nonce()).latest === before,
      "10 unpersisted signature never sent or consumes nonce",
    );
    await env.run(operation);
    await env.run(operation);
    check(
      job(operation).operation.state === "confirmed",
      "10 pre-persistence crash recovers same reservation",
    );
  }
  {
    const { operation } = await ready();
    await env.rpc.rpc("anvil_setBalance", [env.registry.signer, "0x0"]);
    check(
      await env.run(operation) === "insufficient_funds" &&
        job(operation).attempts.length === 0,
      "10 insufficient funds blocks EVM only",
    );
    await env.rpc.rpc("anvil_setBalance", [
      env.registry.signer,
      quantity(100000000000000000000n),
    ]);
    await reauthorize(operation);
    await env.run(operation);
    await env.run(operation);
    check(
      job(operation).operation.state === "confirmed",
      "10 funding recovery uses explicit reauthorization",
    );
  }
  {
    const { operation } = await ready();
    const snapshot = await env.rpc.rpc<Hex>("evm_snapshot");
    const before = sql(
      `SELECT next_nonce FROM certichain_private.blockchain_signer_nonces WHERE deployment_id='${binding.deployment_id}' AND signer=decode('${
        env.registry.signer.slice(2)
      }','hex')`,
    );
    const nonce = (await env.registry.nonce()).latest;
    await env.rpc.rpc("anvil_setNonce", [
      env.registry.signer,
      quantity(nonce + 1n),
    ]);
    check(
      await env.run(operation) === "nonce_conflict" &&
        job(operation).attempts.length === 0,
      "10 unknown nonce is blocked, never skipped to prioritize revoke",
    );
    check(
      sql(
        `SELECT next_nonce FROM certichain_private.blockchain_signer_nonces WHERE deployment_id='${binding.deployment_id}' AND signer=decode('${
          env.registry.signer.slice(2)
        }','hex')`,
      ) === before,
      "10 unknown nonce never advances private ledger",
    );
    await env.rpc.rpc("evm_revert", [snapshot]);
    await reauthorize(operation);
    await env.run(operation);
    await env.run(operation);
    check(
      job(operation).operation.state === "confirmed",
      "10 exact original synthetic chain restoration recovers known nonce",
    );
  }
  for (const flag of ["enabled", "writes_stopped"]) {
    const { operation } = await ready();
    sql(
      `UPDATE certichain_private.blockchain_deployments SET ${flag}=${
        flag === "enabled" ? "false" : "true"
      } WHERE id='${binding.deployment_id}'`,
    );
    check(
      await env.run(operation) === "authorization_denied" &&
        job(operation).attempts.length === 0,
      `10 ${flag} forbids new signatures without moving obligations`,
    );
    sql(
      `UPDATE certichain_private.blockchain_deployments SET ${flag}=${
        flag === "enabled" ? "true" : "false"
      } WHERE id='${binding.deployment_id}'`,
    );
    await reauthorize(operation);
    await env.run(operation);
    await env.run(operation);
    check(
      job(operation).operation.state === "confirmed",
      `10 ${flag} recovery uses exact same deployment`,
    );
  }
  {
    const { operation } = await ready();
    await configure(env.registry.signer, false);
    check(
      await env.run(operation) === "authorization_denied" &&
        job(operation).attempts.length === 0,
      "10 canRevoke false blocks despite canIssue true",
    );
    await configure(env.registry.signer, true);
    await reauthorize(operation);
    await env.run(operation);
    await env.run(operation);
    check(
      job(operation).operation.state === "confirmed",
      "10 withdrawn permission requires audited retry after restoration",
    );
  }
  {
    const { operation, issue } = await ready();
    try {
      await env.run(operation, false, {
        barrier: (point) => {
          if (point === "stored") throw new Error("HARNESS_CRASH");
          return Promise.resolve();
        },
      });
    } catch (e) {
      if (!(e instanceof Error) || e.message !== "HARNESS_CRASH") throw e;
    }
    const original = job(operation).attempts[0];
    // An already signed transaction cannot be cancelled by removing permission.
    await configure(env.registry.signer, false);
    expire(operation);
    await env.run(operation);
    await env.run(operation);
    check(
      job(operation).operation.state === "failed" &&
        job(operation).attempts[0].state === "reverted",
      "10 real revoke revert consumes nonce and retains failed receipt",
    );
    const next = Wallet.createRandom();
    await env.rpc.rpc("anvil_setBalance", [
      next.address,
      quantity(100000000000000000000n),
    ]);
    await configure(next.address.toLowerCase() as Hex, true);
    await reauthorize(operation);
    await env.runWithSigner(operation, next.privateKey);
    await env.runWithSigner(operation, next.privateKey);
    const recovered = job(operation);
    check(
      recovered.operation.state === "confirmed" &&
        recovered.attempts.length === 2 &&
        recovered.attempts[1].signer !== original.signer &&
        recovered.attempts[1].nonce === "0",
      "10 rotated signer revokes stored I after consumed revert with fresh EOA nonce",
    );
    const observation = await env.registry.observe(
      dbHex(job(issue).attempts[0].transaction_hash),
    );
    let rejected = false;
    if (observation.kind === "included") {
      try {
        await env.registry.validateEvidence(
          { kind: "revoke", K: dbHex(recovered.anchor!.certificate_key) },
          observation.receipt,
          observation.receipt.from,
        );
      } catch (e) {
        rejected = e instanceof RegistryError &&
          e.code === "incompatible_evidence";
      }
    }
    check(
      rejected,
      "10 real successful issue receipt cannot stand in for revoke evidence",
    );
    await configure(env.registry.signer, true);
  }
  sql(
    "UPDATE certichain_private.public_verification_budget SET used=0,window_started_at=clock_timestamp()",
  );
}
