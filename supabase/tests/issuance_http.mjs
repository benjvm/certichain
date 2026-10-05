import { runtimeReady, startRuntime } from "./edge_runtime.mjs";
import { spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import {
  api,
  assertDisposableStack,
  localStatus,
  sql,
} from "../scripts/local_supabase.mjs";
import { flatePdfFixture, pdfFixture } from "./pdf_fixture.mjs";
import { reconcile } from "../admin/reconcile_issuance.mjs";

assertDisposableStack();
const local = localStatus();
const run = randomUUID(), faultToken = randomUUID();
const folder = mkdtempSync(join(tmpdir(), "certichain-7b-"));
const envFile = join(folder, "local.env");
writeFileSync(envFile, `CERTICHAIN_LOCAL_FAULT_TOKEN=${faultToken}\n`, {
  mode: 0o600,
});
const edge = startRuntime(envFile);
const server = edge.child;
const users = [], institutions = [];
let assertions = 0;
function check(condition, label) {
  if (!condition) throw new Error(label);
  assertions++;
}
async function jsonRequest(path, token, body, method = "POST") {
  const response = await api(local, path, token, method, JSON.stringify(body), {
    "Content-Type": "application/json",
  });
  const data = await response.json().catch(() => ({}));
  return { response, data };
}
async function rpc(name, args, token = local.SERVICE_ROLE_KEY) {
  edge.current();
  const { response, data } = await jsonRequest(
    `/rest/v1/rpc/${name}`,
    token,
    args,
  );
  check(response.ok, `Fixture RPC ${name} failed: HTTP ${response.status}`);
  return data;
}
async function createUser(label) {
  edge.current();
  const password = `Local-${randomUUID()}-Aa1!`,
    email = `${label}-${run}@example.invalid`;
  const created = await jsonRequest(
    "/auth/v1/admin/users",
    local.SERVICE_ROLE_KEY,
    {
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: "Synthetic 7B Identity",
        role: "platform_admin",
      },
    },
  );
  check(created.response.ok, "Local Auth fixture creation");
  const id = created.data.id;
  users.push(id);
  const session = await jsonRequest(
    "/auth/v1/token?grant_type=password",
    local.ANON_KEY,
    { email, password },
  );
  check(
    session.response.ok && session.data.user.id === id,
    "Real local Auth session",
  );
  return { id, token: session.data.access_token };
}
async function institution(platform, owner, status = "verified") {
  const id = await rpc("create_institution", {
    p_name: "Synthetic 7B Institution",
    p_slug: `phase7b-${run}-${randomUUID().slice(0, 8)}`,
    p_owner: owner.id,
  }, platform.token);
  institutions.push(id);
  if (status === "verified" || status === "suspended") {
    await rpc("set_institution_status", {
      p_institution: id,
      p_status: "verified",
    }, platform.token);
  }
  if (status === "rejected" || status === "suspended") {
    await rpc(
      "set_institution_status",
      { p_institution: id, p_status: status },
      platform.token,
    );
  }
  return id;
}
const validPdf = pdfFixture();
let common;
async function issue(actor, changes = {}, options = {}) {
  const form = new FormData(), input = { ...common, ...changes };
  for (const [key, value] of Object.entries(input)) {
    if (value !== null && value !== undefined) form.append(key, String(value));
  }
  form.append(
    "pdf",
    new Blob([options.bytes ?? validPdf], {
      type: options.mime ?? "application/pdf",
    }),
    options.filename ?? "certificate.pdf",
  );
  const headers = options.fault
    ? { "x-local-fault-token": faultToken, "x-local-fault": options.fault }
    : {};
  let response;
  if (actor) {
    response = await api(
      local,
      "/functions/v1/issue-certificate",
      actor.token,
      "POST",
      form,
      headers,
    );
  } else {response = await fetch(
      `${local.API_URL}/functions/v1/issue-certificate`,
      { method: "POST", body: form, headers: { apikey: local.ANON_KEY } },
    );}
  const data = await response.json().catch(() => ({}));
  check(
    !JSON.stringify(data).match(
      /document_path|request_fingerprint|stored_hash|lease_token|service_role|\.pdf|http:\/\//,
    ),
    "Response leaks internal data",
  );
  return { status: response.status, data };
}
function expect(result, status, error) {
  check(
    result.status === status,
    `Expected HTTP ${status}, got ${result.status} (${
      result.data.error ?? "gateway"
    })`,
  );
  if (error) check(result.data.error === error, `Expected error ${error}`);
}
function expire(key) {
  check(/^[0-9a-f-]{36}$/.test(key), "Safe fixture key");
  sql(
    `UPDATE public.certificate_issuance_operations SET lease_until=clock_timestamp()-interval '1 second' WHERE institution_id='${common.institution_id}' AND idempotency_key='${key}';`,
  );
}
async function operation(key) {
  const r = await api(
    local,
    `/rest/v1/certificate_issuance_operations?institution_id=eq.${common.institution_id}&idempotency_key=eq.${key}`,
    local.SERVICE_ROLE_KEY,
  );
  check(r.ok, "Technical operation lookup");
  return (await r.json())[0];
}
async function stored(op) {
  const r = await api(
    local,
    `/storage/v1/object/authenticated/certificates/${op.institution_id}/${op.target_certificate_id}.pdf`,
    local.SERVICE_ROLE_KEY,
  );
  check(r.ok, "Technical stored bytes lookup");
  return Buffer.from(await r.arrayBuffer());
}

