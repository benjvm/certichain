import { handler } from "./handler.ts";
import {
  credentialCode,
  publicProjection,
  publicTimestamp,
} from "./contract.ts";
import { BodyError, boundedBody } from "../_shared/bounded_body.ts";

const code = "a1111111-2222-4333-8444-555555555555";
const config = { url: "http://backend", serviceKey: "synthetic-secret" };
const absence = { schema_version: "1", result: "not_found" };
const valid = {
  schema_version: "1",
  result: "valid",
  credential_code: code,
  title: "Synthetic",
  issuer: { name: "Synthetic Issuer" },
  issued_at: "2026-01-01T00:00:00.123456+00:00",
  expires_at: null,
  checked_at: "2026-10-04T00:00:00.654321+00:00",
  verification_source: "certichain_registry",
};
function check(value: unknown, label = "Assertion failed") {
  if (!value) throw new Error(label);
}
function request(
  body: BodyInit = JSON.stringify({ credential_code: code }),
  type = "application/json",
) {
  return new Request("http://localhost", {
    method: "POST",
    headers: { "Content-Type": type },
    body,
  });
}
async function mocked(
  run: () => Promise<void>,
  options: { budget?: unknown; result?: unknown; failure?: string } = {},
) {
  const original = globalThis.fetch;
  let consumes = 0, lookups = 0;
  globalThis.fetch = (async (url, init) => {
    await Promise.resolve();
    check(
      new Headers(init?.headers).get("Authorization") ===
        `Bearer ${config.serviceKey}`,
    );
    check(init?.signal, "Upstream timeout");
    const target = String(url);
    const budget = target.endsWith("consume_public_verification_budget");
    check(
      budget || target.endsWith("lookup_public_certificate"),
      "Only narrow RPCs",
    );
    if (budget) {
      consumes++;
      check(
        JSON.stringify(JSON.parse(String(init?.body))) === "{}",
        "No client budget arguments",
      );
    } else {
      lookups++;
      check(consumes > 0, "Budget precedes lookup");
      check(JSON.parse(String(init?.body)).p_credential_code === code);
    }
    if (options.failure === (budget ? "budget" : "lookup")) {
      return Response.json({ details: "private SQL and credentials" }, {
        status: 500,
      });
    }
    return Response.json(
      budget
        ? options.budget ?? { allowed: true, retry_after: 0 }
        : options.result ?? valid,
    );
  }) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
  return { consumes, lookups };
}
async function expect(req: Request, status: number, body: unknown) {
  const response = await handler(config)(req);
  check(
    response.status === status,
    `Expected ${status}, got ${response.status}`,
  );
  check(response.headers.get("cache-control") === "no-store");
  check(response.headers.get("access-control-allow-origin") === "*");
  check(
    JSON.stringify(await response.json()) === JSON.stringify(body),
    "Closed response",
  );
  return response;
}

