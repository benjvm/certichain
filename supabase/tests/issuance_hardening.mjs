import { spawn, spawnSync } from "node:child_process";
import {
  createHash,
  createHmac,
  createPrivateKey,
  createPublicKey,
  randomUUID,
  sign,
  verify,
} from "node:crypto";
import { performance } from "node:perf_hooks";
import { api, sql } from "../scripts/local_supabase.mjs";
import { reconcile } from "../admin/reconcile_issuance.mjs";
import { compatibilityPdf, pdfFixture } from "./pdf_fixture.mjs";
import {
  check as assert,
  fixture,
  terminate,
  until,
} from "./local_issuance_fixture.mjs";

let assertions = 0;
function check(condition, label) {
  assert(condition, label);
  assertions++;
}
export function expiredToken(local, realToken) {
  // Preserve actual Auth claims/algorithm/kid and verify the original signature
  // first. Read the signing key exclusively from LOCAL Auth into runner memory.
  // Never transfer it to Flutter, write it or print it.
  const parts = realToken.split(".");
  const header = JSON.parse(Buffer.from(parts[0], "base64url"));
  let signer;
  if (header.alg === "ES256") {
    const inspection = spawnSync("docker", [
      "inspect",
      "supabase_auth_certichain",
    ], { encoding: "utf8", timeout: 5000 });
    check(
      inspection.status === 0,
      "Local Auth signing configuration available",
    );
    const env = JSON.parse(inspection.stdout)[0].Config.Env;
    const keys = JSON.parse(
      env.find((v) => v.startsWith("GOTRUE_JWT_KEYS=")).slice(
        "GOTRUE_JWT_KEYS=".length,
      ),
    );
    const jwk = keys.find((key) =>
      key.kid === header.kid && key.alg === "ES256" && key.d
    );
    check(Boolean(jwk), "Matching local Auth signing key");
    const privateKey = createPrivateKey({ key: jwk, format: "jwk" });
    check(
      verify("sha256", Buffer.from(parts.slice(0, 2).join(".")), {
        key: createPublicKey(privateKey),
        dsaEncoding: "ieee-p1363",
      }, Buffer.from(parts[2], "base64url")),
      "Original real Auth signature verified before expiring it",
    );
    signer = (body) =>
      sign("sha256", Buffer.from(body), {
        key: privateKey,
        dsaEncoding: "ieee-p1363",
      }).toString("base64url");
  } else {
    check(
      header.alg === "HS256" &&
        createHmac("sha256", local.JWT_SECRET).update(
            parts.slice(0, 2).join("."),
          ).digest("base64url") === parts[2],
      "Original local Auth HMAC verified",
    );
    signer = (body) =>
      createHmac("sha256", local.JWT_SECRET).update(body).digest("base64url");
  }
  const payload = JSON.parse(Buffer.from(realToken.split(".")[1], "base64url"));
  payload.exp = Math.floor(Date.now() / 1000) - 60;
  payload.iat = payload.exp - 3600;
  const body = `${parts[0]}.${
    Buffer.from(JSON.stringify(payload)).toString("base64url")
  }`;
  return `${body}.${signer(body)}`;
}

// A real PostgreSQL row lock gates every contender at reserve, rather than
// relying on Promise.all scheduling. We observe ALL waiting backends before release.
async function withBarrier(inst, contenders, action) {
  const locker = spawn("docker", [
    "exec",
    "-i",
    "supabase_db_certichain",
    "psql",
    "-X",
    "-q",
    "-A",
    "-t",
    "-U",
    "postgres",
    "-d",
    "postgres",
    "-v",
    "ON_ERROR_STOP=1",
  ], { windowsHide: true, stdio: "pipe" });
  let output = "";
  locker.stdout.on("data", (b) => output += b);
  locker.stderr.resume();
  const done = new Promise((resolve, reject) =>
    locker.on(
      "exit",
      (code) =>
        code === 0 ? resolve() : reject(new Error("Barrier SQL failed")),
    )
  );
  done.catch(() => {}); // Failure is still propagated by the awaited transaction.
  let requests;
  try {
    locker.stdin.write(
      `BEGIN; SELECT id FROM public.institutions WHERE id='${inst}' FOR UPDATE;\n\\echo barrier-ready\n`,
    );
    await until(
      () => output.includes("barrier-ready"),
      "institution row locked",
    );
    requests = action();
    requests.catch(() => {});
    await until(
      () =>
        Number(
          sql(
            `SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND wait_event_type='Lock' AND query LIKE '%reserve_certificate_issuance%';`,
          ),
        ) >= contenders,
      "all HTTP reserve contenders blocked",
      25_000,
    );
    locker.stdin.end("COMMIT;\n");
    await done;
    return await requests;
  } finally {
    terminate(locker);
    // Release/settle every real request before the fixture teardown can run.
    await requests?.catch(() => {});
  }
}

