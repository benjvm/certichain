import { sql } from "../scripts/local_supabase.mjs";
import {
  dbHex,
  type Job,
} from "../functions/_shared/blockchain/application/coordinator.ts";
import {
  bytes,
  digest,
} from "../functions/_shared/blockchain/application/commitment.ts";
import { calldata } from "../functions/_shared/blockchain/data/evm_registry.ts";
import type { Hex } from "../functions/_shared/blockchain/domain/registry.ts";
import type { phase9dEnvironment } from "./phase9d_environment.ts";

export async function phase10Checks(
  env: Awaited<ReturnType<typeof phase9dEnvironment>>,
  check: (v: unknown, label: string) => void,
) {
  const { f, backend } = env;
  const privateReason = "Synthetic private revocation reason — never public";
  const post = (endpoint: string, token: string, body: unknown) =>
    f.json(`/functions/v1/${endpoint}`, token, body);
  const issue = async () => {
    const r = await f.issue(f.owner, {
      institution_id: f.verified,
      holder_id: f.holder.id,
      idempotency_key: crypto.randomUUID(),
      title: "Synthetic phase10",
    });
    check(r.status === 201, "10 real publication");
    return r.data.certificate_id as string;
  };
  const query = async (id: string) => {
    const code = sql(
      `SELECT credential_code FROM public.certificates WHERE id='${id}'`,
    );
    const r = await fetch(
      `${f.local.API_URL}/functions/v1/verify-certificate-v3`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ credential_code: code }),
        signal: AbortSignal.timeout(15000),
      },
    );
    const data = await r.json();
    check(r.status === 200, "10 v3 HTTP available");
    check(
      !JSON.stringify(data).includes(privateReason) &&
        !JSON.stringify(data).includes("reason") &&
        !JSON.stringify(data).includes(f.local.SERVICE_ROLE_KEY),
      "10 public output contains no reason or service secret",
    );
    return data;
  };
  const revoke = (
    id: string,
    key = crypto.randomUUID(),
    actor = f.owner,
    reason = privateReason,
  ) =>
    post("revoke-certificate", actor.token, {
      certificate_id: id,
      idempotency_key: key,
      reason,
    });
  const syncId = (id: string) =>
    sql(
      `SELECT o.id FROM certichain_private.blockchain_operations o JOIN certichain_private.certificate_anchors a ON a.id=o.anchor_id WHERE a.certificate_id='${id}' AND o.kind='revoke'`,
    );
  const anchor = async (id: string) => {
    const r = await post("anchor-certificate", f.owner.token, {
      certificate_id: id,
      idempotency_key: crypto.randomUUID(),
    });
    check(r.response.status === 202, "10 explicit anchor requested");
    return r.data.operation_id as string;
  };
  const admin = await f.user("revocation-admin");
  await f.rpc("set_institution_member", {
    p_institution: f.verified,
    p_member: admin.id,
    p_role: "admin",
  }, f.owner.token);
  const issuer = await f.user("revocation-issuer");
  await f.rpc("set_institution_member", {
    p_institution: f.verified,
    p_member: issuer.id,
    p_role: "issuer",
  }, f.owner.token);
  const off = await issue();
  for (const actor of [f.holder, f.outsider, f.platform, issuer]) {
    check(
      (await revoke(off, crypto.randomUUID(), actor)).response.status === 404,
      "10 holder outsider platform issuer uniformly denied",
    );
    check(
      (await post("revocation-progress", actor.token, { certificate_id: off }))
        .response.status === 404,
      "10 unauthorized audit denied",
    );
  }
  check(
    (await revoke(crypto.randomUUID(), crypto.randomUUID(), f.owner)).response
      .status === 404,
    "10 missing matches foreign denial",
  );
  check(
    (await post("revoke-certificate", f.local.ANON_KEY, {
      certificate_id: off,
      idempotency_key: crypto.randomUUID(),
      reason: privateReason,
    })).response.status === 401,
    "10 anonymous JWT denied",
  );
  const key = crypto.randomUUID();
  const concurrent = await Promise.all([
    revoke(off, key),
    revoke(off, key),
    revoke(off, crypto.randomUUID(), admin),
  ]);
  check(
    concurrent.every((r) => [200, 202].includes(r.response.status)) &&
      concurrent.filter((r) => r.response.status === 202).length === 1,
    "10 concurrent requests create one logical revocation",
  );
  const decision = concurrent[0].data;
  check(
    concurrent.every((r) =>
      r.data.request_id === decision.request_id &&
      r.data.revoked_at === decision.revoked_at
    ),
    "10 same/different keys preserve first date and request",
  );
  check(
    (await revoke(off, key)).data.request_id === decision.request_id,
    "10 same key recovers same request",
  );
  check(
    (await revoke(off, key, f.owner, "conflicting reason")).response.status ===
      409,
    "10 canonical key reason conflict",
  );
  const another = await issue();
  check(
    (await revoke(another, key)).response.status === 409,
    "10 same institutional key certificate conflict",
  );
  const offView = await query(off);
  check(
    offView.registry.result === "revoked" &&
      offView.revocation.state === "not_applicable" &&
      offView.blockchain.state === "off_chain_only",
    "10 SQL-only revocation creates no EVM evidence",
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.certificate_anchors WHERE certificate_id='${off}'`,
    ) === "0",
    "10 no salts/anchors for off-chain decision",
  );
  const unsigned = await issue(), unsignedOp = await anchor(unsigned);
  await revoke(unsigned);
  check(
    sql(
          `SELECT state FROM certichain_private.blockchain_operations WHERE id='${unsignedOp}'`,
        ) === "cancelled" && await env.run(unsignedOp) === "busy",
    "10 unsigned issue cancelled and cannot claim/sign",
  );
  check(
    syncId(unsigned) === "",
    "10 cancellation retains audit without EVM revoke",
  );
  const cert = await issue(), issueOp = await anchor(cert);
  await env.run(issueOp);
  await env.run(issueOp);
  const before = await query(cert),
    originalIssue = before.blockchain.transaction_hash;
  const snapshot = await env.rpc.rpc<Hex>("evm_snapshot");
  env.pause();
  try {
    const requestKey = crypto.randomUUID();
    const decisions = await Promise.all([
      revoke(cert, requestKey, admin),
      revoke(cert, requestKey, admin),
      revoke(cert, crypto.randomUUID(), admin),
    ]);
    check(
      decisions.every((r) => [200, 202].includes(r.response.status)) &&
        decisions.filter((r) => r.response.status === 202).length === 1,
      "10 SQL acceptance independent of paused RPC/worker",
    );
    check(
      decisions.every((r) =>
        r.data.request_id === decisions[0].data.request_id &&
        r.data.revoked_at === decisions[0].data.revoked_at
      ) &&
        sql(
            `SELECT count(*) FROM certichain_private.blockchain_operations o JOIN certichain_private.certificate_anchors a ON a.id=o.anchor_id WHERE a.certificate_id='${cert}' AND o.kind='revoke'`,
          ) === "1",
      "10B concurrent signed-anchor requests create one decision and one EVM revoke obligation",
    );
    const offline = await query(cert);
    check(
      offline.registry.result === "revoked" &&
        offline.revocation.state === "unavailable",
      "10 RPC outage never masks SQL revocation",
    );
  } finally {
    env.unpause();
  }
  const pending = await query(cert);
  check(
    pending.registry.result === "revoked" &&
      pending.revocation.state === "pending" &&
      pending.blockchain.state === "divergence",
    "10 expected synchronization delay distinguished from active EVM",
  );
  const rev = syncId(cert);
  // Suspension only removes canIssue. Revoke uses canRevoke and the stored I.
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "suspended",
  }, f.platform.token);
  const binding = JSON.parse(
    sql(
      `SELECT row_to_json(b) FROM certichain_private.blockchain_issuers b WHERE institution_id='${f.verified}'`,
    ),
  );
  const config = {
    kind: "set_issuer" as const,
    I: dbHex(binding.issuer_id),
    signer: dbHex(binding.signer),
    canIssue: false,
    canRevoke: true,
  };
  const cfg = await backend.rpc<string>("blockchain_configure_issuer", {
    p_actor: f.platform.id,
    p_deployment: binding.deployment_id,
    p_institution: f.verified,
    p_i: config.I,
    p_signer: config.signer,
    p_issue: false,
    p_revoke: true,
    p_key: crypto.randomUUID(),
    p_payload: await digest(bytes(calldata(config))),
  });
  await env.run(cfg, true);
  await env.run(cfg, true);
  await f.rpc("remove_institution_member", {
    p_institution: f.verified,
    p_member: admin.id,
  }, f.owner.token);
  check(
    await env.run(rev) === "authorization_denied" &&
      sql(
          `SELECT state FROM certichain_private.blockchain_operations WHERE id='${rev}'`,
        ) === "blocked",
    "10 removed author cannot sign revocation",
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${rev}'`,
    ) === "0",
    "10 no signature after member removal",
  );
  check(
    (await post("revocation-progress", admin.token, { certificate_id: cert }))
      .response.status === 404,
    "10 removed admin cannot read audit",
  );
  const beforeReauthorization = sql(
    `SELECT row_to_json(o) FROM certichain_private.blockchain_operations o WHERE id='${rev}'`,
  );
  for (const actor of [admin, issuer, f.holder, f.outsider, f.platform]) {
    const denied = await post("reauthorize-revocation", actor.token, {
      operation_id: rev,
    });
    check(
      denied.response.status === 404 &&
        denied.data.error === "revocation_unavailable",
      "10B blocked revoke reauthorization denied without current membership role",
    );
  }
  check(
    sql(
      `SELECT row_to_json(o) FROM certichain_private.blockchain_operations o WHERE id='${rev}'`,
    ) === beforeReauthorization,
    "10B denied reauthorization preserves lease nonce state and audit",
  );
  check(
    (await post("reauthorize-revocation", f.owner.token, {
      operation_id: issueOp,
    })).response.status === 404,
    "10B issue operation cannot use revoke reauthorization",
  );
  const decisionBeforeReauthorization = sql(
    `SELECT row_to_json(r) FROM certichain_private.certificate_revocations r WHERE certificate_id='${cert}'`,
  );
  const rea = await post("reauthorize-revocation", f.owner.token, {
    operation_id: rev,
  });
  check(
    rea.response.status === 200 && rea.data.request_id !== null,
    "10 suspended owner explicitly reauthorizes blocked revocation",
  );
  check(
    sql(
      `SELECT row_to_json(r) FROM certichain_private.certificate_revocations r WHERE certificate_id='${cert}'`,
    ) === decisionBeforeReauthorization,
    "10B reauthorization preserves original decision actor reason date and request",
  );
  check(
    (await post("reauthorize-revocation", f.owner.token, { operation_id: rev }))
      .response.status === 409,
    "10B requested revoke cannot reauthorize outside allowed states",
  );
  check(
    sql(
      `SELECT jsonb_array_length(authorizations) FROM certichain_private.blockchain_operations WHERE id='${rev}'`,
    ) === "1",
    "10 reauthorization audit appended",
  );
  await env.run(rev);
  await env.run(rev);
  const done = await query(cert);
  check(
    done.registry.result === "revoked" &&
      done.revocation.state === "confirmed" &&
      done.revocation.evidence.finality === "not_applicable",
    "10 canIssue false canRevoke true actual confirmed revocation",
  );
  check(
    done.blockchain.transaction_hash === originalIssue &&
      done.revocation.evidence.transaction_hash !== originalIssue,
    "10 issue and revoke evidence remain separate",
  );
  const sqlDate = sql(
    `SELECT revoked_at FROM public.certificates WHERE id='${cert}'`,
  );
  await env.rpc.rpc("evm_revert", [snapshot]);
  check(
    (await query(cert)).revocation.state === "reorged",
    "10 real revoke reorg visible",
  );
  // Configuration too was reverted; observe it again before preparing any new bytes.
  await env.run(cfg, true);
  await env.run(cfg, true);
  await env.run(rev);
  await env.run(rev);
  check(
    (await query(cert)).revocation.state === "confirmed" &&
      sql(`SELECT revoked_at FROM public.certificates WHERE id='${cert}'`) ===
        sqlDate,
    "10 revoke reorg recovered without reactivating SQL",
  );
  check(
    (await post("certificate-pdf", f.holder.token, { certificate_id: cert }))
      .response.status === 200,
    "10 holder still obtains authorized revoked PDF",
  );
  check(
    (await post("certificate-opening", f.holder.token, {
      certificate_id: cert,
    })).response.status === 200,
    "10 holder opening preserved during suspension/revocation",
  );
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "pending",
  }, f.platform.token);
  check(
    (await revoke(another)).response.status === 404,
    "10 pending owner cannot revoke",
  );
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "rejected",
  }, f.platform.token);
  check(
    (await revoke(another)).response.status === 404,
    "10 rejected owner cannot revoke",
  );
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "pending",
  }, f.platform.token);
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "verified",
  }, f.platform.token);
  const restore = { ...config, canIssue: true };
  const cfg2 = await backend.rpc<string>("blockchain_configure_issuer", {
    p_actor: f.platform.id,
    p_deployment: binding.deployment_id,
    p_institution: f.verified,
    p_i: restore.I,
    p_signer: restore.signer,
    p_issue: true,
    p_revoke: true,
    p_key: crypto.randomUUID(),
    p_payload: await digest(bytes(calldata(restore))),
  });
  await env.run(cfg2, true);
  await env.run(cfg2, true);
  const late = await issue(), lateIssue = await anchor(late);
  const beforeLate = await env.rpc.rpc<Hex>("evm_snapshot");
  try {
    await env.run(lateIssue, false, {
      barrier: (point) => {
        if (point === "stored") throw new Error("HARNESS_CRASH");
        return Promise.resolve();
      },
    });
  } catch (e) {
    if (!(e instanceof Error) || e.message !== "HARNESS_CRASH") throw e;
  }
  const oldJob = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${lateIssue}')`),
  ) as Job;
  check(
    oldJob.attempts.length === 1,
    "10 crash after durable issue signature before broadcast",
  );
  await revoke(late);
  const lateRevoke = syncId(late);
  check(
    await env.run(lateRevoke) === "waiting_issue",
    "10 signed issue null is unresolved, never clean",
  );
  sql(
    `UPDATE certichain_private.blockchain_operations SET lease_until=clock_timestamp()-interval '1 second' WHERE id='${lateIssue}'`,
  );
  await env.run(lateIssue);
  await env.run(lateIssue);
  check(
    sql(
      `SELECT state FROM certichain_private.blockchain_operations WHERE id='${lateIssue}'`,
    ) === "confirmed",
    "10 late issue reconciles instead of permanent divergence",
  );
  await env.run(lateRevoke);
  await env.run(lateRevoke);
  check(
    (await query(late)).revocation.state === "confirmed",
    "10 late signed issue compensated with same K/I/C",
  );
  await env.rpc.rpc("evm_revert", [beforeLate]);
  await env.run(lateIssue);
  await env.run(lateIssue);
  await env.run(lateRevoke);
  await env.run(lateRevoke);
  check(
    (await query(late)).registry.result === "revoked" &&
      (await query(late)).revocation.state === "confirmed",
    "10 issue and revoke reorg recover using original signed bytes",
  );
  check(
    sql(
      `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id IN ('${lateIssue}','${lateRevoke}')`,
    ) === "2",
    "10 recovered operations do not duplicate transactions",
  );
  // Historical active without completed remains publicly ineligible, but revocable.
  check(
    (await revoke(f.legacy)).response.status === 202,
    "10 historical active revocable without backfill",
  );
  check(
    (await query(f.legacy)).registry.result === "not_found",
    "10 revoking legacy does not relax public eligibility",
  );
  sql(
    "UPDATE certichain_private.public_verification_budget SET used=0,window_started_at=clock_timestamp()",
  );
}
