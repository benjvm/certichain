import { handler } from "./handler.ts";
const config = {
  url: "http://backend.invalid",
  anonKey: "public-test",
  serviceKey: "technical-test",
  environment: "local",
};
const uuid = "00112233-4455-6677-8899-aabbccddeeff";
const handle = handler(config);
function equal(a: unknown, b: unknown) {
  if (a !== b) throw new Error(`Mismatch ${a} != ${b}`);
}
const rejected = [
  [
    "extra actor",
    JSON.stringify({
      certificate_id: uuid,
      idempotency_key: uuid,
      actor: uuid,
    }),
  ],
  [
    "duplicate key",
    `{"certificate_id":"${uuid}","certificate_id":"${uuid}","idempotency_key":"${uuid}"}`,
  ],
  [
    "escaped duplicate key",
    `{"certificate_id":"${uuid}","certificate_\\u0069d":"${uuid}","idempotency_key":"${uuid}"}`,
  ],
  ["array", JSON.stringify([uuid, uuid])],
  [
    "noncanonical UUID",
    JSON.stringify({ certificate_id: ` ${uuid}`, idempotency_key: uuid }),
  ],
  ["over 2KiB", " ".repeat(2049)],
  ["invalid JSON", "{"],
];
for (const [label, body] of rejected) {
  Deno.test("anchor closed UTF8 input: " + label, async () => {
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      return Promise.resolve(Response.json({ id: uuid, is_anonymous: false }));
    };
    try {
      const response = await handle(
        new Request("http://edge.invalid", {
          method: "POST",
          headers: {
            authorization: "Bearer user-test",
            "content-type": "application/json",
          },
          body,
        }),
      );
      equal(response.status, 400);
      equal(response.headers.get("cache-control"), "no-store");
      equal(calls, 1);
    } finally {
      globalThis.fetch = original;
    }
  });
}
Deno.test("Auth boundary fails before technical access", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(Response.json({ error: "invalid" }, { status: 401 }));
  try {
    equal(
      (await handle(
        new Request("http://edge.invalid", {
          method: "POST",
          headers: { authorization: "Bearer invalid" },
          body: "{}",
        }),
      )).status,
      401,
    );
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("OPTIONS and wrong method do not call Auth", async () => {
  equal(
    (await handle(new Request("http://edge.invalid", { method: "OPTIONS" })))
      .status,
    204,
  );
  equal((await handle(new Request("http://edge.invalid"))).status, 405);
});
Deno.test("invalid UTF8 never reaches private snapshot", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(Response.json({ id: uuid, is_anonymous: false }));
  try {
    equal(
      (await handle(
        new Request("http://edge.invalid", {
          method: "POST",
          headers: {
            authorization: "Bearer user-test",
            "content-type": "application/json",
          },
          body: new Uint8Array([0xff]),
        }),
      )).status,
      400,
    );
  } finally {
    globalThis.fetch = original;
  }
});
