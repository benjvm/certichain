// 10B only. Real Auth/Edge/SQL; transport barriers belong solely to this harness.
import {
  gatewayObservation,
  gatewayPolicy,
  privateRoutes,
} from "./phase10_gateway_policy.ts";
import { createServer } from "node:http";
import { once } from "node:events";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { sql } from "../scripts/local_supabase.mjs";
import { digest } from "../functions/_shared/blockchain/application/commitment.ts";
import { BlockchainBackend } from "../functions/_shared/blockchain/data/backend.ts";
import type { phase9dEnvironment } from "./phase9d_environment.ts";

type AuthFixture = Pick<Awaited<ReturnType<typeof phase9dEnvironment>>, "f">;

function expiredFixtureToken({ f }: AuthFixture): string {
  // Reuse the Node fixture in its pinned runtime. All local signing material
  // stays inside private pipes on the trusted harness host, never arguments/logs.
  const script = `import { expiredToken } from ${
    JSON.stringify(new URL("./issuance_hardening.mjs", import.meta.url).href)
  };
    let input = ''; for await (const chunk of process.stdin) input += chunk;
    const data = JSON.parse(input); process.stdout.write(expiredToken(data.local, data.token));`;
  const jwt = spawnSync("node", ["--input-type=module", "-e", script], {
    input: JSON.stringify({ local: f.local, token: f.owner.token }),
    encoding: "utf8",
    windowsHide: true,
    timeout: 15000,
  });
  if (jwt.status !== 0 || jwt.stdout.split(".").length !== 3) {
    throw new Error("Owned JWT fixture failed");
  }
  return jwt.stdout;
}

// A gateway response precedes the handler: never attribute the handler's CORS
// headers to it. Report all three routes before evaluating this acceptance gate.
export async function phase10GatewayCache(
  env: AuthFixture,
) {
  const config = readFileSync("supabase/config.toml", "utf8");
  const expired = expiredFixtureToken(env);
  const observations = [];
  async function probe(
    endpoint: string,
    scenario: string,
    token: string | null,
    body: unknown,
    expectedStatus: number,
  ) {
    const headers: Record<string, string> = {
      "content-type": "application/json",
    };
    if (token !== null) headers.authorization = `Bearer ${token}`;
    const response = await fetch(
      `${env.f.local.API_URL}/functions/v1/${endpoint}`,
      {
        method: "POST",
        headers,
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(15000),
      },
    );
    const observation = await gatewayObservation(
      endpoint,
      scenario,
      response,
      env.f.legacy,
    );
    if (observation.expected_status !== expectedStatus) {
      throw new Error("Unexpected gateway test scenario");
    }
    return observation;
  }
  for (
    const endpoint of privateRoutes
  ) {
    const section = config.match(
      new RegExp(`\\[functions\\.${endpoint}\\]([^]*?)(?=\\n\\[|$)`),
    )?.[1];
    if (!section || !/^verify_jwt\s*=\s*true\s*$/m.test(section)) {
      throw new Error("Private gateway JWT verification must remain enabled");
    }
    for (
      const [scenario, token, status] of [
        ["no_token", null, 401],
        ["invalid_token", "invalid", 401],
        ["expired_token", expired, 401],
        ["valid_session_invalid_input", env.f.owner.token, 400],
        ["anonymous_api_jwt", env.f.local.ANON_KEY, 401],
      ] as const
    ) observations.push(await probe(endpoint, scenario, token, {}, status));
  }
  observations.push(
    await probe(
      "revocation-progress",
      "valid_owner_authorized",
      env.f.owner.token,
      { certificate_id: env.f.legacy },
      200,
    ),
  );
  observations.push(
    await probe(
      "revocation-progress",
      "valid_foreign_denied",
      env.f.outsider.token,
      { certificate_id: env.f.legacy },
      404,
    ),
  );
  return gatewayPolicy(observations);
}

