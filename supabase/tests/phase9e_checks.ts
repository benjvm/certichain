import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { sql } from "../scripts/local_supabase.mjs";
import {
  commitment,
  digest,
} from "../functions/_shared/blockchain/application/commitment.ts";
import {
  dbHex,
  type Job,
} from "../functions/_shared/blockchain/application/coordinator.ts";
import { RegistryError } from "../functions/_shared/blockchain/domain/registry.ts";
import type { phase9dEnvironment } from "./phase9d_environment.ts";

export async function phase9eChecks(
  environment: Awaited<ReturnType<typeof phase9dEnvironment>>,
  check: (value: unknown, label: string) => void,
) {
  const { f: fixture, backend } = environment;
  const issued = await fixture.issue(fixture.owner, {
    institution_id: fixture.verified,
    holder_id: fixture.holder.id,
    idempotency_key: crypto.randomUUID(),
    title: "Synthetic 9E recovery",
  });
  check(issued.status === 201, "9E synthetic recovery publication");
  const certificate = issued.data.certificate_id as string;
  if (!/^[0-9a-fixture-]{36}$/.test(certificate)) {
    throw new Error("Invalid owned certificate");
  }
  const input = {
    certificate_id: certificate,
    idempotency_key: crypto.randomUUID(),
  };
  const replies = await Promise.all(
    Array.from(
      { length: 3 },
      () =>
        fixture.json(
          "/functions/v1/anchor-certificate",
          fixture.owner.token,
          input,
        ),
    ),
  );
  const accepted = replies.filter((reply) =>
    [200, 202].includes(reply.response.status)
  );
  check(
    accepted.length > 0 &&
      replies.every((reply) => [200, 202, 409].includes(reply.response.status)),
    "concurrent explicit requests have bounded durable responses",
  );
  const operation = accepted[0].data.operation_id as string;
  if (!/^[0-9a-fixture-]{36}$/.test(operation)) {
    throw new Error("Invalid owned operation");
  }
  const retry = await fixture.json(
    "/functions/v1/anchor-certificate",
    fixture.owner.token,
    input,
  );
  check(
    retry.data.operation_id === operation &&
      accepted.every((reply) => reply.data.operation_id === operation),
    "discarded request response and explicit retry recover one operation",
  );
  const claim = await backend.rpc<Job>("blockchain_claim", {
    p_operation: operation,
  });
  sql(
    `UPDATE certichain_private.blockchain_operations SET lease_until=clock_timestamp()-interval '1 second' WHERE id='${operation}';`,
  );
  const newer = await backend.rpc<Job>("blockchain_claim", {
    p_operation: operation,
  });
  let stale = false;
  try {
    await backend.rpc("blockchain_update_job", {
      p_operation: operation,
      p_token: claim.operation.lease_token,
      p_generation: claim.operation.generation,
      p_action: "release",
    });
  } catch (error) {
    stale = error instanceof RegistryError && error.code === "busy";
  }
  check(
    stale &&
      BigInt(newer.operation.generation) > BigInt(claim.operation.generation),
    "expired lease fences stale actor with real SQL CAS",
  );
  sql(
    `UPDATE certichain_private.blockchain_operations SET lease_until=clock_timestamp()-interval '1 second' WHERE id='${operation}';`,
  );
  let crashed = false;
  try {
    await environment.run(operation, false, {
      barrier: (point) =>
        point === "broadcast"
          ? Promise.reject(new Error("HARNESS_CRASH"))
          : Promise.resolve(),
    });
  } catch (error) {
    crashed = error instanceof Error && error.message === "HARNESS_CRASH";
  }
  check(
    crashed,
    "worker interrupted after real broadcast before SQL acknowledgement",
  );
  const before = sql(
    `SELECT certichain_private.blockchain_job('${operation}')`,
  );
  sql(
    `UPDATE certichain_private.blockchain_operations SET lease_until=clock_timestamp()-interval '1 second' WHERE id='${operation}';`,
  );
  check(
    environment.restartWorker(operation) === "confirmed",
    "separate production CLI worker process recovers persisted broadcast after interruption",
  );
  await environment.run(operation);
  const job = JSON.parse(
    sql(`SELECT certichain_private.blockchain_job('${operation}')`),
  ) as Job;
  check(
    job.operation.state === "confirmed" && job.attempts.length === 1 &&
      job.attempts[0].transaction_hash ===
        (JSON.parse(before) as Job).attempts[0].transaction_hash,
    "fresh worker reconciles persisted broadcast without another signature",
  );
  const progress = await fixture.json(
    "/functions/v1/anchor-progress",
    fixture.owner.token,
    { operation_id: operation },
  );
  check(
    progress.response.status === 200 && progress.data.status === "confirmed",
    "9D client progress contract reads recovered 9C ledger",
  );
  for (
    const actor of [
      fixture.holder,
      fixture.outsider,
      fixture.platform,
      fixture.issuer,
    ]
  ) {
    check(
      (await fixture.json("/functions/v1/anchor-progress", actor.token, {
        operation_id: operation,
      })).response.status === 403,
      "foreign holder platform or removed member denied private progress",
    );
  }
  await fixture.rpc("set_institution_member", {
    p_institution: fixture.pending,
    p_member: fixture.outsider.id,
    p_role: "issuer",
  }, fixture.owner.token);
  check(
    (await fixture.json(
      "/functions/v1/certificate-opening",
      fixture.outsider.token,
      {
        certificate_id: certificate,
      },
    )).response.status === 404,
    "another institution membership does not grant opening",
  );
  check(
    (await fixture.json(
      "/functions/v1/anchor-progress",
      fixture.outsider.token,
      {
        operation_id: operation,
      },
    )).response.status === 403,
    "another institution membership does not grant progress",
  );
  await fixture.rpc("set_institution_status", {
    p_institution: fixture.verified,
    p_status: "suspended",
  }, fixture.platform.token);
  check(
    (await fixture.json("/functions/v1/anchor-progress", fixture.owner.token, {
      operation_id: operation,
    })).response.status === 403,
    "suspended institution member denied private progress",
  );
  await fixture.rpc("set_institution_status", {
    p_institution: fixture.verified,
    p_status: "pending",
  }, fixture.platform.token);
  await fixture.rpc("set_institution_status", {
    p_institution: fixture.verified,
    p_status: "verified",
  }, fixture.platform.token);
  const project = /^project_id\s*=\s*"([^"]+)"/m.exec(
    readFileSync("supabase/config.toml", "utf8"),
  )![1];
  const database = `phase9e_${crypto.randomUUID().replaceAll("-", "")}`;
  const dump = `/tmp/${database}.dump`, bucket = database;
  const docker = (...args: string[]) => {
    const result = spawnSync("docker", [
      "exec",
      `supabase_db_${project}`,
      ...args,
    ], { encoding: "utf8", windowsHide: true, timeout: 60000 });
    if (result.status !== 0) {
      const firstLine = (result.stderr || result.stdout).split(/\r?\n/)[0];
      const diagnostic =
        /^(pg_dump:|Error response from daemon:|OCI runtime|sh:|rm:|docker:)/
            .test(firstLine)
          ? firstLine.replace(
            /0x[0-9a-f]+|\\x[0-9a-f]+|[0-9a-f]{64,}|eyJ[A-Za-z0-9_.-]+/gi,
            "[redacted]",
          ).replace(/"[^"]*"|'[^']*'/g, "[quoted]").replace(
            /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g,
            "[email]",
          ).slice(0, 300)
          : "unclassified local command failure";
      console.log(
        JSON.stringify({
          stage: "private-restore",
          command: args[0],
          result: "FAIL",
          exit: result.status,
          diagnostic,
          category: /no space left/i.test(result.stderr)
            ? "storage_capacity"
            : /not running|No such container/i.test(result.stderr)
            ? "container_unavailable"
            : /permission denied/i.test(result.stderr)
            ? "permission"
            : /cannot connect|error during connect/i.test(result.stderr)
            ? "docker_unavailable"
            : "other",
          timeout: result.error != null && "code" in result.error &&
            result.error.code === "ETIMEDOUT",
        }),
      );
      throw new Error("Isolated private restore command failed");
    }
    return result.stdout.trim();
  };
  const storage = async (
    path: string,
    method = "GET",
    body?: BodyInit,
    token = fixture.local.SERVICE_ROLE_KEY,
  ) => {
    return await fetch(`${fixture.local.API_URL}/storage/v1/${path}`, {
      method,
      body,
      headers: {
        apikey: fixture.local.ANON_KEY,
        Authorization: `Bearer ${token}`,
        "content-type": body instanceof Uint8Array
          ? "application/pdf"
          : "application/json",
      },
      signal: AbortSignal.timeout(15000),
    });
  };
  const originalPath = `${fixture.verified}/${certificate}.pdf`;
  const backupBytes = await backend.pdf(originalPath);
  const requireCleanup = (response: Response, label: string) => {
    if (!response.ok) {
      console.log(
        JSON.stringify({
          stage: label,
          result: "FAIL",
          status: response.status,
        }),
      );
      throw new Error(label);
    }
  };
  let bucketCreated = false, originalRemoved = false;
  try {
    docker(
      "sh",
      "-c",
      `umask 077; pg_dump -U postgres -Fc -f ${dump} postgres`,
    );
    docker("createdb", "-U", "postgres", database);
    docker(
      "pg_restore",
      "-U",
      "supabase_admin",
      "--exit-on-error",
      "--no-owner",
      "-d",
      database,
      dump,
    );
    const restored = JSON.parse(
      docker(
        "psql",
        "-X",
        "-U",
        "supabase_admin",
        "-d",
        database,
        "-Atc",
        `SELECT certichain_private.blockchain_job('${operation}')`,
      ),
    ) as Job;
    check(
      JSON.stringify(restored) === JSON.stringify(job),
      "isolated PostgreSQL restore retains private anchor operation attempts and nonce context",
    );
    const nonceQuery =
      `SELECT coalesce(jsonb_agg(to_jsonb(n) ORDER BY n.signer),'[]'::jsonb) FROM certichain_private.blockchain_signer_nonces n WHERE deployment_id='${job.deployment.id}'`;
    check(
      docker(
        "psql",
        "-X",
        "-U",
        "supabase_admin",
        "-d",
        database,
        "-Atc",
        nonceQuery,
      ) === sql(nonceQuery),
      "restored signer ledger retains exact nonces and reservations without reconstruction",
    );
    const created = await storage(
      "bucket",
      "POST",
      JSON.stringify({
        id: bucket,
        name: bucket,
        public: false,
        allowed_mime_types: ["application/pdf"],
        file_size_limit: 8388608,
      }),
    );
    check(created.ok, "isolated private Storage restore destination created");
    await created.body?.cancel();
    bucketCreated = true;
    const uploaded = await storage(
      `object/${bucket}/${certificate}.pdf`,
      "POST",
      backupBytes,
    );
    check(
      uploaded.ok,
      "exact backup bytes restored through Storage API without upsert",
    );
    await uploaded.body?.cancel();
    const downloaded = await storage(
      `object/authenticated/${bucket}/${certificate}.pdf`,
    );
    check(
      downloaded.ok,
      "private recovered bytes retrievable only through authorized Storage API",
    );
    const recoveredBytes = new Uint8Array(await downloaded.arrayBuffer());
    const anchor = restored.anchor!;
    const recalculated = await commitment(
      anchor.credential_code_snapshot,
      dbHex(restored.binding.issuer_id),
      await digest(recoveredBytes),
      dbHex(anchor.salt),
    );
    const chain = await environment.registry.read(
      recalculated.K,
      (await environment.registry.validateDeployment(environment.deployment))
        .head,
    );
    check(
      await digest(recoveredBytes) === dbHex(anchor.document_sha256) &&
        recalculated.K === dbHex(anchor.certificate_key) &&
        recalculated.C === dbHex(anchor.commitment) &&
        chain?.C === recalculated.C &&
        chain.I === dbHex(restored.binding.issuer_id),
      "restored private PDF and H K I C S agree with original canonical anchoring",
    );
    for (const token of [fixture.local.ANON_KEY, fixture.holder.token]) {
      const denied = await storage(
        `object/authenticated/${bucket}/${certificate}.pdf`,
        "GET",
        undefined,
        token,
      );
      check(
        !denied.ok,
        "restored private destination denies direct client reads",
      );
      await denied.body?.cancel();
    }
    const removed = await storage(
      "object/certificates",
      "DELETE",
      JSON.stringify({ prefixes: [originalPath] }),
    );
    check(
      removed.ok,
      "only owned synthetic original removed for recovery exercise",
    );
    await removed.body?.cancel();
    originalRemoved = true;
    check(
      (await fixture.json(
        "/functions/v1/certificate-pdf",
        fixture.holder.token,
        {
          certificate_id: certificate,
        },
      )).response.status === 404,
      "missing private bytes gives recoverable document failure",
    );
    const replaced = await storage(
      `object/certificates/${originalPath}`,
      "POST",
      recoveredBytes,
    );
    check(
      replaced.ok,
      "original synthetic environment restores same immutable PDF bytes",
    );
    await replaced.body?.cancel();
    originalRemoved = false;
    check(
      (await fixture.json(
        "/functions/v1/certificate-pdf",
        fixture.holder.token,
        {
          certificate_id: certificate,
        },
      )).response.status === 200,
      "holder document capability recovers with existing certificate and ledger",
    );
    const opened = await fixture.json(
      "/functions/v1/certificate-opening",
      fixture.holder.token,
      { certificate_id: certificate },
    );
    check(
      opened.response.status === 200 &&
        opened.data.salt === dbHex(anchor.salt) &&
        opened.data.document_sha256 === dbHex(anchor.document_sha256),
      "client opening retains original salt and hash after private restore",
    );
    await environment.run(operation);
    check(
      sql(
        `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${operation}'`,
      ) === "1",
      "restore reconciliation produces no duplicate anchor or attempt",
    );
  } finally {
    try {
      if (originalRemoved) {
        const response = await storage(
          `object/certificates/${originalPath}`,
          "POST",
          backupBytes,
        );
        requireCleanup(response, "Owned original restore cleanup failed");
        await response.body?.cancel();
      }
      if (bucketCreated) {
        const empty = await storage(`bucket/${bucket}/empty`, "POST", "{}");
        requireCleanup(empty, "Owned restore bucket cleanup failed");
        await empty.body?.cancel();
        const removed = await storage(`bucket/${bucket}`, "DELETE");
        requireCleanup(removed, "Owned restore bucket deletion failed");
        await removed.body?.cancel();
      }
    } finally {
      try {
        docker("dropdb", "-U", "postgres", "--if-exists", database);
      } finally {
        docker("rm", "-f", dump);
      }
    }
  }
}
