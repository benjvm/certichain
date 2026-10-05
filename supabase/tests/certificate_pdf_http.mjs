import { runtimeReady, startRuntime } from "./edge_runtime.mjs";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";
import {
  api,
  assertDisposableStack,
  localStatus,
  sql,
} from "../scripts/local_supabase.mjs";
import { pdfFixture } from "./pdf_fixture.mjs";
import { until } from "./local_issuance_fixture.mjs";

assertDisposableStack();
const local = localStatus();
const run = randomUUID();
const edge = startRuntime();
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

async function issue(actor, inst, holder) {
  const form = new FormData();
  for (
    const [key, value] of Object.entries({
      institution_id: inst,
      holder_id: holder.id,
      idempotency_key: randomUUID(),
      title: "Synthetic 7C PDF",
    })
  ) form.append(key, value);
  form.append(
    "pdf",
    new Blob([pdfFixture()], { type: "application/pdf" }),
    "certificate.pdf",
  );
  const response = await api(
    local,
    "/functions/v1/issue-certificate",
    actor.token,
    "POST",
    form,
  );
  check(response.status === 201, "Real 7B publication for PDF fixture");
  return (await response.json()).certificate_id;
}
async function document(actor, id) {
  const response = actor
    ? await api(
      local,
      "/functions/v1/certificate-pdf",
      actor.token,
      "POST",
      JSON.stringify({ certificate_id: id }),
      { "Content-Type": "application/json" },
    )
    : await fetch(`${local.API_URL}/functions/v1/certificate-pdf`, {
      method: "POST",
      headers: { apikey: local.ANON_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ certificate_id: id }),
    });
  const data = await response.json();
  check(
    !JSON.stringify(data).match(
      /document_path|document_hash|service_role|lease_token/,
    ),
    "No private fields returned",
  );
  if (response.status !== 401) {
    check(
      response.headers.get("cache-control") === "no-store",
      "PDF response no-store",
    );
  }
  return { response, data };
}
try {
  await runtimeReady(edge, local);
  const platform = await createUser("pdf-platform"),
    owner = await createUser("pdf-owner"),
    admin = await createUser("pdf-admin"),
    issuer = await createUser("pdf-issuer"),
    holder = await createUser("pdf-holder"),
    outsider = await createUser("pdf-outsider");
  sql(
    `SELECT certichain_private.grant_platform_admin('${platform.id}', '${platform.id}', (SELECT count(*)::int FROM public.profiles WHERE role='platform_admin'));`,
  );
  const inst = await institution(platform, owner);
  await institution(platform, outsider);
  for (const [user, role] of [[admin, "admin"], [issuer, "issuer"]]) {
    await rpc("set_institution_member", {
      p_institution: inst,
      p_member: user.id,
      p_role: role,
    }, owner.token);
  }
  const id = await issue(issuer, inst, holder);
  let capability;
  for (const actor of [holder, owner, admin, issuer]) {
    const r = await document(actor, id);
    check(
      r.response.status === 200 && r.data.expires_in === 60,
      "Holder or allowed current member has PDF access",
    );
    check(
      Object.keys(r.data).sort().join(",") === "expires_in,signed_url",
      "Minimal response",
    );
    const signed = new URL(r.data.signed_url, local.API_URL);
    const jwt = JSON.parse(
      Buffer.from(signed.searchParams.get("token").split(".")[1], "base64url"),
    );
    check(
      jwt.exp - jwt.iat <= 60 && jwt.exp - jwt.iat > 0,
      "Actual signed capability limited to sixty seconds",
    );
    const download = await fetch(signed);
    check(
      download.ok &&
        Buffer.from(await download.arrayBuffer()).equals(pdfFixture()),
      "Real signed download of exact bytes",
    );
    capability = r.data.signed_url;
  }
  const firstFresh = await document(holder, id);
  const firstClaims = JSON.parse(
    Buffer.from(
      new URL(firstFresh.data.signed_url, local.API_URL).searchParams.get(
        "token",
      ).split(".")[1],
      "base64url",
    ),
  );
  // Storage signs at second precision; independent sign requests within one
  // second may yield equal JWTs. Cross the actual iat, then prove freshness.
  await until(
    () => Math.floor(Date.now() / 1000) > firstClaims.iat,
    "new capability signing second",
    3000,
  );
  const nextFresh = await document(holder, id);
  check(
    nextFresh.response.status === 200 &&
      nextFresh.data.signed_url !== firstFresh.data.signed_url,
    "New authorization produces a fresh capability, no cached previous URL",
  );
  const foreign = await document(outsider, id),
    missing = await document(holder, randomUUID());
  const legacy = randomUUID();
  sql(
    `INSERT INTO public.certificates(id,institution_id,holder_id,issued_by,title,credential_code) VALUES('${legacy}','${inst}','${holder.id}','${issuer.id}','Synthetic legacy','${randomUUID()}');`,
  );
  const historical = await document(holder, legacy);
  for (
    const r of [foreign, missing, historical, await document(platform, id)]
  ) {
    check(
      r.response.status === 404 && r.data.error === "document_unavailable",
      "Uniform inaccessible/missing/legacy response",
    );
  }
  check(
    JSON.stringify(foreign.data) === JSON.stringify(missing.data) &&
      JSON.stringify(missing.data) === JSON.stringify(historical.data),
    "No enumeration distinction",
  );
  for (
    const actor of [null, { token: "invalid" }, {
      token: local.SERVICE_ROLE_KEY,
    }]
  ) {
    check(
      (await document(actor, id)).response.status === 401,
      "Anonymous/invalid/technical key is not a real session",
    );
  }
  await rpc("remove_institution_member", {
    p_institution: inst,
    p_member: issuer.id,
  }, owner.token);
  check(
    (await document(issuer, id)).response.status === 404,
    "Removed member denied fresh URL",
  );
  const previousCapability = await fetch(new URL(capability, local.API_URL));
  check(
    previousCapability.ok &&
      Buffer.from(await previousCapability.arrayBuffer()).equals(pdfFixture()),
    "Already issued capacity remains valid after member removal until its TTL",
  );
  await rpc("set_institution_status", {
    p_institution: inst,
    p_status: "suspended",
  }, platform.token);
  for (const actor of [owner, admin]) {
    check(
      (await document(actor, id)).response.status === 404,
      "Suspended institution member denied",
    );
  }
  check(
    (await document(holder, id)).response.status === 200,
    "Holder keeps PDF despite suspension",
  );
  const direct = await api(
    local,
    `/storage/v1/object/authenticated/certificates/${inst}/${id}.pdf`,
    holder.token,
  );
  check(!direct.ok, "Authenticated direct Storage remains denied");
  await direct.arrayBuffer();
  console.log(
    "PDF authorization checked; waiting for the issued capability to expire.",
  );
  await delay(64000);
  const expired = await fetch(new URL(capability, local.API_URL));
  check(!expired.ok, "Actual capability no longer downloads after expiry");
  await expired.arrayBuffer();
  const deletion = await jsonRequest(
    "/storage/v1/object/certificates",
    local.SERVICE_ROLE_KEY,
    { prefixes: [`${inst}/${id}.pdf`] },
    "DELETE",
  );
  check(deletion.response.ok, "Remove synthetic object through Storage API");
  const absentStorage = await document(holder, id);
  check(
    absentStorage.response.status === 404 &&
      JSON.stringify(absentStorage.data) === JSON.stringify(missing.data),
    "Missing Storage has same safe response",
  );
  const invalid = await jsonRequest(
    "/functions/v1/certificate-pdf",
    holder.token,
    { certificate_id: id, actor_id: owner.id },
  );
  check(
    invalid.response.status === 400,
    "Closed input ignores no spoofable actor",
  );
  const preflight = await fetch(
    `${local.API_URL}/functions/v1/certificate-pdf`,
    {
      method: "OPTIONS",
      headers: {
        Origin: "http://localhost:3000",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "authorization,apikey,content-type",
      },
    },
  );
  check(
    preflight.ok &&
      preflight.headers.get("access-control-allow-origin") === "*",
    "Chrome authenticated preflight supported",
  );
  console.log(
    `PASS local PDF HTTP: ${assertions} assertions; Auth, memberships, suspension, legacy, Storage, signed bytes and actual expiry`,
  );
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
}