export async function phase10Backend(
  env: Awaited<ReturnType<typeof phase9dEnvironment>>,
  check: (v: unknown, label: string) => void,
) {
  const { f } = env;
  // coordinate() owns a mutable deadline on env.backend. HTTP acceptance must
  // not reuse a worker deadline across the response-loss barrier.
  const backend = new BlockchainBackend(
    f.local.API_URL,
    f.local.SERVICE_ROLE_KEY,
  );
  const published = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: crypto.randomUUID(),
    title: "10B transport recovery",
  });
  check(published.status === 201, "10B real publication");
  const cid = published.data.certificate_id as string;
  const key = crypto.randomUUID();
  const input = {
    certificate_id: cid.toUpperCase(),
    idempotency_key: key.toUpperCase(),
    reason: " \tRevisio\u0301n\r\nprivada\r🙂\t ",
  };
  const headers = {
    apikey: f.local.ANON_KEY,
    authorization: `Bearer ${f.owner.token}`,
    "content-type": "application/json",
  };
  const post = (endpoint: string, body: unknown, token = f.owner.token) =>
    f.json(`/functions/v1/${endpoint}`, token, body);
  const snapshot = () =>
    sql(`SELECT jsonb_build_object(
    'certificate',to_jsonb(c),'publication',to_jsonb(p),
    'decisions',(SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]') FROM certichain_private.certificate_revocations r WHERE r.certificate_id=c.id),
    'keys',(SELECT coalesce(jsonb_agg(to_jsonb(k) ORDER BY k.idempotency_key),'[]') FROM certichain_private.certificate_revocation_keys k WHERE k.certificate_id=c.id),
    'anchors',(SELECT coalesce(jsonb_agg(to_jsonb(a)),'[]') FROM certichain_private.certificate_anchors a WHERE a.certificate_id=c.id),
    'operations',(SELECT coalesce(jsonb_agg(to_jsonb(o)),'[]') FROM certichain_private.blockchain_operations o JOIN certichain_private.certificate_anchors a ON a.id=o.anchor_id WHERE a.certificate_id=c.id))
    FROM public.certificates c JOIN public.certificate_issuance_operations p ON p.id=c.issuance_operation_id WHERE c.id='${cid}'`);
  const before = JSON.parse(snapshot());
  const pdfBefore = await backend.pdf(`${f.verified}/${cid}.pdf`);
  // Forward to the real Edge, withhold every response byte, then break the
  // consumer socket only after an independent SQL connection confirms commit.
  const reached = Promise.withResolvers<void>();
  const release = Promise.withResolvers<void>();
  let upstreamStatus = 0;
  const proxy = createServer(async (request, response) => {
    try {
      for await (const _chunk of request) {
        /* drain bounded synthetic input */
      }
      const upstream = await fetch(
        `${f.local.API_URL}/functions/v1/revoke-certificate`,
        {
          method: "POST",
          headers,
          body: JSON.stringify(input),
          signal: AbortSignal.timeout(30000),
        },
      );
      upstreamStatus = upstream.status;
      await upstream.arrayBuffer();
      reached.resolve();
      await release.promise;
      response.destroy();
    } catch {
      reached.reject(new Error("10B upstream barrier failed"));
      response.destroy();
    }
  });
  proxy.listen(0, "127.0.0.1");
  await once(proxy, "listening");
  const address = proxy.address();
  if (!address || typeof address === "string") {
    throw new Error("Owned transport unavailable");
  }
  let consumerReceived = false;
  const consumerAbort = new AbortController();
  const consumer = fetch(`http://127.0.0.1:${address.port}`, {
    method: "POST",
    body: JSON.stringify(input),
    signal: AbortSignal.any([consumerAbort.signal, AbortSignal.timeout(30000)]),
  }).then(async (r) => {
    consumerReceived = true;
    await r.arrayBuffer();
    return false;
  }, () => true);
  let committed = JSON.parse("{}");
  let committedSnapshot = "";
  try {
    await reached.promise;
    committedSnapshot = snapshot();
    committed = JSON.parse(committedSnapshot);
    check(
      upstreamStatus === 202 && !consumerReceived &&
        committed.decisions.length === 1 && committed.keys.length === 1,
      "10B commit confirmed independently while consumer has no response",
    );
    check(
      committed.decisions[0].reason === "Revisión\nprivada\n🙂",
      "10B HTTP canonical Unicode equals SQL stored reason",
    );
    release.resolve();
    consumerAbort.abort();
    check(
      await consumer && consumerAbort.signal.aborted && !consumerReceived,
      "10B actual transport interrupted after commit before consumer obtains result",
    );
  } finally {
    release.resolve();
    consumerAbort.abort();
    proxy.closeAllConnections();
    await new Promise<void>((resolve) => proxy.close(() => resolve()));
    await consumer;
  }
  const recovered = await post("revoke-certificate", input);
  check(
    recovered.response.status === 200 &&
      recovered.data.request_id === committed.decisions[0].id &&
      recovered.data.revoked_at === committed.certificate.revoked_at &&
      recovered.data.reason === committed.decisions[0].reason,
    "10B lost transport retry preserves request date and reason",
  );
  check(
    snapshot() === committedSnapshot,
    "10B retry changes no SQL decision alias or operation",
  );
  // Compare JSON values via SQL's canonical serialization, without storing PII.
  const stable = snapshot();
  for (let i = 0; i < 2; i++) {
    const p = await post("revocation-progress", { certificate_id: cid });
    check(
      p.response.status === 200 &&
        JSON.stringify(p.data) === JSON.stringify(recovered.data),
      "10B progress recovers original result",
    );
  }
  check(
    snapshot() === stable,
    "10B progress has no decision alias authorization anchor or operation mutations",
  );
  const alias = crypto.randomUUID();
  const a = await post("revoke-certificate", {
    ...input,
    idempotency_key: alias,
    reason: "Different alias reason",
  });
  check(
    a.response.status === 200 &&
      JSON.stringify(a.data) === JSON.stringify(recovered.data),
    "10B alias returns first immutable decision",
  );
  check(
    (await post("revoke-certificate", {
      ...input,
      idempotency_key: alias,
      reason: "changed",
    })).response.status === 409,
    "10B alias fingerprint persisted and conflicts",
  );
  const final = JSON.parse(snapshot());
  check(
    JSON.stringify(final.decisions) === JSON.stringify(committed.decisions) &&
      final.keys.length === 2 && final.operations.length === 0 &&
      final.anchors.length === 0,
    "10B retries aliases create no second decision or EVM operation",
  );
  check(
    JSON.stringify(before.publication) === JSON.stringify(final.publication) &&
      final.publication.status === "completed" &&
      before.certificate.credential_code ===
        final.certificate.credential_code &&
      await digest(pdfBefore) ===
        await digest(await backend.pdf(`${f.verified}/${cid}.pdf`)),
    "10B completed publication code and exact private PDF preserved",
  );
  for (
    const reason of [input.reason, "🙂".repeat(500), "\u00a0", "a\tb\r\nc\rd"]
  ) {
    const normalizationKey = reason === input.reason
      ? key
      : crypto.randomUUID();
    const r = await post("revoke-certificate", {
      ...input,
      idempotency_key: normalizationKey,
      reason,
    });
    const direct = await backend.rpc<Record<string, unknown>>(
      "request_certificate_revocation",
      {
        p_actor: f.owner.id,
        p_certificate: cid,
        p_key: normalizationKey,
        p_reason: reason,
      },
    );
    check(
      r.response.status === 200 && direct.created === false &&
        direct.request_id === recovered.data.request_id &&
        direct.reason === recovered.data.reason,
      "10B HTTP and direct SQL share canonical fingerprint including 500 Unicode points",
    );
  }

  const endpoints = [
    ["revoke-certificate", input],
    ["revocation-progress", { certificate_id: cid }],
    ["reauthorize-revocation", { operation_id: crypto.randomUUID() }],
  ] as const;
  const expired = expiredFixtureToken(env);
  check(
    expired.split(".").length === 3,
    "10B existing Node fixture verifies original Auth signature before expiring JWT",
  );
  for (const [ep, body] of endpoints) {
    for (
      const token of [
        "invalid",
        f.local.ANON_KEY,
        expired,
      ]
    ) {
      const r = await post(ep, body, token);
      check(
        r.response.status === 401,
        `10B ${ep} invalid anonymous expired real JWT denied`,
      );
    }
    const text = JSON.stringify(body);
    const field = ep === "reauthorize-revocation"
      ? "operation_id"
      : "certificate_id";
    for (
      const [bad, status] of [
        [text.padEnd(8193, " "), 413],
        [new Uint8Array([0xff]), 400],
        [text.slice(0, -1) + ',"role":"owner"}', 400],
        [
          text.slice(0, -1) + `,"${field.replace("i", "\\u0069")}":"${cid}"}`,
          400,
        ],
      ] as const
    ) {
      const r = await fetch(`${f.local.API_URL}/functions/v1/${ep}`, {
        method: "POST",
        headers,
        body: bad,
      });
      check(
        r.status === status && r.headers.get("cache-control") === "no-store",
        `10B ${ep} real Edge bounded closed UTF8 duplicate input`,
      );
      await r.arrayBuffer();
    }
  }
  const actor = await f.user("10b-current-permission");
  await f.rpc("set_institution_member", {
    p_institution: f.verified,
    p_member: actor.id,
    p_role: "admin",
  }, f.owner.token);
  check(
    (await post("revocation-progress", { certificate_id: cid }, actor.token))
      .response.status === 200,
    "10B current admin reads decision",
  );
  for (
    const column of [
      "is_anonymous=true",
      "deleted_at=clock_timestamp()",
      "banned_until=clock_timestamp()+interval '1 day'",
    ]
  ) {
    sql(`UPDATE auth.users SET ${column} WHERE id='${actor.id}'`);
    for (const [ep, body] of endpoints) {
      const r = await post(ep, body, actor.token);
      check(
        [401, 404].includes(r.response.status),
        `10B ${ep} anonymous deleted banned actor cannot authorize`,
      );
    }
    sql(
      `UPDATE auth.users SET is_anonymous=false,deleted_at=NULL,banned_until=NULL WHERE id='${actor.id}'`,
    );
  }
  await f.rpc("remove_institution_member", {
    p_institution: f.verified,
    p_member: actor.id,
  }, f.owner.token);
  for (const [ep, body] of endpoints) {
    check(
      (await post(ep, body, actor.token)).response.status === 404,
      `10B ${ep} prior success gives no permanent access`,
    );
  }
  // Pause only this runner's Auth container; production has no fault switches.
  const project = /^project_id\s*=\s*"([^"]+)"/m.exec(
    readFileSync("supabase/config.toml", "utf8"),
  )![1];
  if (
    !/^certichain_8[ad]_[0-9a-f]{8}$/.test(project) &&
    !(Deno.env.get("GITHUB_ACTIONS") === "true" && project === "certichain")
  ) throw new Error("Owned Auth required");
  const authAction = (action: string) => {
    const r = spawnSync("docker", [action, `supabase_auth_${project}`], {
      windowsHide: true,
      stdio: "ignore",
      timeout: 15000,
    });
    if (r.status !== 0) throw new Error("Owned Auth action failed");
  };
  authAction("pause");
  try {
    const results = await Promise.all(
      endpoints.map(async ([ep, body]) => ({ ep, ...await post(ep, body) })),
    );
    for (const r of results) {
      check(
        r.response.status === 503 && r.data.error === "temporary_failure" &&
          r.response.headers.get("cache-control") === "no-store",
        `10B ${r.ep} real Auth outage is safe 503`,
      );
    }
  } finally {
    authAction("unpause");
  }
  check(
    (await post("revocation-progress", { certificate_id: cid })).response
      .status === 200,
    "10B real Auth restored and session revalidated",
  );
}
