import { handler, normalizeReason } from "./handler.ts";
import {
  command,
  type Job,
} from "../_shared/blockchain/application/coordinator.ts";
const id = "00112233-4455-6677-8899-aabbccddeeff";
const config = {
  url: "http://backend.invalid",
  anonKey: "public",
  serviceKey: "technical",
};
function equal(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error("Assertion failed");
  }
}
function request(body: BodyInit, authorization = "Bearer synthetic") {
  return new Request("http://edge.invalid", {
    method: "POST",
    headers: {
      authorization,
      "content-type": "application/json",
    },
    body,
  });
}
for (
  const reason of ["", " \n ", "a".repeat(501), "\u0000", "\ud800", 42, null]
) {
  Deno.test(`reason rejects ${typeof reason} ${typeof reason === "string" ? reason.length : 0}`, () => {
    let rejected = false;
    try {
      normalizeReason(reason);
    } catch {
      rejected = true;
    }
    equal(rejected, true);
  });
}
Deno.test("private reason canonical Unicode/newline, no HTML execution/interpretation", () => {
  equal(
    normalizeReason("  Revisio\u0301n\r\nprivada\r  "),
    "Revisión\nprivada",
  );
  equal(
    normalizeReason("<script>private text</script>"),
    "<script>private text</script>",
  );
  equal(normalizeReason("🙂".repeat(500)), "🙂".repeat(500));
});
for (
  const body of [
    "[]",
    "{}",
    `{"certificate_id":"${id}","idempotency_key":"${id}","reason":"a","actor":"${id}"}`,
    `{"certificate_id":"${id}","idempotency_key":"${id}","reason":"a","re\\u0061son":"b"}`,
  ]
) {
  Deno.test("closed revoke input rejects ambiguous authority/duplicates before SQL", async () => {
    const saved = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      return Promise.resolve(Response.json({ id, is_anonymous: false }));
    };
    try {
      const r = await handler(config)(request(body));
      equal(r.status, 400);
      equal(calls, 1);
      equal(r.headers.get("cache-control"), "no-store");
    } finally {
      globalThis.fetch = saved;
    }
  });
}
Deno.test("202 accepts SQL only, actor comes from real Auth response and no EVM access", async () => {
  const saved = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = (url, init) => {
    calls++;
    if (String(url).endsWith("/auth/v1/user")) {
      return Promise.resolve(Response.json({ id, is_anonymous: false }));
    }
    equal(
      String(url),
      config.url + "/rest/v1/rpc/request_certificate_revocation",
    );
    equal(JSON.parse(init!.body as string), {
      p_actor: id,
      p_certificate: id,
      p_key: id,
      p_reason: "Revisión",
    });
    return Promise.resolve(Response.json({
      certificate_id: id,
      request_id: id,
      status: "revoked",
      revoked_at: "2026-10-15T00:00:00Z",
      reason: "Revisión",
      synchronization: [],
      created: true,
    }));
  };
  try {
    const r = await handler(config)(
      request(
        JSON.stringify({
          certificate_id: id,
          idempotency_key: id,
          reason: " Revisio\u0301n ",
        }),
      ),
    );
    equal(r.status, 202);
    equal((await r.json()).created, undefined);
    equal(calls, 2);
  } finally {
    globalThis.fetch = saved;
  }
});
Deno.test("progress and retry errors are closed, foreign and absent share 404", async () => {
  const saved = globalThis.fetch;
  try {
    for (const code of ["PT404", "42501", "23505", "PT409", "XX000"]) {
      globalThis.fetch = (url) =>
        Promise.resolve(
          String(url).endsWith("/auth/v1/user")
            ? Response.json({ id, is_anonymous: false })
            : Response.json({ code, message: "PRIVATE upstream reason" }, {
              status: 400,
            }),
        );
      const r = await handler(config, "progress")(
        request(JSON.stringify({ certificate_id: id })),
      );
      equal(
        r.status,
        ["PT404", "42501"].includes(code)
          ? 404
          : code === "23505" || code === "PT409"
          ? 409
          : 503,
      );
      equal((await r.text()).includes("PRIVATE"), false);
    }
  } finally {
    globalThis.fetch = saved;
  }
});
Deno.test("coordinator maps revoke to the same K with no private reason in command", () => {
  const job = {
    operation: { kind: "revoke" },
    anchor: { certificate_key: "\\x" + "12".repeat(32) },
    binding: { issuer_id: "\\x" + "34".repeat(32) },
  } as Job;
  equal(command(job), { kind: "revoke", K: "0x" + "12".repeat(32) });
});