try {
  await runtimeReady(edge, local);
  const platform = await createUser("platform"),
    owner = await createUser("owner"),
    admin = await createUser("admin"),
    issuer = await createUser("issuer"),
    holder = await createUser("holder"),
    outsider = await createUser("outsider");
  sql(
    `SELECT certichain_private.grant_platform_admin('${platform.id}', '${platform.id}', (SELECT count(*)::int FROM public.profiles WHERE role='platform_admin'));`,
  );
  const inst = await institution(platform, owner);
  for (const [user, role] of [[admin, "admin"], [issuer, "issuer"]]) {
    await rpc("set_institution_member", {
      p_institution: inst,
      p_member: user.id,
      p_role: role,
    }, owner.token);
  }
  const other = await institution(platform, outsider);
  common = {
    institution_id: inst,
    holder_id: holder.id,
    idempotency_key: randomUUID(),
    title: "Synthetic Certificate",
    description: "Synthetic Description",
    expires_at: null,
  };

  expect(await issue(null), 401);
  expect(await issue({ token: "invalid" }), 401);
  expect(
    await issue({ token: local.SERVICE_ROLE_KEY }),
    401,
    "unauthenticated",
  );
  for (const actor of [owner, admin, issuer]) {
    const key = randomUUID();
    const result = await issue(actor, { idempotency_key: key });
    expect(result, 201);
    const op = await operation(key);
    check(op.status === "completed", "Completed transaction observed");
    const bytes = await stored(op),
      hash = createHash("sha256").update(bytes).digest("hex");
    check(
      bytes.equals(validPdf) && hash === op.pdf_hash && hash === op.stored_hash,
      "Exact stored bytes match input SHA-256",
    );
    const certificate = await api(
      local,
      `/rest/v1/certificates?id=eq.${result.data.certificate_id}`,
      local.SERVICE_ROLE_KEY,
    );
    const row = (await certificate.json())[0];
    check(
      row.document_hash === hash && row.status === "active" &&
        row.issued_by === actor.id && row.id === op.target_certificate_id,
      "Published certificate contract",
    );
    expect(await issue(actor, { idempotency_key: key }), 200);
    check(
      (await reconcile(local, op.id)).protected === 1,
      "Reconciliation protects completed",
    );
    check((await stored(op)).equals(bytes), "Completed PDF retained");
  }
  for (const actor of [outsider, holder, platform]) {
    expect(
      await issue(actor, { idempotency_key: randomUUID() }),
      403,
      "forbidden",
    );
  }
  expect(
    await issue(owner, {
      institution_id: other,
      idempotency_key: randomUUID(),
    }),
    403,
    "forbidden",
  );
  for (const state of ["pending", "rejected", "suspended"]) {
    const id = await institution(platform, owner, state);
    expect(
      await issue(owner, { institution_id: id, idempotency_key: randomUUID() }),
      403,
      "forbidden",
    );
  }
  expect(
    await issue(owner, {
      holder_id: randomUUID(),
      idempotency_key: randomUUID(),
    }),
    422,
    "invalid_input",
  );
  expect(
    await issue(owner, {
      holder_id: platform.id,
      idempotency_key: randomUUID(),
    }),
    422,
    "invalid_input",
  );
  // Recipient eligibility changes are read from Auth, not profile enumeration.
  for (
    const update of [
      "email_confirmed_at=NULL",
      "banned_until=now()+interval '1 day'",
      "is_anonymous=true",
    ]
  ) {
    sql(`UPDATE auth.users SET ${update} WHERE id='${holder.id}';`);
    expect(
      await issue(owner, { idempotency_key: randomUUID() }),
      422,
      "invalid_input",
    );
    sql(
      `UPDATE auth.users SET email_confirmed_at=now(), banned_until=NULL, is_anonymous=false WHERE id='${holder.id}';`,
    );
  }
  for (
    const field of [
      "actor_id",
      "issued_by",
      "status",
      "credential_code",
      "id",
      "issued_at",
      "document_path",
      "document_hash",
    ]
  ) expect(await issue(owner, { [field]: "injected" }), 400, "invalid_input");
  expect(await issue(owner, { title: "a".repeat(201) }), 400, "invalid_input");
  expect(
    await issue(owner, {
      expires_at: "2000-01-01T00:00:00Z",
      idempotency_key: randomUUID(),
    }),
    422,
    "invalid_input",
  );
  expect(
    await issue(owner, {
      expires_at: "2050-01-01T00:00:00Z",
      idempotency_key: randomUUID(),
    }),
    422,
    "invalid_input",
  );
  for (
    const options of [
      { bytes: Buffer.alloc(0) },
      { bytes: Buffer.from("text") },
      { bytes: Buffer.from("%PDF-1.4\n%%EOF\n") },
      { bytes: validPdf.subarray(0, 200) },
      {
        bytes: Buffer.from(
          validPdf.toString().replace("0000000009", "0000000010"),
        ),
      },
      { mime: "text/plain" },
      { filename: "file.txt" },
      { bytes: flatePdfFixture(true) },
      {
        bytes: pdfFixture(
          undefined,
          "/OpenAction << /S /JavaScript /JS (bad) >>",
        ),
      },
      { bytes: pdfFixture(undefined, "/Names << /EmbeddedFiles << >> >>") },
      { bytes: pdfFixture(undefined, "/A << /S /Rendition >>") },
      { bytes: pdfFixture(undefined, "/AcroForm << >>") },
      {
        bytes: Buffer.from(
          validPdf.toString().replace(
            "/Size 4 /Root 1 0 R",
            "/Size 4 /Root 1 0 R /Encrypt 1 0 R",
          ),
        ),
      },
    ]
  ) {
    const key = randomUUID();
    expect(
      await issue(owner, { idempotency_key: key }, options),
      422,
      "invalid_pdf",
    );
    check(!(await operation(key)), "Invalid PDF rejected before reservation");
  }
  const large = pdfFixture(8_388_608);
  expect(
    await issue(owner, { idempotency_key: randomUUID() }, {
      bytes: flatePdfFixture(),
    }),
    201,
  );
  expect(
    await issue(owner, { idempotency_key: randomUUID() }, { bytes: large }),
    201,
  );
  expect(
    await issue(owner, { idempotency_key: randomUUID() }, {
      bytes: pdfFixture(8_388_609),
    }),
    413,
    "payload_too_large",
  );
  // Real HTTP chunked multipart without Content-Length exercises the read limit.
  const oversized = new ReadableStream({
    start(c) {
      c.enqueue(Buffer.alloc(8_388_608 + 32_769));
      c.close();
    },
  });
  const oversizedResult = await fetch(
    `${local.API_URL}/functions/v1/issue-certificate`,
    {
      method: "POST",
      duplex: "half",
      headers: {
        apikey: local.ANON_KEY,
        Authorization: `Bearer ${owner.token}`,
        "Content-Type": "multipart/form-data; boundary=local",
      },
      body: oversized,
    },
  );
  check(
    oversizedResult.status === 413,
    "Chunked request limited before parsing",
  );
  await oversizedResult.arrayBuffer();

  for (const table of ["certificates", "certificate_issuance_operations"]) {
    const result = await jsonRequest(`/rest/v1/${table}`, owner.token, {});
    check(!result.response.ok, `Direct ${table} INSERT blocked`);
  }
  const direct = await jsonRequest(
    "/rest/v1/rpc/reserve_certificate_issuance",
    owner.token,
    {
      p_institution: inst,
      p_actor: owner.id,
      p_holder: holder.id,
      p_key: randomUUID(),
      p_fingerprint: "a".repeat(64),
      p_pdf_hash: "b".repeat(64),
      p_title: "Direct",
    },
  );
  check(!direct.response.ok, "Direct technical RPC blocked");
  const profile = await api(
    local,
    `/rest/v1/profiles?id=eq.${holder.id}`,
    owner.token,
  );
  check(
    profile.ok && (await profile.json()).length === 0,
    "Holder lookup did not expand profile SELECT",
  );

  const key = randomUUID();
  const first = await issue(issuer, { idempotency_key: key });
  expect(first, 201);
  expect(
    await issue(issuer, { idempotency_key: key, title: "Changed" }),
    409,
    "idempotency_conflict",
  );
  expect(
    await issue(owner, { idempotency_key: key }),
    409,
    "idempotency_conflict",
  );
  expect(
    await issue(issuer, { idempotency_key: key }, {
      bytes: pdfFixture(undefined, "/Lang (es)"),
    }),
    409,
    "idempotency_conflict",
  );
  const sameBytes = await issue(issuer, { idempotency_key: randomUUID() });
  expect(sameBytes, 201);
  check(
    sameBytes.data.certificate_id !== first.data.certificate_id,
    "Distinct keys allow identical content",
  );
  await rpc("remove_institution_member", {
    p_institution: inst,
    p_member: issuer.id,
  }, owner.token);
  expect(await issue(issuer, { idempotency_key: key }), 403, "forbidden");
  await rpc("set_institution_member", {
    p_institution: inst,
    p_member: issuer.id,
    p_role: "issuer",
  }, owner.token);

  const concurrentKey = randomUUID();
  const simultaneous = await Promise.all(
    Array.from(
      { length: 8 },
      () => issue(issuer, { idempotency_key: concurrentKey }),
    ),
  );
  check(
    simultaneous.every((r) => [200, 201, 409].includes(r.status)),
    "Simultaneous attempts have clear results",
  );
  check(
    simultaneous.filter((r) => r.status === 201).length === 1,
    "Exactly one simultaneous publisher",
  );
  const concurrentOp = await operation(concurrentKey);
  check(
    concurrentOp.status === "completed" &&
      (await stored(concurrentOp)).equals(validPdf),
    "Concurrent object not overwritten",
  );
  expect(await issue(issuer, { idempotency_key: concurrentKey }), 200);

  for (
    const stage of [
      "after_reserve",
      "after_upload",
      "after_read",
      "after_validate",
      "before_publish",
      "after_publish",
    ]
  ) {
    const failureKey = randomUUID();
    expect(
      await issue(issuer, { idempotency_key: failureKey }, { fault: stage }),
      503,
      "temporary_failure",
    );
    if (stage !== "after_publish") {
      expect(
        await issue(issuer, { idempotency_key: failureKey }),
        409,
        "operation_in_progress",
      );
      expire(failureKey);
    }
    const recovered = await issue(issuer, { idempotency_key: failureKey });
    expect(recovered, stage === "after_publish" ? 200 : 201);
    const op = await operation(failureKey);
    check(
      op.status === "completed" && (await stored(op)).equals(validPdf),
      `Recovered boundary ${stage}`,
    );
  }
  const dbFailureKey = randomUUID();
  try {
    sql(
      `CREATE FUNCTION certichain_private.phase7b_test_completion_failure() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF NEW.idempotency_key='${dbFailureKey}' AND NEW.status='completed' THEN
      RAISE EXCEPTION 'Injected local completion failure'; END IF; RETURN NEW; END; $$;
      CREATE TRIGGER phase7b_test_completion_failure BEFORE UPDATE ON public.certificate_issuance_operations
      FOR EACH ROW EXECUTE FUNCTION certichain_private.phase7b_test_completion_failure();`,
    );
    expect(
      await issue(issuer, { idempotency_key: dbFailureKey }),
      503,
      "temporary_failure",
    );
    const op = await operation(dbFailureKey);
    check(
      op.status === "finalizing" && op.certificate_id === null,
      "Actual PostgreSQL rollback leaves finalizing",
    );
    check(
      sql(
        `SELECT count(*) FROM public.certificates WHERE issuance_operation_id='${op.id}';`,
      ) === "0",
      "No certificate survived failed publication transaction",
    );
  } finally {
    sql(
      "DROP TRIGGER IF EXISTS phase7b_test_completion_failure ON public.certificate_issuance_operations; DROP FUNCTION IF EXISTS certichain_private.phase7b_test_completion_failure();",
    );
  }
  expire(dbFailureKey);
  expect(await issue(issuer, { idempotency_key: dbFailureKey }), 201);
  // Compare-and-set takeover of a genuinely expired reservation via simultaneous SQL RPCs.
  const leaseKey = randomUUID();
  expect(
    await issue(issuer, { idempotency_key: leaseKey }, {
      fault: "after_reserve",
    }),
    503,
  );
  expire(leaseKey);
  const oldLease = await operation(leaseKey);
  const args = {
    p_institution: inst,
    p_actor: issuer.id,
    p_holder: holder.id,
    p_key: leaseKey,
    p_fingerprint: oldLease.request_fingerprint,
    p_pdf_hash: oldLease.pdf_hash,
    p_title: common.title,
    p_description: common.description,
  };
  const takeovers = await Promise.all([
    rpc("reserve_certificate_issuance", args),
    rpc("reserve_certificate_issuance", args),
  ]);
  check(
    takeovers.filter((x) => x.status === "uploading").length === 1 &&
      takeovers.filter((x) => x.status === "in_progress").length === 1,
    "Expired lease has one new owner",
  );
  const stale = await jsonRequest(
    "/rest/v1/rpc/advance_certificate_issuance",
    local.SERVICE_ROLE_KEY,
    {
      p_institution: inst,
      p_operation: oldLease.id,
      p_lease: oldLease.lease_token,
      p_action: "validate",
      p_stored_hash: oldLease.pdf_hash,
    },
  );
  check(
    !stale.response.ok && stale.data.code === "PT409",
    "Old process cannot finalize",
  );
  expire(leaseKey);
  expect(await issue(issuer, { idempotency_key: leaseKey }), 201);

  // A Storage collision is inspected; mismatched bytes are never replaced.
  const collisionKey = randomUUID();
  expect(
    await issue(issuer, { idempotency_key: collisionKey }, {
      fault: "after_reserve",
    }),
    503,
  );
  const collision = await operation(collisionKey),
    collisionBytes = pdfFixture(undefined, "/Lang (different)");
  const upload = await api(
    local,
    `/storage/v1/object/certificates/${inst}/${collision.target_certificate_id}.pdf`,
    local.SERVICE_ROLE_KEY,
    "POST",
    collisionBytes,
    { "Content-Type": "application/pdf", "x-upsert": "false" },
  );
  check(upload.ok, "Collision fixture stored");
  await upload.arrayBuffer();
  expire(collisionKey);
  expect(
    await issue(issuer, { idempotency_key: collisionKey }),
    503,
    "stored_object_invalid",
  );
  check(
    (await stored(collision)).equals(collisionBytes),
    "Collision bytes not overwritten",
  );
  check(
    (await operation(collisionKey)).status === "cleanup_pending",
    "Invalid collision queued for cleanup",
  );
  const failedCleanup = await reconcile(local, collision.id, {
    failDelete: true,
  });
  check(failedCleanup.pending === 1, "Cleanup failure remains durable");
  expire(collisionKey);
  check(
    (await reconcile(local, collision.id)).cleaned === 1,
    "Cleanup retry succeeds",
  );
  check(
    (await operation(collisionKey)).status === "failed",
    "Failed operation closed",
  );
  expect(
    await issue(issuer, { idempotency_key: collisionKey }),
    409,
    "attempt_failed",
  );
  // Late old upload after cleanup cannot publish, and the tombstone catches it.
  const lateUpload = await api(
    local,
    `/storage/v1/object/certificates/${inst}/${collision.target_certificate_id}.pdf`,
    local.SERVICE_ROLE_KEY,
    "POST",
    validPdf,
    { "Content-Type": "application/pdf", "x-upsert": "false" },
  );
  check(lateUpload.ok, "Simulated late upload");
  await lateUpload.arrayBuffer();
  check(
    (await reconcile(local, collision.id)).cleaned === 1,
    "Late orphan cleaned from failed tombstone",
  );

  // Auth changes after upload are checked at publication, then reconciled.
  const revokedKey = randomUUID();
  expect(
    await issue(issuer, { idempotency_key: revokedKey }, {
      fault: "after_upload",
    }),
    503,
  );
  const revoked = await operation(revokedKey);
  await rpc("remove_institution_member", {
    p_institution: inst,
    p_member: issuer.id,
  }, owner.token);
  await rpc("advance_certificate_issuance", {
    p_institution: inst,
    p_operation: revoked.id,
    p_lease: revoked.lease_token,
    p_action: "validate",
    p_stored_hash: revoked.pdf_hash,
  });
  const forbiddenPublish = await jsonRequest(
    "/rest/v1/rpc/advance_certificate_issuance",
    local.SERVICE_ROLE_KEY,
    {
      p_institution: inst,
      p_operation: revoked.id,
      p_lease: revoked.lease_token,
      p_action: "publish",
    },
  );
  check(
    forbiddenPublish.response.status === 403 &&
      forbiddenPublish.data.code === "42501",
    "Membership withdrawal prevents publication",
  );
  expire(revokedKey);
  check(
    (await reconcile(local, revoked.id)).cleaned === 1,
    "Revoked authorization orphan cleaned",
  );

  const duplicates = sql(
    `SELECT count(*) FROM (SELECT issuance_operation_id FROM public.certificates WHERE institution_id='${inst}' GROUP BY issuance_operation_id HAVING count(*)>1) AS duplicate;`,
  );
  check(duplicates === "0", "No operation produced duplicate certificates");
  console.log(
    `PASS local issuance HTTP: ${assertions} assertions; real Auth, Edge runtime, Storage, leases and recovery`,
  );
} catch (error) {
  console.error(`Local HTTP test failed: ${error.message}`);
  throw error;
} finally {
  if (server.pid) {
    if (process.platform === "win32") {
      spawnSync("taskkill", ["/pid", String(server.pid), "/t", "/f"], {
        windowsHide: true,
        stdio: "ignore",
      });
    } else server.kill("SIGTERM");
  }
  // Discover any own creation whose response was lost; never replay its POST.
  for (
    const id of sql(
      `SELECT id FROM auth.users WHERE email LIKE '%${run}%@example.invalid';`,
    ).split("\n").filter(Boolean)
  ) if (!users.includes(id)) users.push(id);
  for (
    const id of sql(
      `SELECT id FROM public.institutions WHERE slug LIKE 'phase7b-${run}-%';`,
    ).split("\n").filter(Boolean)
  ) if (!institutions.includes(id)) institutions.push(id);
  // Remove PDFs exclusively via Storage API before fixture-only SQL teardown.
  for (const id of institutions) {
    const r = await api(
      local,
      `/rest/v1/certificate_issuance_operations?institution_id=eq.${id}&select=target_certificate_id`,
      local.SERVICE_ROLE_KEY,
    );
    if (!r.ok) throw new Error("Fixture cleanup lookup failed");
    const paths = (await r.json()).map((op) =>
      `${id}/${op.target_certificate_id}.pdf`
    );
    if (paths.length) {
      const deletion = await jsonRequest(
        "/storage/v1/object/certificates",
        local.SERVICE_ROLE_KEY,
        { prefixes: paths },
        "DELETE",
      );
      if (!deletion.response.ok) {
        throw new Error("Fixture Storage cleanup failed");
      }
    }
  }
  // Synthetic fixtures only, with exclusive table locks inside one transaction.
  // Circular RESTRICT FKs and last-owner/delete guards intentionally prevent
  // production deletion; temporarily disable them only for this local teardown.
  if (
    institutions.every((id) => /^[0-9a-f-]{36}$/.test(id)) &&
    users.every((id) => /^[0-9a-f-]{36}$/.test(id))
  ) {
    const ids = institutions.map((x) => `'${x}'`).join(",") || "NULL";
    sql(
      `BEGIN;
      ALTER TABLE public.certificates DISABLE TRIGGER ALL;
      ALTER TABLE public.certificate_issuance_operations DISABLE TRIGGER ALL;
      ALTER TABLE public.institution_members DISABLE TRIGGER ALL;
      ALTER TABLE public.institutions DISABLE TRIGGER ALL;
      DELETE FROM public.certificates WHERE institution_id IN (${ids});
      DELETE FROM public.certificate_issuance_operations WHERE institution_id IN (${ids});
      DELETE FROM public.institution_members WHERE institution_id IN (${ids});
      DELETE FROM public.institutions WHERE id IN (${ids});
      ALTER TABLE public.certificates ENABLE TRIGGER ALL;
      ALTER TABLE public.certificate_issuance_operations ENABLE TRIGGER ALL;
      ALTER TABLE public.institution_members ENABLE TRIGGER ALL;
      ALTER TABLE public.institutions ENABLE TRIGGER ALL;
      COMMIT;`,
      "supabase_admin",
    );
  }
  for (const id of users) {
    const deleted = await api(
      local,
      `/auth/v1/admin/users/${id}`,
      local.SERVICE_ROLE_KEY,
      "DELETE",
    );
    if (!deleted.ok) throw new Error("Local Auth fixture cleanup failed");
    await deleted.arrayBuffer();
  }
  rmSync(folder, { recursive: true, force: true });
}
