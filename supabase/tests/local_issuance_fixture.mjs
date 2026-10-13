import { runtimeReady, startRuntime } from "./edge_runtime.mjs";
// Test infrastructure only. All privileged work stays in Node on the local host.
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import {
  api,
  assertDisposableStack,
  localStatus,
  sql,
} from "../scripts/local_supabase.mjs";
import { pdfFixture } from "./pdf_fixture.mjs";

export function check(condition, label) {
  if (!condition) throw new Error(label);
}
export async function until(predicate, label, milliseconds = 20_000) {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await delay(50);
  }
  throw new Error(`Timed out: ${label}`);
}
export function terminate(child) {
  if (!child?.pid || child.exitCode !== null) return;
  if (process.platform === "win32") {
    spawnSync("taskkill", ["/pid", String(child.pid), "/t", "/f"], {
      windowsHide: true,
      stdio: "ignore",
    });
  } else child.kill("SIGTERM");
}
export async function fixture(readRpcUrl) {
  assertDisposableStack();
  const local = localStatus();
  const users = [], institutions = [];
  const run = randomUUID(), faultToken = randomUUID();
  const directory = mkdtempSync(join(tmpdir(), "certichain-7d-"));
  check(
    resolve(directory).startsWith(resolve(tmpdir()) + sep),
    "Unsafe fixture directory",
  );
  const envFile = join(directory, "functions.env");
  if (readRpcUrl && !/^http:\/\/anvil:8545$/.test(readRpcUrl)) {
    throw new Error("Fixture read RPC must be owned private Anvil");
  }
  writeFileSync(
    envFile,
    `CERTICHAIN_LOCAL_FAULT_TOKEN=${faultToken}\n${
      readRpcUrl ? `EVM_RPC_URL=${readRpcUrl}\n` : ""
    }`,
  );
  const edge = startRuntime(envFile);
  const runtime = edge.child;
  async function json(path, token, body, method = "POST") {
    const response = await api(
      local,
      path,
      token,
      method,
      JSON.stringify(body),
      {
        "Content-Type": "application/json",
      },
    );
    return { response, data: await response.json().catch(() => ({})) };
  }
  async function rpc(name, body, token) {
    edge.current();
    const r = await json(`/rest/v1/rpc/${name}`, token, body);
    check(r.response.ok, `Fixture RPC ${name}: HTTP ${r.response.status}`);
    return r.data;
  }
  async function user(label, confirmed = true) {
    edge.current();
    const email = `phase7d-${label}-${run}@example.invalid`;
    const password = `Local-${randomUUID()}-Aa1!`;
    const r = await json("/auth/v1/admin/users", local.SERVICE_ROLE_KEY, {
      email,
      password,
      email_confirm: confirmed,
      user_metadata: { full_name: "Synthetic 7D", role: "platform_admin" },
    });
    check(r.response.ok, "Synthetic local Auth identity");
    users.push(r.data.id);
    if (!confirmed) return { id: r.data.id, email, password };
    const session = await json(
      "/auth/v1/token?grant_type=password",
      local.ANON_KEY,
      { email, password },
    );
    check(
      session.response.ok && session.data.user.id === r.data.id,
      "Real password login",
    );
    return { id: r.data.id, email, password, token: session.data.access_token };
  }
  async function institution(platform, owner, name, status = "verified") {
    const id = await rpc("create_institution", {
      p_name: name,
      p_slug: `phase7d-${run}-${randomUUID().slice(0, 8)}`,
      p_owner: owner.id,
    }, platform.token);
    institutions.push(id);
    if (status !== "pending") {
      await rpc("set_institution_status", {
        p_institution: id,
        p_status: "verified",
      }, platform.token);
    }
    if (status === "suspended") {
      await rpc("set_institution_status", {
        p_institution: id,
        p_status: status,
      }, platform.token);
    }
    return id;
  }
  async function issue(actor, input, bytes = pdfFixture(), fault) {
    edge.current();
    const form = new FormData();
    for (const [key, value] of Object.entries(input)) {
      if (value != null) form.append(key, value);
    }
    form.append(
      "pdf",
      new Blob([bytes], { type: "application/pdf" }),
      "synthetic.pdf",
    );
    const response = await api(
      local,
      "/functions/v1/issue-certificate",
      actor.token,
      "POST",
      form,
      {
        Connection: "close",
        ...(fault
          ? { "x-local-fault-token": faultToken, "x-local-fault": fault }
          : {}),
      },
    );
    return { status: response.status, data: await response.json() };
  }
  function snapshot(inst, key) {
    check(
      /^[0-9a-f-]{36}$/.test(inst) && /^[0-9a-f-]{36}$/.test(key),
      "Safe snapshot IDs",
    );
    return JSON.parse(sql(`SELECT json_build_object('operations',
      (SELECT coalesce(json_agg(o),'[]') FROM public.certificate_issuance_operations o WHERE institution_id='${inst}' AND idempotency_key='${key}'),
      'certificates', (SELECT coalesce(json_agg(c),'[]') FROM public.certificates c JOIN public.certificate_issuance_operations o ON o.id=c.issuance_operation_id WHERE o.institution_id='${inst}' AND o.idempotency_key='${key}'));`));
  }
  function expire(inst, key) {
    snapshot(inst, key); // UUID validation; only this fixture's institutions.
    check(institutions.includes(inst), "Lease fixture ownership");
    sql(
      `UPDATE public.certificate_issuance_operations SET lease_until=clock_timestamp()-interval '1 second' WHERE institution_id='${inst}' AND idempotency_key='${key}';`,
    );
  }
  async function stored(inst, certificate) {
    const r = await api(
      local,
      `/storage/v1/object/authenticated/certificates/${inst}/${certificate}.pdf`,
      local.SERVICE_ROLE_KEY,
    );
    if (!r.ok) {
      await r.arrayBuffer();
      return null;
    }
    return Buffer.from(await r.arrayBuffer());
  }
  async function close() {
    try {
      // A create response may be lost AFTER committing. Discover this run's
      // rows before teardown; never replay a non-idempotent create POST.
      for (
        const id of JSON.parse(
          sql(
            `SELECT coalesce(json_agg(id),'[]') FROM auth.users WHERE email LIKE '%-${run}@example.invalid';`,
          ),
        )
      ) {
        if (!users.includes(id)) users.push(id);
      }
      for (
        const id of JSON.parse(
          sql(
            `SELECT coalesce(json_agg(id),'[]') FROM public.institutions WHERE slug LIKE 'phase7d-${run}-%';`,
          ),
        )
      ) {
        if (!institutions.includes(id)) institutions.push(id);
      }
      for (const id of institutions) {
        const r = await api(
          local,
          `/rest/v1/certificate_issuance_operations?institution_id=eq.${id}&select=target_certificate_id`,
          local.SERVICE_ROLE_KEY,
        );
        check(r.ok, "Cleanup operations lookup");
        const prefixes = (await r.json()).map((o) =>
          `${id}/${o.target_certificate_id}.pdf`
        );
        if (prefixes.length) {
          const deletion = await json(
            "/storage/v1/object/certificates",
            local.SERVICE_ROLE_KEY,
            { prefixes },
            "DELETE",
          );
          check(deletion.response.ok, "Fixture Storage cleanup");
        }
      }
      check(
        institutions.every((id) => /^[0-9a-f-]{36}$/.test(id)),
        "Cleanup IDs",
      );
      const ids = institutions.map((id) => `'${id}'`).join(",") || "NULL";
      // Synthetic rows only. Exclusive locks and guards restored atomically.
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
      check(
        sql(
          `SELECT count(*) FROM public.certificates WHERE institution_id IN (${ids});
        SELECT count(*) FROM public.certificate_issuance_operations WHERE institution_id IN (${ids});
        SELECT count(*) FROM storage.objects WHERE bucket_id='certificates' AND split_part(name,'/',1) IN (${ids});`,
        ) === "0\n0\n0",
        "Fixture certificates, operations and real Storage objects all removed",
      );
      for (const id of users) {
        // A deletion response may be lost as Auth closes pooled connections.
        // Confirm real absence before accepting it, retry only this fixture ID.
        await until(async () => {
          const deleted = await api(
            local,
            `/auth/v1/admin/users/${id}`,
            local.SERVICE_ROLE_KEY,
            "DELETE",
            undefined,
            { Connection: "close" },
          ).catch(() => null);
          if (deleted) await deleted.arrayBuffer();
          const remaining = await api(
            local,
            `/auth/v1/admin/users/${id}`,
            local.SERVICE_ROLE_KEY,
            "GET",
            undefined,
            { Connection: "close" },
          );
          await remaining.arrayBuffer();
          return remaining.status === 404;
        }, "Fixture Auth deletion confirmed");
      }
      check(
        sql(
          `SELECT count(*) FROM public.institutions WHERE id IN (${ids});`,
        ) === "0",
        "No fixture institutions remain",
      );
      check(
        sql(
          `SELECT count(*) FROM auth.users WHERE id IN (${
            users.map((id) => `'${id}'`).join(",") || "NULL"
          });`,
        ) === "0",
        "No fixture users remain",
      );
    } finally {
      terminate(runtime);
      rmSync(directory, { recursive: true, force: true });
    }
  }
  try {
    await runtimeReady(edge, local);
    const platform = await user("platform"),
      owner = await user("owner"),
      holder = await user("holder"),
      outsider = await user("outsider"),
      issuer = await user("issuer");
    const count = sql(
      "SELECT count(*) FROM public.profiles WHERE role='platform_admin';",
    );
    sql(
      `\\set target_id ${platform.id}\n\\set confirm_target_id ${platform.id}\n\\set expected_admin_count ${count}\n${
        readFileSync(
          new URL("../admin/grant_platform_admin.sql", import.meta.url),
          "utf8",
        )
      }`,
    );
    const verified = await institution(platform, owner, "7D Verified");
    const pending = await institution(platform, owner, "7D Pending", "pending");
    const suspended = await institution(
      platform,
      owner,
      "7D Suspended",
      "suspended",
    );
    await rpc("set_institution_member", {
      p_institution: verified,
      p_member: issuer.id,
      p_role: "issuer",
    }, owner.token);
    const legacy = randomUUID();
    // A gateway 401 only proves JWT rejection, not that a restarted worker has
    // finished loading its imports. Warm the real authenticated handler with an
    // invalid JSON body: no reservation, document or publication is created.
    await until(
      async () => {
        const r = await fetch(
          `${local.API_URL}/functions/v1/issue-certificate`,
          {
            method: "POST",
            headers: {
              apikey: local.ANON_KEY,
              Authorization: `Bearer ${owner.token}`,
              "Content-Type": "application/json",
            },
            body: "{}",
            signal: AbortSignal.timeout(15000),
          },
        ).catch(() => null);
        if (!r) return false;
        await r.arrayBuffer();
        return r.status === 400;
      },
      "Authenticated issuance worker ready",
      60000,
    );
    sql(
      `INSERT INTO public.certificates(id,institution_id,holder_id,issued_by,title,credential_code) VALUES('${legacy}','${verified}','${holder.id}','${owner.id}','7D Legacy','${randomUUID()}');`,
    );
    return {
      local,
      platform,
      owner,
      holder,
      outsider,
      issuer,
      verified,
      pending,
      suspended,
      legacy,
      faultToken,
      json,
      rpc,
      user,
      issue,
      snapshot,
      expire,
      stored,
      close,
      stopRuntime: () => {
        terminate(runtime);
        rmSync(directory, { recursive: true, force: true });
      },
    };
  } catch (error) {
    await close();
    throw error;
  }
}
