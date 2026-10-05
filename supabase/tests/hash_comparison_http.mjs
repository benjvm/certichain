import { createHash, randomUUID } from "node:crypto";
import { check, fixture, until } from "./local_issuance_fixture.mjs";
import { sql } from "../scripts/local_supabase.mjs";

if (process.env.CERTICHAIN_TEST_DISPOSABLE !== "1") {
  throw new Error("Disposable stack required");
}
const f = await fixture();
let assertions = 0;
function verify(value, label) {
  check(value, label);
  assertions++;
}
const saved = sql(
  "SELECT row_to_json(b) FROM certichain_private.public_verification_budget b;",
);
function budget(used = 0) {
  sql(
    `UPDATE certichain_private.public_verification_budget SET used=${used},window_started_at=clock_timestamp();`,
  );
}
async function query(
  body,
  {
    endpoint = "compare-certificate-hash",
    method = "POST",
    mime = "application/json",
  } = {},
) {
  // Independent anonymous fetch; no SDK, JWT, API key or session cookies.
  const response = await fetch(`${f.local.API_URL}/functions/v1/${endpoint}`, {
    method,
    headers: { "Content-Type": mime },
    body: method === "POST"
      ? (typeof body === "string" ? body : JSON.stringify(body))
      : undefined,
    signal: AbortSignal.timeout(15000),
  });
  verify(response.headers.get("cache-control") === "no-store", "No-store");
  verify(response.headers.get("access-control-allow-origin") === "*", "CORS");
  return { response, data: await response.json().catch(() => null) };
}
try {
  await until(async () => {
    const r = await query(undefined, { method: "OPTIONS" }).catch(() => null);
    return r?.response.status === 204;
  }, "Comparison worker ready");
  budget();
  const issued = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: randomUUID(),
    title: "8C synthetic",
  });
  verify(issued.status === 201, "Production issuance");
  const cert = issued.data.certificate_id;
  const row = JSON.parse(
    sql(`SELECT row_to_json(c) FROM public.certificates c WHERE id='${cert}';`),
  );
  const original = await f.stored(f.verified, cert);
  const digest = createHash("sha256").update(original).digest("hex");
  const code = row.credential_code;
  async function compareState(state) {
    for (
      const [candidate, integrity] of [[digest, "match"], [
        "0".repeat(64),
        "integrity_mismatch",
      ]]
    ) {
      const r = await query({
        credential_code: code.toUpperCase(),
        document_sha256: candidate,
      });
      verify(
        r.response.status === 200 && r.data.file_integrity === integrity,
        "Candidate comparison",
      );
      verify(
        r.data.verification.result === state,
        "Current state independent from integrity",
      );
      verify(
        Object.keys(r.data).sort().join(",") ===
          "file_integrity,schema_version,verification",
        "Closed DTO",
      );
      verify(
        !JSON.stringify(r.data).includes(digest),
        "Expected digest never returned",
      );
      verify(
        Object.keys(r.data.verification).length === 9 &&
          r.data.verification.checked_at,
        "v1 projection and server checked_at",
      );
    }
  }
  await compareState("valid");
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "suspended",
  }, f.platform.token);
  await compareState("issuer_unavailable");
  sql(`UPDATE public.certificates SET status='revoked' WHERE id='${cert}';`);
  await compareState("revoked");
  const legacy = sql(
    `SELECT credential_code FROM public.certificates WHERE id='${f.legacy}';`,
  );
  for (const absent of [randomUUID(), legacy]) {
    const r = await query({ credential_code: absent, document_sha256: digest });
    verify(
      JSON.stringify(r.data.verification) ===
          '{"result":"not_found","schema_version":"1"}' ||
        JSON.stringify(r.data.verification) ===
          '{"schema_version":"1","result":"not_found"}',
      "Uniform absence",
    );
    verify(
      r.data.file_integrity === "unavailable" &&
        Object.keys(r.data).length === 3,
      "Unavailable minimal",
    );
  }
  for (
    const body of [
      "{}",
      "null",
      "[]",
      "{",
      JSON.stringify({
        credential_code: code,
        document_sha256: digest,
        filename: "private.pdf",
      }),
      JSON.stringify({
        credential_code: code,
        document_sha256: digest.toUpperCase(),
      }),
      JSON.stringify({ credential_code: code, document_sha256: digest + "\n" }),
    ]
  ) {
    const r = await query(body);
    verify(
      r.response.status === 400 && r.data.error === "invalid_input",
      "Strict input",
    );
  }
  verify(
    (await query("x".repeat(2049))).response.status === 413,
    "2 KiB real byte limit",
  );
  verify(
    (await query({}, { method: "GET" })).response.status === 405,
    "Method",
  );
  verify(
    (await query({}, { mime: "application/json; charset=latin1" })).response
      .status === 400,
    "UTF-8 only",
  );
  sql(
    "REVOKE EXECUTE ON FUNCTION public.compare_public_certificate_hash(text,text) FROM service_role;",
  );
  try {
    const r = await query({ credential_code: code, document_sha256: digest });
    verify(
      r.response.status === 503 && r.data.error === "temporary_failure",
      "Infrastructure never mismatch/absence",
    );
  } finally {
    sql(
      "GRANT EXECUTE ON FUNCTION public.compare_public_certificate_hash(text,text) TO service_role;",
    );
  }
  budget(59);
  verify(
    (await query({})).response.status === 400,
    "Invalid comparison consumes shared last slot",
  );
  const limited = await query({ credential_code: code }, {
    endpoint: "verify-certificate",
  });
  verify(
    limited.response.status === 429 &&
      Number(limited.response.headers.get("retry-after")) > 0,
    "Shared rate limit and Retry-After",
  );
  budget();
  const replies = await Promise.all(
    Array.from({ length: 80 }, (_, i) =>
      query(
        i % 4 === 0
          ? {}
          : i % 2
          ? { credential_code: code }
          : { credential_code: code, document_sha256: digest },
        { endpoint: i % 2 ? "verify-certificate" : "compare-certificate-hash" },
      )),
  );
  verify(
    replies.filter((r) => r.response.status === 429).length === 20 &&
      replies.filter((r) => [200, 400].includes(r.response.status)).length ===
        60,
    "Atomic 60 shared POSTs including invalid and concurrent",
  );
  verify(
    sql("SELECT used FROM certichain_private.public_verification_budget;") ===
      "60",
    "One shared counter",
  );
  verify(
    (await f.stored(f.verified, cert)).equals(original),
    "All comparisons preserve private PDF bytes",
  );
  console.log(
    `PASS: ${assertions} comparison HTTP assertions, real anonymous endpoints/shared concurrent budget`,
  );
} finally {
  const old = JSON.parse(saved);
  sql(
    `UPDATE certichain_private.public_verification_budget SET used=${old.used},window_started_at='${old.window_started_at}'::timestamptz;`,
  );
  await f.close();
}
