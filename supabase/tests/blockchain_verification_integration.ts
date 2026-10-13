import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { phase9dEnvironment } from "./phase9d_environment.ts";
import { sql } from "../scripts/local_supabase.mjs";
import {
  commitment,
  digest,
} from "../functions/_shared/blockchain/application/commitment.ts";
import type { Hex } from "../functions/_shared/blockchain/domain/registry.ts";

let checks = 0;
function check(v: unknown, label: string) {
  if (!v) throw new Error(label);
  checks++;
  console.log(JSON.stringify({ case: label, result: "PASS" }));
}
const environment = await phase9dEnvironment();
try {
  const { f } = environment;
  const publicQuery = async (
    code: string,
    endpoint = "verify-certificate-v2",
  ) => {
    const r = await fetch(`${f.local.API_URL}/functions/v1/${endpoint}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ credential_code: code }),
      signal: AbortSignal.timeout(15000),
    });
    return { status: r.status, headers: r.headers, data: await r.json() };
  };
  const issued = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: crypto.randomUUID(),
    title: "Synthetic 9D HTTP",
  });
  check(issued.status === 201, "real publication before separate anchoring");
  const certificate = issued.data.certificate_id as string;
  const code = sql(
    `SELECT credential_code FROM public.certificates WHERE id='${certificate}'`,
  );
  check(
    (await publicQuery(code)).data.blockchain.state === "off_chain_only",
    "public off-chain eligible registry without anchor",
  );
  const request = await f.json(
    "/functions/v1/anchor-certificate",
    f.owner.token,
    { certificate_id: certificate, idempotency_key: crypto.randomUUID() },
  );
  check(
    request.response.status === 202 && request.data.status === "requested",
    "real anchor request is not confirmation",
  );
  check(
    (await publicQuery(code)).data.blockchain.state === "pending",
    "live public pending while worker not run",
  );
  const operation = request.data.operation_id as string;
  check(
    (await f.json("/functions/v1/anchor-progress", f.holder.token, {
      operation_id: operation,
    })).response.status === 403,
    "holder cannot open institutional progress",
  );
  const beforeIssue = await environment.rpc.rpc<Hex>("evm_snapshot");
  await environment.run(operation);
  await environment.run(operation);
  const verified = await publicQuery(code);
  check(
    verified.status === 200 && verified.data.registry.result === "valid" &&
      verified.data.blockchain.state === "confirmed" &&
      verified.data.blockchain.finality === "not_applicable" &&
      verified.data.blockchain.source === "backend_rpc",
    "live EVM receipt event state and public confirmation without signer",
  );
  check(
    verified.headers.has("server-timing"),
    "total latency exposed without sensitive logs",
  );
  const previousDate = verified.data.blockchain.last_evidence.checked_at;
  const opened = await f.json(
    "/functions/v1/certificate-opening",
    f.holder.token,
    { certificate_id: certificate },
  );
  check(
    opened.response.status === 200 &&
      opened.response.headers.get("cache-control") === "no-store",
    "real holder opening Auth and no-store",
  );
  const o = opened.data;
  check(
    (await f.json("/functions/v1/certificate-opening", f.issuer.token, {
      certificate_id: certificate,
    })).response.status === 200,
    "current issuer membership permits opening",
  );
  await f.rpc("set_institution_member", {
    p_institution: f.verified,
    p_member: f.issuer.id,
    p_role: "admin",
  }, f.owner.token);
  check(
    (await f.json("/functions/v1/certificate-opening", f.issuer.token, {
      certificate_id: certificate,
    })).response.status === 200,
    "current admin membership permits opening",
  );
  await f.rpc("remove_institution_member", {
    p_institution: f.verified,
    p_member: f.issuer.id,
  }, f.owner.token);
  check(
    (await f.json("/functions/v1/certificate-opening", f.issuer.token, {
      certificate_id: certificate,
    })).response.status === 404,
    "removed issuer cannot obtain another opening",
  );
  const result = await commitment(
    code,
    o.issuer_id as Hex,
    o.document_sha256 as Hex,
    o.salt as Hex,
  );
  check(
    result.K === verified.data.blockchain.certificate_key &&
      result.C === verified.data.blockchain.commitment,
    "opening recalculates exact K/C without disclosure",
  );
  check(
    await digest(
      await environment.backend.pdf(`${f.verified}/${certificate}.pdf`),
    ) === o.document_sha256,
    "opening H matches exact private stored PDF",
  );
  for (const actor of [f.outsider, f.platform]) {
    check(
      (await f.json("/functions/v1/certificate-opening", actor.token, {
        certificate_id: certificate,
      })).response.status === 404,
      "real foreign or platform opening denied uniformly",
    );
  }
  const absent = await publicQuery(crypto.randomUUID());
  check(
    absent.status === 200 && absent.data.registry.result === "not_found" &&
      absent.data.blockchain === null,
    "uniform public absence",
  );
  const legacyCode = sql(
    `SELECT credential_code FROM public.certificates WHERE id='${f.legacy}'`,
  );
  check(
    (await publicQuery(legacyCode)).data.blockchain === null,
    "legacy publication has no anchor disclosure",
  );
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "suspended",
  }, f.platform.token);
  check(
    (await f.json("/functions/v1/certificate-opening", f.holder.token, {
      certificate_id: certificate,
    })).response.status === 200,
    "real holder retains opening after suspension",
  );
  check(
    (await f.json("/functions/v1/certificate-opening", f.owner.token, {
      certificate_id: certificate,
    })).response.status === 404,
    "real suspended member denied opening",
  );
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "pending",
  }, f.platform.token);
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "verified",
  }, f.platform.token);
  environment.pause();
  try {
    const unavailable = await publicQuery(code);
    check(
      unavailable.status === 200 &&
        unavailable.data.registry.result === "valid" &&
        unavailable.data.blockchain.state === "unavailable" &&
        unavailable.data.blockchain.last_evidence.checked_at === previousDate,
      "actual RPC outage retains original previous evidence date",
    );
  } finally {
    environment.unpause();
  }
  check(
    (await publicQuery(code, "verify-certificate")).data.schema_version === "1",
    "API v1 preserved on anchored certificate",
  );
  // Every public POST, including invalid v2, shares the singleton budget. These
  // fixture-only changes are sequential and the whole stack is disposable.
  sql(
    "UPDATE certichain_private.public_verification_budget SET used=59,window_started_at=clock_timestamp();",
  );
  check(
    (await publicQuery("invalid")).status === 400,
    "invalid v2 consumes shared remaining slot",
  );
  const limited = await publicQuery(code, "verify-certificate");
  check(
    limited.status === 429 && Number(limited.headers.get("retry-after")) > 0,
    "v1 shares v2 exhaustion and Retry-After",
  );
  const comparison = await fetch(
    `${f.local.API_URL}/functions/v1/compare-certificate-hash`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        credential_code: code,
        document_sha256: "0".repeat(64),
      }),
    },
  );
  check(comparison.status === 429, "comparison v1 shares same budget");
  await comparison.body?.cancel();
  sql(
    "UPDATE certichain_private.public_verification_budget SET used=0,window_started_at=clock_timestamp();",
  );
  await environment.rpc.rpc("evm_revert", [beforeIssue]);
  const reorged = await publicQuery(code);
  check(
    reorged.data.blockchain.state === "reorged" &&
      reorged.data.blockchain.last_evidence.checked_at === previousDate,
    "real orphaned block invalidates current evidence and retains earlier date",
  );
  for (let pass = 0; pass < 4; pass++) {
    const state = await environment.run(operation);
    if (state === "confirmed") break;
  }
  const recovered = await publicQuery(code);
  check(
    recovered.data.blockchain.state === "confirmed" &&
      recovered.data.blockchain.commitment ===
        verified.data.blockchain.commitment,
    "worker reinclusion conserves original commitment and restores canonical evidence",
  );
  if (Deno.env.get("CERTICHAIN_9D_BROWSER") === "1") {
    const module = await import(
      pathToFileURL(
        resolve(
          Deno.env.get("CERTICHAIN_SOURCE_ROOT") ?? Deno.cwd(),
          "mobile/tool/blockchain_verification_browser.mjs",
        ),
      ).href
    );
    const safeId = (id: string) => {
      if (!/^[0-9a-f-]{36}$/.test(id)) throw new Error("Invalid owned ID");
      return id;
    };
    await module.runBrowserJourney({
      ...environment,
      lookupCertificate: (title: string) => {
        if (title !== "9D Browser Certificate") {
          throw new Error("Unknown synthetic title");
        }
        return sql(
          `SELECT id FROM public.certificates WHERE institution_id='${f.verified}' AND title='9D Browser Certificate'`,
        );
      },
      lookupOperation: (id: string) =>
        sql(
          `SELECT o.id FROM certichain_private.blockchain_operations o JOIN certichain_private.certificate_anchors a ON a.id=o.anchor_id WHERE a.certificate_id='${
            safeId(id)
          }' AND o.kind='issue'`,
        ),
      lookupCode: (id: string) =>
        sql(
          `SELECT credential_code FROM public.certificates WHERE id='${
            safeId(id)
          }'`,
        ),
    });
  }
  // Deliberate external EVM revoke fixture. This is not product phase 10.
  const K = verified.data.blockchain.certificate_key as Hex;
  const fees = await environment.registry.fees({ kind: "revoke", K });
  const nonce = await environment.registry.nonce();
  const tx = await environment.registry.prepare(
    { kind: "revoke", K },
    nonce.latest,
    fees,
  );
  await environment.registry.broadcast(tx);
  const divergence = await publicQuery(code);
  check(
    divergence.data.registry.result === "valid" &&
      divergence.data.blockchain.state === "divergence" &&
      divergence.data.blockchain.revoked === true,
    "external EVM revocation conflicts with active SQL registry",
  );
  console.log(
    JSON.stringify({
      suite: "phase9d-real",
      checks,
      camera: "NOT_RUN",
      camera_reason:
        "Omitidas por instrucción del usuario; no hay cámara física disponible",
    }),
  );
} finally {
  environment.close();
  console.log(
    JSON.stringify({ cleanup: "owned Anvil network and Edge runtime stopped" }),
  );
}