Deno.test("Canonical UUID only; case normalization; closed input", () => {
  check(credentialCode({ credential_code: code.toUpperCase() }) === code);
  for (
    const value of [
      null,
      [],
      {},
      { credential_code: 1 },
      { credential_code: null },
      { credential_code: ` ${code}` },
      { credential_code: `${code}\n` },
      { credential_code: code.replaceAll("-", "") },
      { credential_code: `{${code}}` },
      { credential_code: code, limit: 100 },
    ]
  ) {
    check(credentialCode(value) === null);
  }
});
Deno.test("Projection rejects private/unknown fields and retains microseconds", () => {
  check(publicProjection(valid, code));
  check(publicProjection(absence, code));
  for (
    const data of [
      null,
      { ...valid, holder_id: code },
      { ...valid, issuer: { name: "Issuer", logo: "invented" } },
      { ...valid, result: "pending" },
      { ...valid, credential_code: "other" },
      { ...absence, issuer: valid.issuer },
      { ...valid, schema_version: 2 },
    ]
  ) {
    check(!publicProjection(data, code));
  }
});
Deno.test("8D exact result types fail closed at the RPC boundary", async () => {
  for (
    const result of [
      ["valid"],
      { toString: "valid" },
      true,
      false,
      1,
      null,
      "unknown",
      ["not_found"],
    ]
  ) {
    const projection = { ...valid, result };
    check(!publicProjection(projection, code));
    await mocked(async () => {
      await expect(request(), 503, { error: "temporary_failure" });
    }, { result: projection });
  }
});
Deno.test("8D Gregorian dates, time, precision and numeric zones", async () => {
  const accepted = [
    "2000-02-29T23:59:59Z",
    "2024-02-29T12:00:00.1+02:30",
    "2026-01-31T00:00:00.123456-23:59",
    "0001-01-01T00:00:00+00:00",
  ];
  const rejected: unknown[] = [
    "2026-99-99T12:00:00Z",
    "2026-02-29T00:00:00Z",
    "1900-02-29T00:00:00Z",
    "2026-04-31T00:00:00Z",
    "2026-00-01T00:00:00Z",
    "2026-01-00T00:00:00Z",
    "0000-01-01T00:00:00Z",
    "2026-01-01T24:00:00Z",
    "2026-01-01T00:60:00Z",
    "2026-01-01T00:00:60Z",
    "2026-01-01T00:00:00+24:00",
    "2026-01-01T00:00:00-01:60",
    "2026-01-01T00:00:00.1234567Z",
    "2026-01-01T00:00:00.Z",
    "2026-01-01T00:00:00+0100",
    "2026-01-01T00:00:00",
    "2026-01-01T00:00:00Z\n",
    [valid.issued_at],
    {},
    true,
  ];
  for (const timestamp of accepted) {
    check(publicTimestamp(timestamp));
    check(
      publicProjection({
        ...valid,
        issued_at: timestamp,
        checked_at: timestamp,
        expires_at: timestamp,
      }, code),
    );
  }
  for (const timestamp of rejected) {
    check(!publicTimestamp(timestamp));
    for (const field of ["issued_at", "checked_at", "expires_at"]) {
      await mocked(async () => {
        await expect(request(), 503, { error: "temporary_failure" });
      }, { result: { ...valid, [field]: timestamp } });
    }
  }
});
Deno.test("Public success without session and uppercase equivalent", async () => {
  await mocked(async () => {
    await expect(
      request(JSON.stringify({ credential_code: code.toUpperCase() })),
      200,
      valid,
    );
  });
});
Deno.test("Unknown shares minimal not_found", async () => {
  await mocked(async () => {
    await expect(request(), 200, absence);
  }, { result: absence });
});
for (
  const [label, input, type, status] of [
    ["invalid JSON", "{", "application/json", 400],
    [
      "extra field",
      JSON.stringify({ credential_code: code, reset: true }),
      "application/json",
      400,
    ],
    ["invalid code", '{"credential_code": false}', "application/json", 400],
    ["wrong MIME", "{}", "text/plain", 400],
    ["MIME prefix", "{}", "application/json-evil", 400],
    ["oversized without length", " ".repeat(2049), "application/json", 413],
  ] as const
) {
  Deno.test(`${label} consumes budget before rejection`, async () => {
    const counts = await mocked(async () => {
      await expect(request(input, type), status, {
        error: status === 413 ? "payload_too_large" : "invalid_input",
      });
    });
    check(counts.consumes === 1 && counts.lookups === 0);
  });
}
Deno.test("OPTIONS and methods never query backend", async () => {
  const counts = await mocked(async () => {
    const response = await handler(config)(
      new Request("http://localhost", { method: "OPTIONS" }),
    );
    check(
      response.status === 204 &&
        response.headers.get("cache-control") === "no-store",
    );
    await expect(new Request("http://localhost"), 405, {
      error: "method_not_allowed",
    });
  });
  check(counts.consumes === 0 && counts.lookups === 0);
});
Deno.test("Exhaustion precedes even invalid body, with server Retry-After", async () => {
  const counts = await mocked(async () => {
    const r = await expect(request("{"), 429, { error: "rate_limited" });
    check(r.headers.get("retry-after") === "7");
  }, { budget: { allowed: false, retry_after: 7 } });
  check(counts.consumes === 1 && counts.lookups === 0);
});
for (const failure of ["budget", "lookup"]) {
  Deno.test(`${failure} infrastructure fails closed`, async () => {
    await mocked(async () => {
      await expect(request(), 503, { error: "temporary_failure" });
    }, { failure });
  });
}
Deno.test("Unexpected upstream projection or budget fails closed", async () => {
  for (
    const options of [{ result: { ...valid, document_hash: "private" } }, {
      result: { ...valid, title: "x".repeat(8192) },
    }, {
      budget: { allowed: false, retry_after: 0 },
    }, { budget: { allowed: "true", retry_after: 0 } }]
  ) {
    await mocked(async () => {
      await expect(request(), 503, { error: "temporary_failure" });
    }, options);
  }
});
Deno.test("Stream byte boundary and timeout are enforced", async () => {
  const bytes = new Uint8Array(2048);
  check((await boundedBody(new Response(bytes).body, 2048)).length === 2048);
  const stream = new ReadableStream<Uint8Array>({ pull() {} });
  try {
    await boundedBody(stream, 2048, 5);
    throw new Error("Expected deadline");
  } catch (e) {
    check(e instanceof BodyError && e.status === 503);
  }
  const chunks = new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(bytes);
      c.enqueue(new Uint8Array(1));
      c.close();
    },
  });
  try {
    await boundedBody(chunks, 2048);
    throw new Error("Expected limit");
  } catch (e) {
    check(e instanceof BodyError && e.status === 413);
  }
});
