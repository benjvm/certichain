import { handler } from "./handler.ts";
const code = "a1111111-2222-4333-8444-555555555555", hash = "b".repeat(64);
const config = { url: "http://backend", serviceKey: "synthetic-secret" };
const verification = {
  schema_version: "1",
  result: "valid",
  credential_code: code,
  title: "Synthetic",
  issuer: { name: "Synthetic" },
  issued_at: "2020-01-01T00:00:00Z",
  expires_at: null,
  checked_at: "2026-10-05T00:00:00.654321Z",
  verification_source: "certichain_registry",
};
const result = { schema_version: "1", verification, file_integrity: "match" };
function check(value: unknown, label = "Comparison assertion") {
  if (!value) throw new Error(label);
}
async function exercise(body: BodyInit, status: number, options: {
  method?: string;
  mime?: string;
  projection?: unknown;
  denied?: boolean;
  broken?: boolean;
} = {}) {
  const original = globalThis.fetch;
  let consumes = 0, lookups = 0;
  globalThis.fetch = (async (url, init) => {
    await Promise.resolve();
    check(
      new Headers(init?.headers).get("Authorization") ===
        `Bearer ${config.serviceKey}`,
    );
    check(init?.signal, "RPC deadline");
    const budget = String(url).endsWith("consume_public_verification_budget");
    if (budget) consumes++;
    else {
      lookups++;
      check(
        consumes === 1 &&
          String(url).endsWith("compare_public_certificate_hash"),
      );
      const args = JSON.parse(String(init?.body));
      check(args.p_credential_code === code && args.p_document_sha256 === hash);
      check(Object.keys(args).length === 2);
    }
    if (options.broken) throw new Error("private backend error");
    return Response.json(
      budget
        ? { allowed: !options.denied, retry_after: options.denied ? 12 : 0 }
        : options.projection ?? result,
    );
  }) as typeof fetch;
  try {
    const method = options.method ?? "POST";
    const response = await handler(config)(
      new Request("http://localhost", {
        method,
        headers: {
          "Content-Type": options.mime ?? "application/json; charset=utf-8",
        },
        body: method === "POST" ? body : undefined,
      }),
    );
    check(
      response.status === status,
      `Expected ${status}, got ${response.status}`,
    );
    check(response.headers.get("cache-control") === "no-store");
    check(response.headers.get("access-control-allow-origin") === "*");
    check(consumes === (method === "POST" ? 1 : 0));
    if (status !== 200) {
      check(lookups === (status === 503 && !options.broken ? 1 : 0));
    }
    if (status === 429) check(response.headers.get("retry-after") === "12");
    if (status !== 204) {
      const data = await response.json();
      check(!JSON.stringify(data).includes("private backend error"));
      if (status === 200) {
        check(
          JSON.stringify(data) === JSON.stringify(options.projection ?? result),
        );
      } else check(Object.keys(data).join(",") === "error");
    }
  } finally {
    globalThis.fetch = original;
  }
}
const input = JSON.stringify({
  credential_code: code.toUpperCase(),
  document_sha256: hash,
});
for (const state of ["valid", "revoked", "expired", "issuer_unavailable"]) {
  for (const integrity of ["match", "integrity_mismatch"]) {
    Deno.test(`comparison projection ${state}/${integrity}`, () =>
      exercise(input, 200, {
        projection: {
          ...result,
          verification: { ...verification, result: state },
          file_integrity: integrity,
        },
      }));
  }
}
Deno.test("uniform unavailable", () =>
  exercise(input, 200, {
    projection: {
      schema_version: "1",
      verification: { schema_version: "1", result: "not_found" },
      file_integrity: "unavailable",
    },
  }));
for (
  const [label, body, status] of [
    ["empty", "{}", 400],
    ["bad JSON", "{", 400],
    ["oversize", "x".repeat(2049), 413],
    [
      "extra field",
      JSON.stringify({
        credential_code: code,
        document_sha256: hash,
        filename: "private.pdf",
      }),
      400,
    ],
    [
      "uppercase hash",
      JSON.stringify({
        credential_code: code,
        document_sha256: hash.toUpperCase(),
      }),
      400,
    ],
    [
      "newline hash",
      JSON.stringify({ credential_code: code, document_sha256: hash + "\n" }),
      400,
    ],
    [
      "bad code",
      JSON.stringify({ credential_code: "uuid", document_sha256: hash }),
      400,
    ],
    ["null", "null", 400],
    ["array", "[]", 400],
  ] as const
) {
  Deno.test(`invalid consumes shared budget: ${label}`, () =>
    exercise(body, status));
}
Deno.test("OPTIONS and method skip budget", async () => {
  await exercise("", 204, { method: "OPTIONS" });
  await exercise("", 405, { method: "GET" });
});
Deno.test("budget checked before validation; infrastructure fails closed", async () => {
  await exercise("not JSON", 429, { denied: true });
  await exercise(input, 503, { broken: true });
});
Deno.test("wrong MIME and widened/upstream inconsistent DTO fail", async () => {
  await exercise(input, 400, { mime: "text/plain" });
  await exercise(input, 503, {
    projection: { ...result, document_hash: hash },
  });
  await exercise(input, 503, {
    projection: { ...result, file_integrity: "unavailable" },
  });
});