async function main() {
  const f = await fixture();
  const start = performance.now();
  const times = [];
  let certificates = 0, submittedBytes = 0;
  const input = (key = randomUUID()) => ({
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: key,
    title: "7D hardening",
  });
  async function completed(key, bytes) {
    const state = f.snapshot(f.verified, key);
    check(
      state.operations.length === 1 && state.certificates.length === 1,
      "Exactly one operation/certificate in PostgreSQL",
    );
    const [op] = state.operations, [cert] = state.certificates;
    const stored = await f.stored(f.verified, cert.id);
    const hash = createHash("sha256").update(stored).digest("hex");
    check(
      op.status === "completed" && cert.id === op.target_certificate_id &&
        cert.id === op.certificate_id,
      "Published IDs and terminal state",
    );
    check(
      stored.equals(bytes) && hash === op.pdf_hash && hash === op.stored_hash &&
        hash === cert.document_hash,
      "Final stored bytes and all SHA-256 links",
    );
    check(
      cert.holder_id === f.holder.id && cert.issued_by === f.issuer.id,
      "Correct holder/actor persisted",
    );
    const listed = await f.json(
      "/storage/v1/object/list/certificates",
      f.local.SERVICE_ROLE_KEY,
      { prefix: f.verified, limit: 100, search: `${cert.id}.pdf` },
    );
    check(
      listed.response.ok &&
        listed.data.filter((o) => o.name === `${cert.id}.pdf`).length === 1,
      "One real Storage object",
    );
    return op;
  }
  try {
    const invalid = [
      [f.owner, { ...input(), institution_id: f.pending }, pdfFixture(), 403],
      [f.owner, { ...input(), institution_id: f.suspended }, pdfFixture(), 403],
      [f.outsider, input(), pdfFixture(), 403],
      [f.platform, input(), pdfFixture(), 403],
      [f.issuer, { ...input(), holder_id: randomUUID() }, pdfFixture(), 422],
      [f.issuer, { ...input(), holder_id: f.platform.id }, pdfFixture(), 422],
      [f.issuer, input(), Buffer.from("%PDF-invalid"), 422],
      [f.issuer, input(), pdfFixture(8_388_609), 413],
    ];
    const unconfirmed = await f.user("unconfirmed", false);
    invalid.push([
      f.issuer,
      { ...input(), holder_id: unconfirmed.id },
      pdfFixture(),
      422,
    ]);
    sql(
      `UPDATE public.profiles SET role='institution_admin' WHERE id='${f.outsider.id}';`,
    );
    invalid.push([f.outsider, input(), pdfFixture(), 403]);
    for (const [actor, data, bytes, expected] of invalid) {
      const r = await f.issue(actor, data, bytes);
      check(r.status === expected, `Negative scenario HTTP ${expected}`);
      const state = f.snapshot(data.institution_id, data.idempotency_key);
      check(
        state.operations.length === 0 && state.certificates.length === 0,
        "Denial left no reservation/certificate",
      );
    }
    const expired = await f.issue({
      token: expiredToken(f.local, f.issuer.token),
    }, input());
    check(
      expired.status === 401,
      "Actually expired signed JWT rejected at local gateway",
    );
    // Bounded compatibility corpus, including page and aggregate inflation limits.
    for (
      const [label, bytes, expected] of [
        ["PDF 1.4 text/font", compatibilityPdf({ version: "1.4" }), 201],
        ["PDF 1.7 Unicode Info", compatibilityPdf(), 201],
        ["100 pages", compatibilityPdf({ pages: 100 }), 201],
        ["101 pages", compatibilityPdf({ pages: 101 }), 422],
        [
          "Flate 16 MiB decoded",
          compatibilityPdf({ inflated: 16_777_216 }),
          201,
        ],
        [
          "Flate over decoded budget",
          compatibilityPdf({ inflated: 16_777_217 }),
          422,
        ],
        ["PDF 2.0 outside MVP", compatibilityPdf({ version: "2.0" }), 422],
      ]
    ) {
      const key = randomUUID(), before = performance.now();
      const r = await f.issue(f.issuer, input(key), bytes);
      check(
        r.status === expected,
        `Compatibility ${label}: expected ${expected}, got ${r.status}`,
      );
      times.push({
        label,
        milliseconds: Math.round(performance.now() - before),
      });
      submittedBytes += bytes.length;
      if (expected === 201) {
        await completed(key, bytes);
        certificates++;
      } else {check(
          f.snapshot(f.verified, key).operations.length === 0,
          "Unsupported PDF not reserved",
        );}
    }
    const key = randomUUID(), pdf = pdfFixture();
    const replies = await withBarrier(
      f.verified,
      4,
      () =>
        Promise.all(
          Array.from({ length: 4 }, () => f.issue(f.issuer, input(key), pdf)),
        ),
    );
    check(
      replies.every((r) => [200, 201, 409].includes(r.status)),
      "Barrier duplicate contenders have bounded outcomes",
    );
    await completed(key, pdf);
    certificates++;
    check(
      (await f.issue(f.issuer, input(key), pdf)).status === 200,
      "Completed replay",
    );
    for (
      const [data, bytes] of [[{ ...input(key), title: "Changed" }, pdf], [
        input(key),
        compatibilityPdf(),
      ]]
    ) {
      check(
        (await f.issue(f.issuer, data, bytes)).status === 409,
        "Changed metadata/PDF conflicts",
      );
      await completed(key, pdf);
    }
    const leaseKey = randomUUID();
    check(
      (await f.issue(f.issuer, input(leaseKey), pdf, "after_upload")).status ===
        503,
      "Failure after real upload",
    );
    const before = f.snapshot(f.verified, leaseKey).operations[0];
    check(
      before.status === "uploading" &&
        (await f.stored(f.verified, before.target_certificate_id)).equals(pdf),
      "Durable lease/object before takeover",
    );
    f.expire(f.verified, leaseKey);
    await withBarrier(
      f.verified,
      4,
      () =>
        Promise.all(
          Array.from(
            { length: 4 },
            () => f.issue(f.issuer, input(leaseKey), pdf),
          ),
        ),
    );
    const after = await completed(leaseKey, pdf);
    certificates++;
    check(
      after.id === before.id &&
        after.target_certificate_id === before.target_certificate_id &&
        after.request_fingerprint === before.request_fingerprint &&
        after.lease_token !== before.lease_token,
      "Lease takeover preserves identity/content and fences old token",
    );
    const failedKey = randomUUID();
    check(
      (await f.issue(f.issuer, input(failedKey), pdf, "after_upload"))
        .status === 503,
      "Orphan fixture has real bytes",
    );
    const orphan = f.snapshot(f.verified, failedKey).operations[0];
    f.expire(f.verified, failedKey);
    check(
      (await reconcile(f.local, orphan.id, { failDelete: true })).pending === 1,
      "Failed cleanup remains recoverable",
    );
    check(
      f.snapshot(f.verified, failedKey).operations[0].status ===
          "cleanup_pending" &&
        await f.stored(f.verified, orphan.target_certificate_id) !== null,
      "Failed cleanup kept object/durable state",
    );
    f.expire(f.verified, failedKey);
    check(
      (await reconcile(f.local, orphan.id)).cleaned === 1,
      "Operator reconciles orphan",
    );
    check(
      f.snapshot(f.verified, failedKey).certificates.length === 0 &&
        f.snapshot(f.verified, failedKey).operations[0].status === "failed" &&
        await f.stored(f.verified, orphan.target_certificate_id) === null,
      "Terminal failed/zero certificates/absent Storage proven",
    );
    check(
      (await f.issue(f.issuer, input(failedKey), pdf)).status === 409,
      "Failed key cannot reopen",
    );
    // Abuse/load budget: at most 4 in flight, 12 invalid requests and 8 x 1 MiB.
    for (let i = 0; i < 3; i++) {
      const keys = Array.from({ length: 4 }, () => randomUUID());
      const r = await Promise.all(
        keys.map((k) => f.issue(f.issuer, input(k), Buffer.from("not-pdf"))),
      );
      check(
        r.every((x) => x.status === 422) &&
          keys.every((k) => f.snapshot(f.verified, k).operations.length === 0),
        "Invalid burst has no durable effects",
      );
    }
    const loadPdf = pdfFixture(1_048_576);
    for (let i = 0; i < 2; i++) {
      const keys = Array.from({ length: 4 }, () => randomUUID()),
        before = performance.now();
      const r = await Promise.all(
        keys.map((k) => f.issue(f.issuer, input(k), loadPdf)),
      );
      check(
        r.every((x) => x.status === 201),
        "Bounded four-request 1 MiB load",
      );
      for (const k of keys) {
        await completed(k, loadPdf);
        certificates++;
      }
      submittedBytes += loadPdf.length * 4;
      times.push({
        label: `batch ${i + 1}: 4 x 1 MiB`,
        milliseconds: Math.round(performance.now() - before),
      });
    }
    const count = Number(
      sql(
        `SELECT count(*) FROM public.certificates WHERE institution_id='${f.verified}' AND issuance_operation_id IS NOT NULL;`,
      ),
    );
    check(
      count === certificates,
      "Final PostgreSQL total equals validated publications",
    );
    check(
      sql(
        `SELECT count(*) FROM storage.objects WHERE bucket_id='certificates' AND name LIKE '${f.verified}/%';`,
      ) === String(certificates),
      "Final Storage total matches certificates, no orphan",
    );
    check(
      performance.now() - start < 180_000 && submittedBytes < 16_777_216,
      "CI load time/byte budget",
    );
    console.log(
      JSON.stringify({
        result: "PASS",
        assertions,
        certificates,
        submittedBytes,
        totalMilliseconds: Math.round(performance.now() - start),
        times,
      }),
    );
  } finally {
    await f.close();
  }
}

// Also importable by the browser runner for the expired-JWT fixture.
if (process.argv[1]?.endsWith("issuance_hardening.mjs")) await main();
