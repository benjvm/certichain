import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { sql } from "../scripts/local_supabase.mjs";
import { until } from "./local_issuance_fixture.mjs";
import type { phase9dEnvironment } from "./phase9d_environment.ts";

export async function phase10Concurrency(
  env: Awaited<ReturnType<typeof phase9dEnvironment>>,
  check: (v: unknown, label: string) => void,
) {
  const { f } = env;
  const actor = await f.user("revocation-lock-race");
  const project = /^project_id\s*=\s*"([^"]+)"/m.exec(
    readFileSync("supabase/config.toml", "utf8"),
  )![1];
  async function member() {
    await f.rpc("set_institution_member", {
      p_institution: f.verified,
      p_member: actor.id,
      p_role: "admin",
    }, f.owner.token);
  }
  async function published() {
    const r = await f.issue(f.owner, {
      institution_id: f.verified,
      holder_id: f.holder.id,
      idempotency_key: crypto.randomUUID(),
      title: "Synthetic SQL lock race",
    });
    if (r.status !== 201) throw new Error("Lock race publication failed");
    return r.data.certificate_id as string;
  }
  async function transaction(body: string) {
    const child = spawn("docker", [
      "exec",
      "-i",
      `supabase_db_${project}`,
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
    let marker = false, failed = false;
    const done = new Promise<void>((resolve, reject) => {
      child.on("error", () => {
        failed = true;
        reject(new Error("Owned SQL session failed"));
      });
      child.on("close", (code) => {
        if (code !== 0) {
          failed = true;
          reject(new Error("Owned SQL transaction failed"));
        } else resolve();
      });
    });
    child.stdout.on("data", (data) => {
      if (String(data).includes("PHASE10_LOCK_HELD")) marker = true;
    });
    child.stderr.on(
      "data",
      () => {/* No SQL error/PII/parameters in artifacts. */},
    );
    child.stdin.write(`BEGIN;\n${body}\nSELECT 'PHASE10_LOCK_HELD';\n`);
    try {
      await until(
        () => {
          if (failed) throw new Error("SQL lock session failed");
          return marker;
        },
        "Owned SQL transaction acquired parent",
        10000,
      );
    } catch (e) {
      child.stdin.end("ROLLBACK;\n");
      await done.catch(() => {});
      throw e;
    }
    return {
      commit: async () => {
        child.stdin.end("COMMIT;\n");
        await done;
      },
      rollback: async () => {
        if (child.exitCode === null) {
          child.stdin.end("ROLLBACK;\n");
          await done;
        }
      },
    };
  }
  await member();
  const first = await published();
  const removed = await transaction(
    `SELECT id FROM public.institutions WHERE id='${f.verified}' FOR UPDATE; DELETE FROM public.institution_members WHERE institution_id='${f.verified}' AND user_id='${actor.id}';`,
  );
  try {
    const pending = f.json("/functions/v1/revoke-certificate", actor.token, {
      certificate_id: first,
      idempotency_key: crypto.randomUUID(),
      reason: "Private concurrent reason",
    });
    await until(
      () =>
        Number(
          sql(
            "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%request_certificate_revocation%'",
          ),
        ) > 0,
      "Revocation waits behind membership transaction",
      10000,
    );
    await removed.commit();
    check(
      (await pending).response.status === 404 &&
        sql(`SELECT status FROM public.certificates WHERE id='${first}'`) ===
          "active",
      "10 SQL lock race membership removal first denies request atomically",
    );
  } finally {
    await removed.rollback();
  }
  await member();
  const second = await published();
  const accepted = await transaction(
    `SELECT public.request_certificate_revocation('${actor.id}','${second}',gen_random_uuid(),'Private concurrent reason');`,
  );
  try {
    const pending = f.rpc("remove_institution_member", {
      p_institution: f.verified,
      p_member: actor.id,
    }, f.owner.token);
    await until(
      () =>
        Number(
          sql(
            "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%remove_institution_member%'",
          ),
        ) > 0,
      "Membership removal waits behind revocation decision",
      10000,
    );
    await accepted.commit();
    await pending;
    check(
      sql(`SELECT status FROM public.certificates WHERE id='${second}'`) ===
          "revoked" &&
        sql(
            `SELECT count(*) FROM certichain_private.certificate_revocations WHERE certificate_id='${second}' AND requested_by='${actor.id}'`,
          ) === "1",
      "10 SQL lock race accepted revocation survives subsequent member removal with original audit",
    );
    check(
      (await f.json("/functions/v1/revocation-progress", actor.token, {
        certificate_id: second,
      })).response.status === 404,
      "10 removed actor cannot recover private result even after accepted race",
    );
  } finally {
    await accepted.rollback();
  }
  const certificate = await published();
  const anchor = await f.json(
    "/functions/v1/anchor-certificate",
    f.owner.token,
    {
      certificate_id: certificate,
      idempotency_key: crypto.randomUUID(),
    },
  );
  await env.run(anchor.data.operation_id);
  await env.run(anchor.data.operation_id);
  const decision = await f.json(
    "/functions/v1/revoke-certificate",
    f.owner.token,
    {
      certificate_id: certificate,
      idempotency_key: crypto.randomUUID(),
      reason: "Private worker race",
    },
  );
  const operation = decision.data.synchronization[0].operation_id as string;
  let stored!: () => void, resume!: () => void;
  const reached = new Promise<void>((resolve) => {
    stored = resolve;
  });
  const gate = new Promise<void>((resolve) => {
    resume = resolve;
  });
  const firstWorker = env.run(operation, false, {
    barrier: async (point) => {
      if (point === "stored") {
        stored();
        await gate;
      }
    },
  });
  try {
    await Promise.race([
      reached,
      firstWorker.then(() => {
        throw new Error("Worker exited before durable barrier");
      }),
    ]);
    check(
      await env.run(operation) === "busy",
      "10C concurrent revoke worker cannot acquire live lease",
    );
    sql(
      `UPDATE certichain_private.blockchain_operations SET lease_until=clock_timestamp()-interval '1 second' WHERE id='${operation}'`,
    );
    await env.run(operation);
    await env.run(operation);
  } finally {
    resume();
  }
  await firstWorker;
  check(
    sql(
          `SELECT state='confirmed' FROM certichain_private.blockchain_operations WHERE id='${operation}'`,
        ) === "t" &&
      sql(
          `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${operation}'`,
        ) === "1",
    "10C expired worker resumes behind new generation without duplicating revoke or overwriting confirmation",
  );
}
