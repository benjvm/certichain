// Real gateway/Edge/PostgREST/Storage, exclusively on an explicitly disposable local stack.
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { fixture, terminate, until } from "./local_issuance_fixture.mjs";
import { sql } from "../scripts/local_supabase.mjs";

if (process.env.CERTICHAIN_TEST_DISPOSABLE !== "1") {
  throw new Error(
    "Requires CERTICHAIN_TEST_DISPOSABLE=1 on a disposable local stack",
  );
}
let assertions = 0;
function check(value, label) {
  if (!value) throw new Error(label);
  assertions++;
}
const f = await fixture(); // localStatus refuses any non-loopback API.
let originalBudget;
const budget = (used = 0, age = "0 seconds") =>
  sql(
    `UPDATE certichain_private.public_verification_budget SET used=${used},window_started_at=clock_timestamp()-interval '${age}';`,
  );
const used = () =>
  Number(
    sql("SELECT used FROM certichain_private.public_verification_budget;"),
  );
const endpoint = `${f.local.API_URL}/functions/v1/verify-certificate`;
async function query(
  body = JSON.stringify({ credential_code: randomUUID() }),
  options = {},
) {
  const response = await fetch(endpoint + (options.query ?? ""), {
    method: options.method ?? "POST",
    // Deliberately no Authorization or apikey, including readiness/OPTIONS.
    headers: { "Content-Type": "application/json", ...options.headers },
    body: options.method && options.method !== "POST" ? undefined : body,
    signal: AbortSignal.timeout(15_000),
    ...(body instanceof ReadableStream ? { duplex: "half" } : {}),
  });
  const data = await response.json().catch(() => null);
  check(
    response.headers.get("cache-control") === "no-store",
    "No-store on gateway response",
  );
  check(
    response.headers.get("access-control-allow-origin") === "*",
    "Public CORS",
  );
  return { response, data };
}
function error(r, status, code) {
  check(r.response.status === status, `HTTP ${status}: ${code}`);
  check(
    JSON.stringify(r.data) === JSON.stringify({ error: code }),
    "Error contains only public code",
  );
}
function notFound(r) {
  check(r.response.status === 200, "Absent is 200");
  check(
    JSON.stringify(r.data) === '{"result":"not_found","schema_version":"1"}' ||
      JSON.stringify(r.data) === '{"schema_version":"1","result":"not_found"}',
    "Uniform minimal absence",
  );
}
let barrier;
try {
  originalBudget = JSON.parse(
    sql(
      "SELECT row_to_json(b) FROM certichain_private.public_verification_budget b;",
    ),
  );
  await until(async () => {
    const r = await fetch(endpoint, {
      method: "OPTIONS",
      signal: AbortSignal.timeout(2000),
    }).catch(() => null);
    if (!r) return false;
    await r.arrayBuffer();
    return r.status === 204;
  }, "Public runtime ready without credentials");
  budget();
  const issued = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: randomUUID(),
    title: "8A Public Certificate",
    description: "PRIVATE 8A DESCRIPTION",
    expires_at: "2030-01-01T00:00:00.123456Z",
  });
  check(issued.status === 201, "Real 7B publication");
  const cert = issued.data.certificate_id;
  const before = sql(
    `SELECT row_to_json(c) FROM public.certificates c WHERE id='${cert}';`,
  );
  const record = JSON.parse(before), code = record.credential_code;
  check(
    code !== cert && /^[0-9a-f-]{36}$/.test(code),
    "Independent public UUID",
  );
  const pdfBefore = await f.stored(f.verified, cert);
  // Historical passage of time, with production constraints/triggers enabled.
  // Direct synthetic publication, as in the SQL suite; never edits emitted dates.
  const expiredCode = randomUUID(),
    expiredCert = randomUUID(),
    expiredOp = randomUUID();
  sql(
    `INSERT INTO public.certificate_issuance_operations(id,institution_id,actor_id,holder_id,
    idempotency_key,request_fingerprint,pdf_hash,target_certificate_id,stored_hash,status,title,expires_at)
    VALUES('${expiredOp}','${f.verified}','${f.owner.id}','${f.holder.id}',gen_random_uuid(),repeat('a',64),
    '${record.document_hash}','${expiredCert}','${record.document_hash}','finalizing','8A Expired','2021-01-01T00:00:00.123456Z');
    INSERT INTO public.certificates(id,institution_id,issued_by,holder_id,title,credential_code,
    issued_at,expires_at,document_path,document_hash,issuance_operation_id)
    VALUES('${expiredCert}','${f.verified}','${f.owner.id}','${f.holder.id}','8A Expired','${expiredCode}',
    '2020-01-01T00:00:00.654321Z','2021-01-01T00:00:00.123456Z','${f.verified}/${expiredCert}.pdf',
    '${record.document_hash}','${expiredOp}');
    UPDATE public.certificate_issuance_operations SET status='completed',certificate_id='${expiredCert}' WHERE id='${expiredOp}';`,
  );
  const expired = await query(JSON.stringify({ credential_code: expiredCode }));
  check(
    expired.response.status === 200 && expired.data.result === "expired",
    "Expired publication through actual HTTP",
  );
  check(
    expired.data.issued_at.includes(".654321") &&
      expired.data.expires_at.includes(".123456"),
    "Expired dates retain precision",
  );
  for (const equivalent of [code, code.toUpperCase(), code]) {
    const r = await query(JSON.stringify({ credential_code: equivalent }));
    check(
      r.response.status === 200 && r.data.result === "valid",
      "Public valid without Auth/key",
    );
    check(
      Object.keys(r.data).sort().join(",") ===
        "checked_at,credential_code,expires_at,issued_at,issuer,result,schema_version,title,verification_source",
      "Exact approved projection",
    );
    check(Object.keys(r.data.issuer).join(",") === "name", "Issuer name alone");
    check(
      r.data.credential_code === code &&
        r.data.verification_source === "certichain_registry" &&
        r.data.expires_at.includes(".123456"),
      "Canonical code and microseconds",
    );
    for (
      const secret of [
        record.holder_id,
        record.issued_by,
        cert,
        record.description,
        record.document_path,
        record.document_hash,
        f.holder.email,
        f.local.SERVICE_ROLE_KEY,
      ]
    ) {
      check(
        !JSON.stringify(r.data).includes(secret),
        "No private data in success",
      );
    }
  }
  notFound(await query());
  const legacyBefore = sql(
    `SELECT row_to_json(c) FROM public.certificates c WHERE id='${f.legacy}';`,
  );
  notFound(
    await query(
      JSON.stringify({
        credential_code: JSON.parse(legacyBefore).credential_code,
      }),
    ),
  );
  const incomplete = await f.issue(
    f.owner,
    {
      institution_id: f.verified,
      holder_id: f.holder.id,
      idempotency_key: randomUUID(),
      title: "Incomplete",
    },
    undefined,
    "after_reserve",
  );
  check(incomplete.status === 503, "Incomplete issuance fixture");
  notFound(await query());
  for (
    const [body, headers, status, expectedError] of [
      ['{"credential_code":"invalid"}', {}, 400, "invalid_input"],
      [
        JSON.stringify({ credential_code: `${code}\n` }),
        {},
        400,
        "invalid_input",
      ],
      ["{", {}, 400, "invalid_input"],
      [
        JSON.stringify({ credential_code: code, holder_id: f.holder.id }),
        {},
        400,
        "invalid_input",
      ],
      ['{"credential_code":42}', {}, 400, "invalid_input"],
      ["null", {}, 400, "invalid_input"],
      ["{}", { "Content-Type": "text/plain" }, 400, "invalid_input"],
      [" ".repeat(2049), {}, 413, "payload_too_large"],
    ]
  ) {
    const count = used();
    error(await query(body, { headers }), status, expectedError);
    check(used() === count + 1, "Invalid POST consumes budget");
  }
  const streaming = new ReadableStream({
    start(c) {
      c.enqueue(new TextEncoder().encode(" ".repeat(1024)));
      c.enqueue(new TextEncoder().encode(" ".repeat(1025)));
      c.close();
    },
  });
  error(await query(streaming), 413, "payload_too_large");
  const count = used();
  const options = await query(undefined, { method: "OPTIONS" });
  check(
    options.response.status === 204 && options.data === null,
    "OPTIONS empty",
  );
  check(
    options.response.headers.get("access-control-allow-methods") ===
      "POST, OPTIONS",
    "CORS methods",
  );
  for (const method of ["GET", "PUT", "DELETE"]) {
    error(await query(undefined, { method }), 405, "method_not_allowed");
  }
  check(used() === count, "OPTIONS/methods do not consume");

  // A real lock barrier forces all four HTTP requests to compete for the last slot.
  budget(59);
  barrier = spawn("docker", [
    "exec",
    "-i",
    "supabase_db_certichain",
    "psql",
    "-X",
    "-qAt",
    "-U",
    "postgres",
    "-d",
    "postgres",
    "-v",
    "ON_ERROR_STOP=1",
  ], { windowsHide: true, stdio: "pipe" });
  let output = "";
  barrier.stdout.on("data", (b) => {
    output += b;
  });
  barrier.stderr.resume();
  barrier.stdin.write(
    "BEGIN; SELECT singleton FROM certichain_private.public_verification_budget FOR UPDATE;\n\\echo ready\n",
  );
  await until(() => output.includes("ready"), "Limiter barrier acquired");
  const racing = Array.from({ length: 4 }, () => query());
  let overlapFailure;
  try {
    await until(
      () =>
        Number(
          sql(
            "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%consume_public_verification_budget%';",
          ),
        ) === 4,
      "All four public backends waiting on budget",
      1800,
    );
  } catch (error) {
    overlapFailure = error;
  } finally {
    barrier.stdin.end("COMMIT;\n");
  }
  const results = await Promise.all(racing);
  if (overlapFailure) throw overlapFailure;
  check(
    results.filter((r) => r.response.status === 200).length === 1 &&
      results.filter((r) => r.response.status === 429).length === 3,
    "One final slot; no over-allocation",
  );
  check(used() === 60, "Atomic count remains 60");
  const limited = await query("{", {
    query: "?reset=true&limit=99999",
    headers: {
      "X-Forwarded-For": randomUUID(),
      "X-Rate-Limit": "99999",
      "X-Reset": "true",
    },
  });
  error(limited, 429, "rate_limited");
  check(
    Number(limited.response.headers.get("retry-after")) >= 1 &&
      Number(limited.response.headers.get("retry-after")) <= 60,
    "Server Retry-After exposed",
  );
  check(used() === 60, "Client inputs cannot reset budget");
  budget(60, "60 seconds");
  notFound(await query());
  check(used() === 1, "Window renewed without waiting");
  budget(0);
  await Promise.all(Array.from({ length: 60 }, () => query())).then(
    (responses) => {
      check(
        responses.every((r) => r.response.status === 200),
        "60 grants exactly",
      );
    },
  );
  error(await query(), 429, "rate_limited");

  // Infrastructure errors pass through actual Edge, with no test-only endpoint hooks.
  budget();
  sql(
    "REVOKE EXECUTE ON FUNCTION public.lookup_public_certificate(text) FROM service_role;",
  );
  try {
    error(await query(), 503, "temporary_failure");
  } finally {
    sql(
      "GRANT EXECUTE ON FUNCTION public.lookup_public_certificate(text) TO service_role;",
    );
  }
  sql("DELETE FROM certichain_private.public_verification_budget;");
  try {
    error(await query(), 503, "temporary_failure");
  } finally {
    sql(
      "INSERT INTO certichain_private.public_verification_budget VALUES(true,clock_timestamp(),0);",
    );
  }
  notFound(await query());
  check(
    sql(
      `SELECT row_to_json(c) FROM public.certificates c WHERE id='${cert}';`,
    ) === before,
    "Full certificate unchanged",
  );
  check(
    sql(
      `SELECT row_to_json(c) FROM public.certificates c WHERE id='${f.legacy}';`,
    ) === legacyBefore,
    "Full historical certificate unchanged",
  );
  check(
    (await f.stored(f.verified, cert)).equals(pdfBefore),
    "Private PDF bytes unchanged",
  );
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "suspended",
  }, f.platform.token);
  const suspended = await query(JSON.stringify({ credential_code: code }));
  check(
    suspended.data.result === "issuer_unavailable",
    "Suspension is not certificate revocation",
  );
  check(
    (await query(JSON.stringify({ credential_code: expiredCode }))).data
      .result === "expired",
    "Expiry wins over suspension via HTTP",
  );
  sql(
    `UPDATE public.certificates SET status='revoked' WHERE id='${expiredCert}';`,
  );
  check(
    (await query(JSON.stringify({ credential_code: expiredCode }))).data
      .result === "revoked",
    "Revoked wins over expiry and suspension via HTTP",
  );
  sql(`UPDATE public.certificates SET status='revoked' WHERE id='${cert}';`);
  const revoked = await query(JSON.stringify({ credential_code: code }));
  check(
    revoked.data.result === "revoked",
    "Existing trusted revocation wins over suspension",
  );
  check(
    (await f.stored(f.verified, cert)).equals(pdfBefore),
    "Revocation preserves document",
  );
  console.log(
    `PASS: public verification, ${assertions} assertions; real unauthenticated gateway and atomic limiter`,
  );
} finally {
  terminate(barrier);
  try {
    if (originalBudget) {
      sql(
        `UPDATE certichain_private.public_verification_budget SET used=${originalBudget.used},window_started_at='${originalBudget.window_started_at}'::timestamptz;`,
      );
    }
  } finally {
    await f.close();
  }
}
