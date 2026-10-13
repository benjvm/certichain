import { handler } from "./handler.ts";
import { handler as opening } from "../certificate-opening/handler.ts";
import { PublicEvmReader } from "../_shared/blockchain/data/public_reader.ts";
import { certificateKey } from "../_shared/blockchain/application/commitment.ts";
import { strictJson } from "../_shared/strict_json.ts";
import type { Deployment } from "../_shared/blockchain/domain/registry.ts";
const code = "00112233-4455-6677-8899-aabbccddeeff";
const at = "2026-10-13T00:00:00.123456Z";
const hex = (byte: string) => `0x${byte.repeat(32)}`;
const config = {
  url: "https://sql.invalid",
  serviceKey: "technical",
  anonKey: "public",
  environment: "local",
};
const registry = {
  schema_version: "1",
  result: "valid",
  credential_code: code,
  title: "Synthetic",
  issuer: { name: "Synthetic" },
  issued_at: at,
  expires_at: null,
  checked_at: at,
  verification_source: "certichain_registry",
};
function assert(v: unknown) {
  if (!v) throw new Error("Assertion failed");
}
async function mocked(
  run: () => Promise<void>,
  respond: (url: string, body: Record<string, unknown>) => Response,
) {
  const original = globalThis.fetch;
  globalThis.fetch =
    ((input: RequestInfo | URL, init?: RequestInit) =>
      Promise.resolve(
        respond(String(input), JSON.parse(String(init?.body ?? "{}"))),
      )) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
}
const request = (
  body = JSON.stringify({ credential_code: code }),
  method = "POST",
) =>
  new Request("https://edge.invalid", {
    method,
    headers: { "content-type": "application/json" },
    ...(method === "POST" ? { body } : {}),
  });
const budget = () => Response.json({ allowed: true, retry_after: 0 });
Deno.test("reader rejects wrong-height and out-of-range block responses", async () => {
  for (const number of ["0x2", "0xffffffffffffffffffffffffffff"]) {
    await mocked(async () => {
      const reader = new PublicEvmReader(
        "https://rpc.invalid",
        { network: "anvil" } as Deployment,
      );
      reader.deadline = Date.now() + 1000;
      let rejected = false;
      try {
        await reader.rpc("eth_getBlockByNumber", ["0x1", false]);
      } catch {
        rejected = true;
      }
      assert(rejected);
    }, () =>
      Response.json({
        jsonrpc: "2.0",
        id: 1,
        result: { number, hash: hex("44"), timestamp: "0x1" },
      }));
  }
});
Deno.test("oversized SQL response is technical 503, not a client body error", () =>
  mocked(
    async () => {
      assert((await handler(config)(request())).status === 503);
    },
    (url) =>
      url.endsWith("consume_public_verification_budget")
        ? budget()
        : new Response("x".repeat(16385)),
  ));
Deno.test("oversized Auth response is sanitized technical 503", () =>
  mocked(async () => {
    const r = await opening(config)(
      new Request("https://edge.invalid", {
        method: "POST",
        headers: {
          authorization: "Bearer caller",
          "content-type": "application/json",
        },
        body: JSON.stringify({ certificate_id: code }),
      }),
    );
    assert(r.status === 503);
  }, () => new Response("x".repeat(16385))));
Deno.test("v2 consumes once, registry literal, off-chain has no EVM", () =>
  mocked(
    async () => {
      let r = await handler(config)(request());
      assert(r.status === 200);
      const dto = await r.json();
      assert(
        dto.schema_version === "2" &&
          JSON.stringify(dto.registry) === JSON.stringify(registry),
      );
      assert(
        dto.blockchain.state === "off_chain_only" &&
          dto.blockchain.checked_at === at,
      );
      r = await handler(config)(request(undefined, "OPTIONS"));
      assert(r.status === 204);
    },
    (url) =>
      url.endsWith("consume_public_verification_budget")
        ? budget()
        : url.endsWith("lookup_public_certificate_v2")
        ? Response.json({ registry, anchor: null })
        : (() => {
          throw new Error("Unexpected RPC");
        })(),
  ));
Deno.test("v2 uniform absence excludes any EVM access", () =>
  mocked(
    async () => {
      const r = await handler({ ...config, rpcUrl: "https://evm.invalid" })(
        request(),
      );
      assert(r.status === 200);
      assert(
        JSON.stringify(await r.json()) ===
          JSON.stringify({
            schema_version: "2",
            registry: { schema_version: "1", result: "not_found" },
            blockchain: null,
          }),
      );
    },
    (url) =>
      url.endsWith("consume_public_verification_budget")
        ? budget()
        : url.endsWith("lookup_public_certificate_v2")
        ? Response.json({
          registry: { schema_version: "1", result: "not_found" },
          anchor: null,
        })
        : (() => {
          throw new Error("Unexpected RPC");
        })(),
  ));