const valid = {
  certificate_id: id,
  request_id: id,
  status: "revoked",
  revoked_at: "2026-10-15T00:00:00.123456+00:00",
  reason: "Private text",
  synchronization: [{ operation_id: id, status: "requested" }],
};
const actions = ["request", "progress", "reauthorize"] as const;
function bodyFor(action: typeof actions[number]) {
  return JSON.stringify(
    action === "request"
      ? {
        certificate_id: id.toUpperCase(),
        idempotency_key: id.toUpperCase(),
        reason: "Private text",
      }
      : action === "progress"
      ? { certificate_id: id.toUpperCase() }
      : { operation_id: id.toUpperCase() },
  );
}
async function mocked(
  run: () => Promise<void>,
  rpcValue: unknown = { ...valid, created: false },
  auth: () => Response | Promise<Response> = () =>
    Response.json({ id, is_anonymous: false }),
) {
  const saved = globalThis.fetch;
  globalThis.fetch = (url, init) => {
    if (String(url).endsWith("/auth/v1/user")) {
      equal(new Headers(init?.headers).get("apikey"), config.anonKey);
      return Promise.resolve().then(auth);
    }
    const args = JSON.parse(init!.body as string);
    equal(args.p_actor, id);
    for (const key of ["p_certificate", "p_operation", "p_key"]) {
      if (key in args) equal(args[key], id);
    }
    return Promise.resolve(Response.json(rpcValue));
  };
  try {
    await run();
  } finally {
    globalThis.fetch = saved;
  }
}
for (const action of actions) {
  Deno.test(`${action}: closed output strips private RPC additions at both levels and normalizes input UUID`, () =>
    mocked(async () => {
      const r = await handler(config, action)(request(bodyFor(action)));
      equal(r.status, 200);
      equal(r.headers.get("cache-control"), "no-store");
      equal(await r.json(), valid);
    }, {
      ...valid,
      created: action !== "request",
      token: "PRIVATE",
      ledger: { raw: "PRIVATE" },
      synchronization: [{
        ...valid.synchronization[0],
        nonce: "PRIVATE",
        salt: "PRIVATE",
      }],
    }));

  for (
    const [name, auth, expected] of [
      [
        "invalid/expired",
        () => Response.json({ message: "PRIVATE" }, { status: 401 }),
        401,
      ],
      ["anonymous", () => Response.json({ id, is_anonymous: true }), 401],
      [
        "unavailable",
        () => Response.json({ message: "PRIVATE" }, { status: 503 }),
        503,
      ],
      ["throttled", () => Response.json({}, { status: 429 }), 503],
      ["network failure", () => {
        throw new Error("PRIVATE");
      }, 503],
      ["malformed Auth", () => new Response("PRIVATE"), 503],
    ] as const
  ) {
    Deno.test(`${action}: Auth ${name}`, () =>
      mocked(
        async () => {
          const r = await handler(config, action)(request(bodyFor(action)));
          equal(r.status, expected);
          equal(r.headers.get("cache-control"), "no-store");
          equal(await r.json(), {
            error: expected === 401 ? "unauthenticated" : "temporary_failure",
          });
        },
        undefined,
        auth,
      ));
  }

  Deno.test(`${action}: missing bearer rejected before Auth`, () =>
    mocked(
      async () => {
        const r = await handler(config, action)(request(bodyFor(action), ""));
        equal(r.status, 401);
        equal(r.headers.get("cache-control"), "no-store");
      },
      undefined,
      () => {
        throw new Error("Auth must not run");
      },
    ));

  for (
    const malformed of [
      null,
      [],
      "PRIVATE",
      {},
      { ...valid, certificate_id: "PRIVATE" },
      { ...valid, request_id: "PRIVATE" },
      { ...valid, status: "confirmed" },
      { ...valid, revoked_at: "2026-02-30T00:00:00Z" },
      { ...valid, revoked_at: null },
      { ...valid, reason: "\ud800" },
      { ...valid, reason: " " },
      { ...valid, reason: "not canonical\r\n" },
      { ...valid, reason: null },
      { ...valid, synchronization: null },
      { ...valid, synchronization: [null] },
      { ...valid, synchronization: [{ operation_id: id, status: "PRIVATE" }] },
      { ...valid, synchronization: [{ status: "requested" }] },
      {
        ...valid,
        synchronization: [valid.synchronization[0], valid.synchronization[0]],
      },
    ]
  ) {
    Deno.test(`${action}: malformed RPC is controlled and never echoed`, () =>
      mocked(async () => {
        const r = await handler(config, action)(request(bodyFor(action)));
        equal(r.status, 503);
        equal(r.headers.get("cache-control"), "no-store");
        equal(await r.json(), { error: "temporary_failure" });
      }, malformed));
  }

  Deno.test(`${action}: historical null audit remains null`, () =>
    mocked(async () => {
      const r = await handler(config, action)(request(bodyFor(action)));
      equal(r.status, 200);
      equal(await r.json(), { ...valid, request_id: null, reason: null });
    }, { ...valid, request_id: null, reason: null, created: false }));

  const correct = bodyFor(action);
  const duplicateKey = action === "reauthorize"
    ? "operation_id"
    : "certificate_id";
  for (
    const bad of [
      "null",
      "[]",
      "{}",
      correct.replace(id.toUpperCase(), "bad-uuid"),
      correct.slice(0, -1) + ',"actor":"forged"}',
      correct.slice(0, -1) + `,"${duplicateKey}":"${id}"}`,
      correct.slice(0, -1) +
      `,"${duplicateKey.replace("i", "\\u0069")}":"${id}"}`,
      correct.replace(`"${id.toUpperCase()}"`, "42"),
      correct.replace(id.toUpperCase(), id + "\\n"),
      new Uint8Array([0x7b, 0xff, 0x7d]),
    ]
  ) {
    Deno.test(`${action}: closed input types UUID duplicates and UTF-8`, () =>
      mocked(async () => {
        const r = await handler(config, action)(request(bad));
        equal(r.status, 400);
        equal(r.headers.get("cache-control"), "no-store");
        equal(await r.json(), { error: "invalid_input" });
      }));
  }
  Deno.test(`${action}: 8192 bytes accepted, 8193 rejected`, () =>
    mocked(async () => {
      for (const size of [8192, 8193]) {
        const r = await handler(config, action)(
          request(correct.padEnd(size, " ")),
        );
        equal(r.status, size === 8192 ? 200 : 413);
        equal(r.headers.get("cache-control"), "no-store");
      }
    }));
}

