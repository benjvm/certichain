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
  EvmRegistry,
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
      `UPDATE certichain_private.blockchain_operations SET lease_until=CASE WHEN lease_token IS NULL THEN NULL ELSE clock_timestamp()-interval '1 second' END,next_attempt_at=clock_timestamp()-interval '1 second' WHERE id='${id}'`,
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
  // Compare exact immutable rows and PDF bytes in memory; never serialize them to evidence.
  async function immutableSnapshot(certificate: string) {
    const rows = sql(`SELECT jsonb_build_array(
      (SELECT to_jsonb(c) FROM public.certificates c WHERE c.id='${certificate}'),
      (SELECT to_jsonb(r) FROM certichain_private.certificate_revocations r WHERE r.certificate_id='${certificate}'),
      (SELECT to_jsonb(i) FROM public.certificate_issuance_operations i WHERE i.certificate_id='${certificate}'),
      (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM certichain_private.certificate_anchors a WHERE a.certificate_id='${certificate}'))`);
    const pdf = await digest(
      await backend.pdf(`${f.verified}/${certificate}.pdf`),
    );
    return { rows, pdf };
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
    const { operation, certificate } = await ready();
    const before = await immutableSnapshot(certificate);
    const transport = Object.create(env.registry) as EvmRegistry;
    transport.broadcast = async (tx) => {
      await env.registry.broadcast(tx);
      throw new RegistryError("rpc_timeout");
    };
    check(
      await coordinate(backend, operation, () => transport) === "rpc_timeout",
      "10C node accepts raw revoke but transport loses response",
    );
    const signed = job(operation).attempts[0];
    check(
      !!signed && job(operation).operation.state === "prepared",
      "10C lost broadcast response retains durable hash without claiming success",
    );
    expire(operation);
    env.restartWorker(operation);
    check(
      job(operation).operation.state === "confirmed" &&
        job(operation).attempts.length === 1 &&
        job(operation).attempts[0].transaction_hash === signed.transaction_hash,
      "10C new process reconciles accepted broadcast without another logical operation or signature",
    );
    const after = await immutableSnapshot(certificate);
    check(
      JSON.stringify(before) === JSON.stringify(after),
      "10C response loss preserves original SQL audit completed PDF and K/I/C/S",
    );
  }
  for (const incompatibleAt of ["receipt", "head"] as const) {
    const { operation, certificate } = await ready();
    const before = await immutableSnapshot(certificate);
    await env.run(operation);
    // Real receipt/event/chain, incompatible state supplied by a faulty RPC read.
    const faulty = Object.create(env.registry) as EvmRegistry;
    const receipt = await env.registry.observe(
      dbHex(job(operation).attempts[0].transaction_hash),
    );
    if (receipt.kind !== "included") {
      throw new Error("Expected owned mined revoke");
    }
    await env.rpc.rpc("evm_mine");
    faulty.read = async (K, block) => {
      const record = await env.registry.read(K, block);
      const corrupt = incompatibleAt === "receipt"
        ? block.number === receipt.receipt.block.number
        : block.number > receipt.receipt.block.number;
      return record && corrupt
        ? { ...record, C: `0x${"ff".repeat(32)}` as Hex }
        : record;
    };
    expire(operation);
    check(
      await coordinate(backend, operation, () => faulty) ===
        "incompatible_evidence",
      `10C incompatible ${incompatibleAt} state rejects real revoke receipt`,
    );
    check(
      sql(
            `SELECT state='divergence' AND canonical_attempt_id IS NULL AND confirmations=0 FROM certichain_private.blockchain_operations WHERE id='${operation}'`,
          ) === "t" &&
        sql(
            `SELECT active_operation_id='${operation}'::uuid FROM certichain_private.blockchain_signer_nonces WHERE deployment_id='${binding.deployment_id}' AND signer=decode('${
              env.registry.signer.slice(2)
            }','hex')`,
          ) === "t",
      "10C incompatible state never promotes receipt or releases nonce reservation",
    );
    check(
      JSON.stringify(before) ===
        JSON.stringify(await immutableSnapshot(certificate)),
      "10C incompatible evidence preserves original SQL audit completed PDF and anchor",
    );
    // Separate faulty-provider classification from the untouched real chain.
    // Restore its validated view through the fenced worker action, not a new signature.
    expire(operation);
    const claimed = await backend.rpc<Job>("blockchain_claim", {
      p_operation: operation,
    });
    const observed = await env.registry.observe(
      dbHex(claimed.attempts[0].transaction_hash),
    );
    if (observed.kind !== "included") throw new Error("Expected real receipt");
    const validated = await env.registry.validateEvidence(
      { kind: "revoke", K: dbHex(claimed.anchor!.certificate_key) },
      observed.receipt,
      env.registry.signer,
    );
    await backend.rpc("blockchain_update_job", {
      p_operation: operation,
      p_token: claimed.operation.lease_token,
      p_generation: claimed.operation.generation,
      p_action: "receipt",
      p_detail: {
        hash: validated.hash,
        status: 1,
        block_number: validated.block.number.toString(),
        block_hash: validated.block.hash,
        transaction_index: validated.transactionIndex.toString(),
        validated_log_index: validated.logIndex!.toString(),
        head_number: observed.chain.head.number.toString(),
        head_hash: observed.chain.head.hash,
        confirmations:
          (observed.chain.head.number - validated.block.number + 1n).toString(),
        finality: "not_applicable",
      },
    });
    await backend.rpc("blockchain_update_job", {
      p_operation: operation,
      p_token: claimed.operation.lease_token,
      p_generation: claimed.operation.generation,
      p_action: "release",
    });
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
    const crashing = Object.create(env.registry) as EvmRegistry;
    crashing.prepare = () => {
      throw new Error("HARNESS_CRASH");
    };
    let crashed = false;
    try {
      await coordinate(backend, operation, () => crashing);
    } catch (e) {
      if (!(e instanceof Error) || e.message !== "HARNESS_CRASH") throw e;
      crashed = true;
    }
    const before = job(operation);
    check(
      crashed && before.attempts.length === 0 &&
        sql(
            `SELECT active_operation_id='${operation}'::uuid FROM certichain_private.blockchain_signer_nonces WHERE deployment_id='${binding.deployment_id}' AND signer=decode('${
              env.registry.signer.slice(2)
            }','hex')`,
          ) === "t",
      "10C process dies before signature persistence leaving only its legitimate nonce reservation",
    );
    expire(operation);
    env.restartWorker(operation);
    env.restartWorker(operation);
    check(
      job(operation).operation.state === "confirmed" &&
        job(operation).attempts.length === 1,
      "10C new process recovers unsigned reservation without nonce skip or duplicate operation",
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
    await configure(env.registry.signer, true);
    await reauthorize(operation);
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
    await configure(env.registry.signer, false);
    expire(operation);
    await env.run(operation);
    await env.run(operation);
    check(
      job(operation).operation.state === "failed" &&
        job(operation).attempts.length === 2 &&
        BigInt(job(operation).attempts[1].nonce) > BigInt(original.nonce),
      "10C second consumed revert retains both receipts and uses a later known nonce",
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
        recovered.attempts.length === 3 &&
        recovered.attempts[2].signer !== original.signer &&
        recovered.attempts[2].nonce === "0",
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
  {
    const admin = await f.user("replacement-revoke-admin");
    await f.rpc("set_institution_member", {
      p_institution: f.verified,
      p_member: admin.id,
      p_role: "admin",
    }, f.owner.token);
    const { operation, certificate } = await ready(admin);
    const before = await immutableSnapshot(certificate);
    // Controlled age only in the copied disposable DB function; restore its exact
    // definition in finally. Identity/fee/nonce/fencing guards remain enabled.
    const definition = sql(
      "SELECT pg_get_functiondef('public.blockchain_store_prepared(uuid,uuid,bigint,jsonb)'::regprocedure)",
    );
    const aged = definition.replace(
      "prev.created_at>clock_timestamp()-interval '5 minutes'",
      "prev.created_at>(clock_timestamp()+interval '301 seconds')-interval '5 minutes'",
    );
    if (aged === definition) throw new Error("Expected replacement age guard");
    await env.rpc.rpc("evm_setAutomine", [false]);
    try {
      await env.run(operation);
      const original = job(operation).attempts[0];
      check(
        (await env.registry.observe(dbHex(original.transaction_hash))).kind ===
          "pending",
        "10C real revoke waits in mempool without interpreting null receipt as abandonment",
      );
      await f.rpc("remove_institution_member", {
        p_institution: f.verified,
        p_member: admin.id,
      }, f.owner.token);
      check(
        await env.run(operation, false, { now: () => Date.now() + 301000 }) ===
            "authorization_denied" && job(operation).attempts.length === 1,
        "10C membership loss blocks replacement signature after five-minute threshold",
      );
      await env.run(operation); // Observe/retransmit existing bytes while blocked.
      await reauthorize(operation); // Current owner, audit; original decision untouched.
      sql(aged);
      for (let replacement = 1; replacement <= 3; replacement++) {
        check(
          await env.run(operation, false, {
            now: () => Date.now() + 301000,
          }) === "submitted",
          `10C real revoke replacement ${replacement} persists before broadcast`,
        );
      }
      const attempts = job(operation).attempts;
      check(
        attempts.length === 4 && attempts.every((t) =>
          t.nonce === original.nonce && t.signer === original.signer &&
          t.calldata === original.calldata
        ) &&
          sql(
              `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${operation}' AND replaces_attempt_id IS NOT NULL`,
            ) === "3",
        "10C replacement relation nonce calldata signer and single operation are durable",
      );
      check(
        attempts.slice(1).every((t, i) =>
          BigInt(t.max_fee_per_gas) * 100n >=
            BigInt(attempts[i].max_fee_per_gas) * 120n &&
          BigInt(t.max_priority_fee_per_gas) * 100n >=
            BigInt(attempts[i].max_priority_fee_per_gas) * 120n
        ),
        "10C revoke replacement fees respect both twenty-percent bounds",
      );
      await env.rpc.rpc("anvil_dropTransaction", [
        dbHex(attempts[3].transaction_hash),
      ]);
      await env.rpc.rpc("eth_sendRawTransaction", [
        dbHex(original.raw_signed_tx!),
      ]);
      await env.rpc.rpc("evm_mine");
      check(
        await env.run(operation) === "confirmed" &&
          job(operation).operation.canonical_attempt_id === original.id,
        "10C earlier revoke attempt wins after three replacements and is reconciled",
      );
      check(
        JSON.stringify(before) ===
          JSON.stringify(await immutableSnapshot(certificate)),
        "10C replacements preserve original decision actor reason date PDF completed and anchor",
      );
    } finally {
      sql(definition);
      await env.rpc.rpc("evm_setAutomine", [true]);
    }
  }
  sql(
    "UPDATE certichain_private.public_verification_budget SET used=0,window_started_at=clock_timestamp()",
  );
}
