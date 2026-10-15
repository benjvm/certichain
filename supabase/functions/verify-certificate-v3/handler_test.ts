import { handler } from "../verify-certificate-v2/handler.ts";
const code = "00112233-4455-6677-8899-aabbccddeeff",
  at = "2026-10-15T00:00:00.123456Z";
const registry = {
  schema_version: "1",
  result: "revoked",
  credential_code: code,
  title: "Synthetic",
  issuer: { name: "Synthetic" },
  issued_at: at,
  expires_at: null,
  checked_at: at,
  verification_source: "certichain_registry",
};
const revocation = {
  revoked_at: at,
  expected: false,
  state: null,
  transaction_hash: null,
  signer: null,
  previous: null,
};
const config = {
  url: "http://sql.invalid",
  serviceKey: "technical",
  environment: "local",
};
function assert(v: unknown) {
  if (!v) throw new Error("Assertion failed");
}
Deno.test("v3 uses one shared budget, closed registry and no RPC for SQL-only revocation", async () => {
  const saved = globalThis.fetch;
  let calls = 0, budgets = 0;
  globalThis.fetch = (url) => {
    calls++;
    if (String(url).endsWith("/consume_public_verification_budget")) {
      budgets++;
      return Promise.resolve(Response.json({ allowed: true, retry_after: 0 }));
    }
    assert(String(url).endsWith("/lookup_public_certificate_v3"));
    return Promise.resolve(
      Response.json({ registry, anchor: null, revocation }),
    );
  };
  try {
    const r = await handler(config, "3")(
      new Request("http://edge.invalid", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ credential_code: code }),
      }),
    );
    const data = await r.json();
    assert(
      r.status === 200 && budgets === 1 && calls === 2 &&
        data.schema_version === "3" && data.registry.result === "revoked" &&
        data.revocation.state === "not_applicable" &&
        data.revocation.revoked_at === at &&
        data.blockchain.state === "off_chain_only",
    );
    assert(
      Object.keys(data).sort().join(",") ===
        "blockchain,registry,revocation,schema_version",
    );
    assert(r.headers.get("cache-control") === "no-store");
  } finally {
    globalThis.fetch = saved;
  }
});
for (
  const patch of [{ reason: "private" }, { revoked_at: null }, {
    expected: true,
  }, { transaction_hash: "0x" + "12".repeat(32) }]
) {
  Deno.test("v3 malformed/private revocation snapshot fails closed without leaking", async () => {
    const saved = globalThis.fetch;
    globalThis.fetch = (url) =>
      Promise.resolve(
        String(url).endsWith("/consume_public_verification_budget")
          ? Response.json({ allowed: true, retry_after: 0 })
          : Response.json({
            registry,
            anchor: null,
            revocation: { ...revocation, ...patch },
          }),
      );
    try {
      const r = await handler(config, "3")(
        new Request("http://edge.invalid", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ credential_code: code }),
        }),
      );
      assert(r.status === 503 && !(await r.text()).includes("private"));
    } finally {
      globalThis.fetch = saved;
    }
  });
}