Deno.test("progress: active certificate preserves nullable fields without a decision", () =>
  mocked(async () => {
    const r = await handler(config, "progress")(request(bodyFor("progress")));
    equal(r.status, 200);
    equal(await r.json(), {
      ...valid,
      status: "active",
      request_id: null,
      reason: null,
      revoked_at: null,
      synchronization: [],
    });
  }, {
    ...valid,
    status: "active",
    request_id: null,
    reason: null,
    revoked_at: null,
    synchronization: [],
  }));

Deno.test("request: missing or malformed created and wrong certificate fail closed", async () => {
  for (
    const value of [
      valid,
      { ...valid, created: "true" },
      { ...valid, created: true, request_id: null, reason: null },
      { ...valid, created: true, reason: "Wrong reason" },
      {
        ...valid,
        created: true,
        certificate_id: crypto.randomUUID(),
      },
    ]
  ) {
    await mocked(async () => {
      const r = await handler(config)(request(bodyFor("request")));
      equal(r.status, 503);
    }, value);
  }
});

Deno.test("body read deadline is temporary 503 with no-store", () =>
  mocked(async () => {
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      cancel() {
        cancelled = true;
      },
    });
    const r = await handler(config)(request(body));
    equal(r.status, 503);
    equal(r.headers.get("cache-control"), "no-store");
    equal(await r.json(), { error: "temporary_failure" });
    equal(cancelled, true);
  }));

Deno.test("reason Unicode boundaries reject every forbidden control and isolated surrogate", () => {
  for (
    const n of [
      ...Array.from({ length: 32 }, (_, i) => i).filter((i) =>
        ![9, 10, 13].includes(i)
      ),
      127,
      0xd800,
      0xdfff,
    ]
  ) {
    let rejected = false;
    try {
      normalizeReason("a" + String.fromCharCode(n));
    } catch {
      rejected = true;
    }
    equal(rejected, true);
  }
  equal(normalizeReason("\u00a0"), "\u00a0");
  equal(normalizeReason("\t🙂\r\n"), "🙂");
});
