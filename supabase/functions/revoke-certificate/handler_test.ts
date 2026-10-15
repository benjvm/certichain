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
function request(body: string) {
  return new Request("http://edge.invalid", {
    method: "POST",
    headers: {
      authorization: "Bearer synthetic",
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
