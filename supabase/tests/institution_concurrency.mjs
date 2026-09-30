// Cross-platform, dependency-free concurrency test against a schema-only clone.
// Never commit fixtures in the application's database. Docker must be local.
import { spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const container = process.argv[2] ?? "supabase_db_certichain";
if (!/^supabase_db_[a-zA-Z0-9_-]+$/.test(container)) {
  throw new Error("Expected a local Supabase database container");
}
const database = `phase6_test_${randomBytes(8).toString("hex")}`;
const admin = "61000000-0000-4000-8000-000000000001";
const ownerA = "61000000-0000-4000-8000-000000000002";
const ownerB = "61000000-0000-4000-8000-000000000003";
const member = "61000000-0000-4000-8000-000000000004";
const sessions = new Set();

function sync(args, input) {
  const result = spawnSync("docker", ["exec", "-i", container, ...args], {
    input,
    encoding: "utf8",
    timeout: 30_000,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    throw new Error(result.error?.message ?? result.stderr);
  }
  return result.stdout.trim();
}

function sql(statement, db = database, user = "postgres") {
  return sync([
    "psql",
    "-X",
    "-qAt",
    "-U",
    user,
    "-d",
    db,
    "-v",
    "ON_ERROR_STOP=1",
  ], statement);
}

function session() {
  const child = spawn("docker", [
    "exec",
    "-i",
    container,
    "psql",
    "-X",
    "-qAt",
    "-U",
    "postgres",
    "-d",
    database,
    "-v",
    "ON_ERROR_STOP=1",
    "-v",
    "VERBOSITY=verbose",
  ], { stdio: ["pipe", "pipe", "pipe"] });
  let output = "";
  let errors = "";
  child.stdout.setEncoding("utf8").on("data", (data) => {
    output += data;
  });
  child.stderr.setEncoding("utf8").on("data", (data) => {
    errors += data;
  });
  // Resolve failures as values so an expected SQL rejection is never unhandled.
  const done = new Promise((resolve) => {
    child.on("error", (error) => resolve({ code: -1, errors: error.message }));
    child.on("close", (code) => {
      sessions.delete(child);
      resolve({ code, errors });
    });
  });
  sessions.add(child);
  return {
    send: (statement) => child.stdin.write(`${statement}\n`),
    end: (statement) => child.stdin.end(`${statement}\n`),
    done,
    async marker(marker) {
      for (let attempt = 0; attempt < 200; attempt++) {
        if (output.split(/\r?\n/).includes(marker)) return;
        if (child.exitCode !== null) {
          throw new Error(`Session ended before ${marker}: ${errors}`);
        }
        await delay(50);
      }
      throw new Error(`Timed out waiting for ${marker}: ${errors}`);
    },
  };
}

async function waitForLock() {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (
      sql(`SELECT count(*) FROM pg_stat_activity WHERE datname='${database}'
      AND application_name='phase6_second' AND wait_event_type='Lock';`) === "1"
    ) return;
    await delay(50);
  }
  throw new Error(
    "Second operation never waited on the first; concurrency was not exercised",
  );
}

const claims = (user) =>
  `SELECT set_config('request.jwt.claim.sub','${user}',true);
  SELECT set_config('request.jwt.claims','{"sub":"${user}","role":"authenticated"}',true);
  SET LOCAL ROLE authenticated;`;

async function race(
  label,
  isolation,
  operationA,
  operationB,
  expectedError,
  actor = admin,
  fixtureOwners = [ownerA, ownerB],
) {
  sql(`BEGIN; ${claims(admin)}
    SELECT public.create_institution('Synthetic Concurrency','${label}','${
    fixtureOwners[0]
  }');
    SELECT public.set_institution_member((SELECT id FROM public.institutions WHERE slug='${label}'),'${
    fixtureOwners[1]
  }','owner');
    COMMIT;`);
  const id = sql(`SELECT id FROM public.institutions WHERE slug='${label}';`);
  if (!/^[0-9a-f-]{36}$/.test(id)) throw new Error("Fixture creation failed");
  const first = session();
  const second = session();
  const api = !label.startsWith("cascade-");
  second.send(
    `BEGIN ISOLATION LEVEL ${isolation}; SET LOCAL statement_timeout='15s';
    SET LOCAL application_name='phase6_second'; ${api ? claims(actor) : ""}
    SELECT count(*) FROM public.institutions; SELECT 'SECOND_READY';`,
  );
  await second.marker("SECOND_READY"); // Establish a snapshot before the first write.
  first.send(
    `BEGIN ISOLATION LEVEL ${isolation}; SET LOCAL statement_timeout='15s';
    SET LOCAL application_name='phase6_first'; ${api ? claims(admin) : ""}
    ${operationA(id)} SELECT 'FIRST_CHANGED';`,
  );
  await first.marker("FIRST_CHANGED");
  second.end(`${operationB(id)} COMMIT;`);
  await waitForLock(); // Prove actual overlap, not merely sequential calls.
  first.end("COMMIT;");
  const a = await first.done;
  const b = await second.done;
  if (a.code !== 0) {
    throw new Error(`${label}: first transaction failed: ${a.errors}`);
  }
  if (b.code === 0 || !b.errors.includes(expectedError)) {
    throw new Error(
      `${label}: expected ${expectedError} rejection, got exit ${b.code}: ${b.errors}`,
    );
  }
  const owners = sql(
    `SELECT count(*) FROM public.institution_members WHERE institution_id='${id}' AND role='owner';`,
  );
  if (owners !== "1") {
    throw new Error(`${label}: owner invariant failed (${owners})`);
  }
  console.log(
    `PASS ${label}: overlap observed, second rejected with ${expectedError}, one owner remains`,
  );
}

async function emissionRace(
  label,
  action,
  mutation,
  isolation = "READ COMMITTED",
) {
  const id = sql(`BEGIN; ${claims(admin)}
    SELECT public.create_institution('Synthetic Issuance','${label}','${ownerB}'); COMMIT;`)
    .split(/\r?\n/).at(-1);
  sql(`BEGIN; ${claims(admin)}
    SELECT public.set_institution_status('${id}', 'verified');
    SELECT public.set_institution_member('${id}', '${ownerA}', 'issuer'); COMMIT;
    UPDATE auth.users SET email_confirmed_at=now() WHERE id='${member}';`);
  const key = "71000000-0000-4000-8000-000000000001";
  const reserve =
    `SELECT public.reserve_certificate_issuance('${id}', '${ownerA}', '${member}', '${key}', repeat('a',64), repeat('b',64), 'Synthetic Certificate');`;
  let operation = reserve;
  if (action === "publish") {
    const op = JSON.parse(sql(reserve));
    sql(
      `SELECT public.advance_certificate_issuance('${id}', '${op.operation_id}', '${op.lease_token}', 'validate', repeat('b',64));`,
    );
    operation =
      `SELECT public.advance_certificate_issuance('${id}', '${op.operation_id}', '${op.lease_token}', 'publish');`;
  }
  const first = session(), second = session();
  second.send(
    `BEGIN ISOLATION LEVEL ${isolation}; SET LOCAL statement_timeout='15s';
    SET LOCAL application_name='phase6_second'; SET LOCAL ROLE service_role;
    SELECT count(*) FROM public.institutions; SELECT 'SECOND_READY';`,
  );
  await second.marker("SECOND_READY");
  first.send(
    `BEGIN; ${claims(admin)} ${
      mutation === "membership"
        ? `SELECT public.remove_institution_member('${id}', '${ownerA}');`
        : `SELECT public.set_institution_status('${id}', 'suspended');`
    } SELECT 'FIRST_CHANGED';`,
  );
  await first.marker("FIRST_CHANGED");
  second.end(`${operation} COMMIT;`);
  await waitForLock();
  first.end("COMMIT;");
  const a = await first.done, b = await second.done;
  const expected = isolation === "READ COMMITTED" ? "42501" : "40001";
  if (a.code !== 0 || b.code === 0 || !b.errors.includes(expected)) {
    throw new Error(`${label}: authorization race failed`);
  }
  if (
    sql(
      `SELECT count(*) FROM public.certificates WHERE institution_id='${id}';`,
    ) !== "0"
  ) throw new Error(`${label}: unauthorized publication`);
  console.log(
    `PASS ${label}: institution lock wait observed; second rejected ${expected}`,
  );
}

try {
  const schema = sync([
    "pg_dump",
    "-U",
    "postgres",
    "-d",
    "postgres",
    "--schema-only",
    "--schema=public",
    "--schema=auth",
    "--schema=certichain_private",
  ]);
  sql(
    `CREATE DATABASE ${database} TEMPLATE template0;`,
    "postgres",
    "supabase_admin",
  );
  sql("DROP SCHEMA public;", database, "supabase_admin");
  sql(schema, database, "supabase_admin");
  sql(
    `INSERT INTO auth.users(id,raw_user_meta_data) SELECT id::uuid,jsonb_build_object('full_name','Synthetic Concurrency')
    FROM unnest(ARRAY['${admin}','${ownerA}','${ownerB}','${member}']) AS users(id);`,
  );
  const bootstrap = sync(
    [
      "psql",
      "-X",
      "-qAt",
      "-U",
      "postgres",
      "-d",
      database,
      "-v",
      `target_id=${admin}`,
      "-v",
      `confirm_target_id=${admin}`,
      "-v",
      "expected_admin_count=0",
    ],
    readFileSync(
      new URL("../admin/grant_platform_admin.sql", import.meta.url),
      "utf8",
    ),
  );
  if (!bootstrap.includes(`platform_admin_assigned|${admin}`)) {
    throw new Error("Bootstrap script did not confirm target");
  }
  const demo = sync(
    [
      "psql",
      "-X",
      "-qAt",
      "-U",
      "postgres",
      "-d",
      database,
      "-v",
      `admin_id=${admin}`,
      "-v",
      `confirm_admin_id=${admin}`,
      "-v",
      "expected_admin_count=1",
      "-v",
      `owner_id=${ownerA}`,
      "-v",
      `member_id=${member}`,
    ],
    readFileSync(
      new URL("../admin/demo_institution.sql", import.meta.url),
      "utf8",
    ),
  );
  for (
    const stage of [
      "pending",
      "verified",
      "suspended",
      "issuer",
      "admin",
      "all changes rolled back",
    ]
  ) {
    if (!demo.includes(stage)) {
      throw new Error(`Walkthrough script missed ${stage}`);
    }
  }
  if (sql("SELECT count(*) FROM public.institutions;") !== "0") {
    throw new Error("Walkthrough did not roll back");
  }
  console.log(
    "PASS: actual bootstrap and walkthrough scripts; confirmed target and rollback checked",
  );

  const removeA = (id) =>
    `SELECT public.remove_institution_member('${id}','${ownerA}');`;
  const removeB = (id) =>
    `SELECT public.remove_institution_member('${id}','${ownerB}');`;
  const demoteA = (id) =>
    `SELECT public.set_institution_member('${id}','${ownerA}','admin');`;
  const demoteB = (id) =>
    `SELECT public.set_institution_member('${id}','${ownerB}','issuer');`;
  await race("rpc-delete-delete", "READ COMMITTED", removeA, removeB, "23514");
  await race("rpc-demote-demote", "READ COMMITTED", demoteA, demoteB, "23514");
  await race("rpc-delete-demote", "READ COMMITTED", removeA, demoteB, "23514");
  await race(
    "rpc-repeatable-read",
    "REPEATABLE READ",
    removeA,
    removeB,
    "40001",
  );
  await race("rpc-serializable", "SERIALIZABLE", demoteA, demoteB, "40001");
  await race(
    "rpc-revoked-authority",
    "READ COMMITTED",
    demoteB,
    (id) =>
      `SELECT public.set_institution_member('${id}','${member}','issuer');`,
    "42501",
    ownerB,
  );

  // Auth cascades use trusted SQL and new synthetic identities for each run.
  // Their deletion must still be unable to orphan an institution.
  for (const isolation of ["READ COMMITTED", "REPEATABLE READ"]) {
    // Cascade actors have no memberships in other fixtures.
    const ids = [
      randomBytes(16).toString("hex"),
      randomBytes(16).toString("hex"),
    ]
      .map((hex) =>
        `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4000-8000-${hex.slice(20)}`
      );
    sql(`INSERT INTO auth.users(id,raw_user_meta_data) VALUES
      ('${ids[0]}','{"full_name":"Synthetic Cascade"}'),('${
      ids[1]
    }','{"full_name":"Synthetic Cascade"}');`);
    const label = isolation === "READ COMMITTED"
      ? "cascade-read-committed"
      : "cascade-repeatable-read";
    await race(
      label,
      isolation,
      () => `DELETE FROM auth.users WHERE id='${ids[0]}';`,
      () => `DELETE FROM auth.users WHERE id='${ids[1]}';`,
      isolation === "READ COMMITTED" ? "23514" : "40001",
      admin,
      ids,
    );
  }
  console.log(
    "PASS: 8 concurrency scenarios; schema clone contains no application data",
  );
  for (const action of ["reserve", "publish"]) {
    for (const mutation of ["membership", "status"]) {
      await emissionRace(`issuance-${action}-${mutation}`, action, mutation);
    }
  }
  await emissionRace(
    "issuance-reserve-repeatable",
    "reserve",
    "status",
    "REPEATABLE READ",
  );
  await emissionRace(
    "issuance-publish-serializable",
    "publish",
    "membership",
    "SERIALIZABLE",
  );
  console.log("PASS: 6 additional issuance authorization races");
} finally {
  for (const child of sessions) child.kill();
  // Only this randomly named disposable database is ever dropped.
  if (!/^phase6_test_[a-f0-9]{16}$/.test(database)) {
    throw new Error("Unsafe cleanup target");
  }
  sql(
    `DROP DATABASE IF EXISTS ${database} WITH (FORCE);`,
    "postgres",
    "supabase_admin",
  );
}