Deno.test("invalid/duplicate/UTF8 inputs consume one shared budget, never lookup", async () => {
  for (
    const source of [
      "{}",
      '{"credential_code":"bad"}',
      `{"credential_code":"${code}","credential_code":"${code}"}`,
      `{"credential_code":"${code}","credential_\\u0063ode":"${code}"}`,
      "[]",
    ]
  ) {
    let calls = 0;
    await mocked(async () => {
      assert((await handler(config)(request(source))).status === 400);
      assert(calls === 1);
    }, (url) => {
      assert(url.endsWith("consume_public_verification_budget"));
      calls++;
      return budget();
    });
  }
});
Deno.test("v2 bounds body and returns Retry-After before validating", async () => {
  await mocked(async () => {
    const r = await handler(config)(request("x".repeat(2049)));
    assert(r.status === 413);
  }, () => budget());
  await mocked(async () => {
    const r = await handler(config)(request("invalid"));
    assert(r.status === 429 && r.headers.get("retry-after") === "23");
  }, () => Response.json({ allowed: false, retry_after: 23 }));
});
Deno.test("SQL failure/malformed snapshot is technical, no false absence", async () => {
  for (
    const bad of [null, {
      registry: { schema_version: "1", result: "not_found" },
      anchor: {},
    }, { registry: { ...registry, extra: "secret" }, anchor: null }]
  ) {
    await mocked(
      async () => {
        assert((await handler(config)(request())).status === 503);
      },
      (url) =>
        url.endsWith("consume_public_verification_budget")
          ? budget()
          : Response.json(bad),
    );
  }
});
Deno.test("unavailable preserves previous evidence's real timestamp without secrets", async () => {
  const K = await certificateKey(code),
    C = hex("11"),
    I = hex("22"),
    address = `0x${"33".repeat(20)}`;
  const previous = {
    state: "confirmed",
    finality: "not_applicable",
    chain_id: "31337",
    contract_address: address,
    protocol_version: 1,
    certificate_key: K,
    issuer_id: I,
    commitment: C,
    revoked: false,
    transaction_hash: hex("44"),
    block_number: "12",
    block_hash: hex("55"),
    confirmations: "1",
    checked_at: at,
    source: "persisted_receipt",
  };
  await mocked(
    async () => {
      const r = await handler(config)(request());
      assert(r.status === 200);
      const dto = await r.json();
      assert(
        dto.blockchain.state === "unavailable" &&
          dto.blockchain.last_evidence.checked_at === at,
      );
      assert(
        !JSON.stringify(dto).includes("document_sha256") &&
          !JSON.stringify(dto).includes("salt"),
      );
    },
    (url) =>
      url.endsWith("consume_public_verification_budget")
        ? budget()
        : Response.json({
          registry,
          anchor: {
            deployment: {
              environment_id: "local",
              network: "anvil",
              chain_id: "31337",
              contract_address: address,
              protocol_version: 1,
              runtime_code_hash: hex("66"),
              genesis_hash: hex("77"),
              deployment_block: "1",
              deployment_hash: hex("88"),
            },
            certificate_key: K,
            issuer_id: I,
            commitment: C,
            state: "confirmed",
            transaction_hash: hex("44"),
            signer: address,
            last_evidence: previous,
          },
        }),
  );
});
Deno.test("strict JSON rejects escaped duplicates, recursion and nonfinite values", () => {
  for (
    const input of [
      '{"a":1,"\\u0061":2}',
      "1e999",
      "[".repeat(17) + "0" + "]".repeat(17),
    ]
  ) {
    let rejected = false;
    try {
      strictJson(input);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
Deno.test("public reader blocks every write method without keys", async () => {
  const reader = new PublicEvmReader(
    "https://rpc.invalid",
    { network: "anvil" } as Deployment,
  );
  for (
    const method of [
      "eth_sendRawTransaction",
      "eth_sendTransaction",
      "eth_estimateGas",
      "eth_getTransactionCount",
      "personal_sign",
      "evm_mine",
    ]
  ) {
    let rejected = false;
    try {
      await reader.rpc(method);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
Deno.test("reader rejects unbounded/malformed/duplicate/noncanonical RPC values", async () => {
  for (
    const body of [
      '{"jsonrpc":"2.0","id":1,"result":"1"}',
      '{"jsonrpc":"2.0","id":1,"result":"0x00"}',
      '{"jsonrpc":"2.0","id":1,"result":"0x1","result":"0x2"}',
      "x".repeat(65537),
    ]
  ) {
    await mocked(async () => {
      const reader = new PublicEvmReader(
        "https://rpc.invalid",
        { network: "anvil" } as Deployment,
      );
      reader.deadline = Date.now() + 1000;
      let rejected = false;
      try {
        await reader.rpc("eth_chainId");
      } catch {
        rejected = true;
      }
      assert(rejected);
    }, () => new Response(body));
  }
});
Deno.test("opening requires real Auth identity and returns uniform no-store denial", async () => {
  assert(
    (await opening(config)(
      new Request("https://edge.invalid", { method: "POST" }),
    )).status === 401,
  );
  await mocked(
    async () => {
      const r = await opening(config)(
        new Request("https://edge.invalid", {
          method: "POST",
          headers: {
            authorization: "Bearer caller",
            "content-type": "application/json",
          },
          body: JSON.stringify({ certificate_id: code }),
        }),
      );
      assert(r.status === 404 && r.headers.get("cache-control") === "no-store");
    },
    (url) =>
      url.endsWith("/user")
        ? Response.json({ id: code, is_anonymous: false })
        : Response.json(null),
  );
});
Deno.test("opening closed input and closed output, no Storage or operations", async () => {
  for (
    const body of [
      `{"certificate_id":"${code}","salt":"x"}`,
      `{"certificate_id":"${code}","certificate_id":"${code}"}`,
    ]
  ) {
    await mocked(async () => {
      const r = await opening(config)(
        new Request("https://edge.invalid", {
          method: "POST",
          headers: {
            authorization: "Bearer caller",
            "content-type": "application/json",
          },
          body,
        }),
      );
      assert(r.status === 400);
    }, (url) => {
      assert(url.endsWith("/user"));
      return Response.json({ id: code, is_anonymous: false });
    });
  }
});
