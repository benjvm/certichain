import assert from "node:assert/strict";
import { test } from "node:test";
import { fetchChecked } from "./download.mjs";

const api =
  "https://api.github.com/repos/argotorg/solidity/releases/tags/v0.8.37";
function harness(sequence, overrides = {}) {
  let time = 1_000_000;
  const calls = [], waits = [], logs = [];
  return {
    calls,
    waits,
    logs,
    options: {
      token: "synthetic-secret",
      now: () => time,
      sleep: (ms) => {
        waits.push(ms);
        time += ms;
      },
      log: (record) => logs.push(record),
      fetchImpl: (url, options) => {
        calls.push({ url, ...options });
        const item = sequence.shift();
        assert.ok(item, "Unexpected attempt");
        if (item instanceof Error) throw item;
        return item;
      },
      ...overrides,
    },
  };
}
const ok = () => new Response("verified bytes");
test("optional token is sent only to the exact HTTPS API origin", async () => {
  for (
    const url of [
      api,
      "http://api.github.com/x",
      "https://api.github.com:444/x",
      "https://api.github.com.evil.test/x",
      "https://github.com/asset",
      "https://codeload.github.com/archive",
      "https://mirror.test/asset",
    ]
  ) {
    const h = harness([ok()]);
    assert.equal(
      (await fetchChecked(url, h.options)).toString(),
      "verified bytes",
    );
    assert.equal(
      h.calls[0].headers.get("authorization"),
      url === api ? "Bearer synthetic-secret" : null,
    );
    assert.equal(h.calls[0].redirect, "manual");
  }
  const h = harness([ok()], { token: "" });
  await fetchChecked(api, h.options);
  assert.equal(h.calls[0].headers.has("authorization"), false);
});
test("manual cross-origin redirects rebuild headers and never forward token to assets", async () => {
  const h = harness([
    new Response(null, {
      status: 302,
      headers: { location: "https://github.com/asset" },
    }),
    new Response(null, {
      status: 307,
      headers: { location: "https://objects.example.test/download" },
    }),
    ok(),
  ]);
  await fetchChecked(api, h.options);
  assert.deepEqual(h.calls.map((c) => c.headers.get("authorization")), [
    "Bearer synthetic-secret",
    null,
    null,
  ]);
  const relative = harness([
    new Response(null, { status: 301, headers: { location: "/new" } }),
    ok(),
  ]);
  await fetchChecked(api, relative.options);
  assert.equal(
    relative.calls[1].headers.get("authorization"),
    "Bearer synthetic-secret",
  );
});
test("unsafe, missing or endless redirects fail bounded, without leaking Location", async () => {
  for (
    const location of [
      "http://api.github.com/insecure",
      "https://secret:password@example.test/private",
      "file:///private",
      null,
    ]
  ) {
    const h = harness([
      new Response(null, {
        status: 302,
        headers: location === null ? {} : { location },
      }),
    ]);
    await assert.rejects(
      fetchChecked(api, h.options),
      (error) =>
        !error.message.includes("password") && /redirect/.test(error.message),
    );
    assert.equal(h.calls.length, 1);
  }
  const h = harness(
    Array.from(
      { length: 6 },
      () => new Response(null, { status: 302, headers: { location: api } }),
    ),
  );
  await assert.rejects(fetchChecked(api, h.options), /invalid_redirect/);
  assert.equal(h.calls.length, 6);
});
test("403 requires positive rate-limit evidence; arbitrary denial is definitive and sanitized", async () => {
  const h = harness([
    new Response("private-token upstream body", {
      status: 403,
      headers: {
        "x-github-request-id": "ABCD:1234",
        "x-ratelimit-remaining": "12",
      },
    }),
  ]);
  await assert.rejects(
    fetchChecked(api + "?secret=private-token", h.options),
    (error) => {
      assert.match(error.message, /permanent_http/);
      assert.match(error.message, /ABCD:1234/);
      assert.match(error.message, /rate_remaining.*12/);
      assert.doesNotMatch(
        error.message,
        /private-token|synthetic-secret|upstream body/,
      );
      return true;
    },
  );
  assert.equal(h.calls.length, 1);
  assert.equal(h.waits.length, 0);
});
test("primary rate limit waits for reset; Retry-After seconds and dates are respected", async () => {
  for (
    const headers of [
      { "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1007" },
      { "retry-after": "7" },
      { "retry-after": new Date(1_007_000).toUTCString() },
    ]
  ) {
    const h = harness([new Response(null, { status: 403, headers }), ok()]);
    await fetchChecked(api, h.options);
    assert.deepEqual(h.waits, [7000]);
    assert.equal(h.logs[0].classification, "rate_limit");
  }
});
test("identified transient status and network errors recover; permanent transport does not", async () => {
  for (
    const item of [
      ...[408, 429, 500, 502, 503, 504].map((status) =>
        new Response("private", { status })
      ),
      new TypeError("private upstream", { cause: { code: "ECONNRESET" } }),
      Object.assign(new Error("private"), { name: "TimeoutError" }),
    ]
  ) {
    const h = harness([item, ok()]);
    await fetchChecked(api, h.options);
    assert.deepEqual(h.waits, [1000]);
    assert.equal(JSON.stringify(h.logs).includes("private"), false);
  }
  for (
    const item of [
      new TypeError("private", { cause: { code: "CERT_HAS_EXPIRED" } }),
      new Error("Download failed: private secret"),
    ]
  ) {
    const h = harness([item]);
    await assert.rejects(fetchChecked(api, h.options), /permanent_transport/);
    assert.equal(h.calls.length, 1);
  }
});
test("retry attempts and total budget are bounded; no retry before excessive Retry-After", async () => {
  const h = harness(
    Array.from({ length: 3 }, () => new Response(null, { status: 503 })),
  );
  await assert.rejects(fetchChecked(api, h.options), /retry_exhausted.*true/);
  assert.equal(h.calls.length, 3);
  assert.deepEqual(h.waits, [1000, 2000]);
  const limited = harness([
    new Response(null, { status: 429, headers: { "retry-after": "121" } }),
  ]);
  await assert.rejects(fetchChecked(api, limited.options), /rate_limit/);
  assert.deepEqual(limited.waits, []);
  const budget = harness([
    new Response(null, { status: 503 }),
    new Response(null, { status: 503 }),
  ], { budgetMs: 2500 });
  await assert.rejects(fetchChecked(api, budget.options), /retry_exhausted/);
  assert.deepEqual(budget.waits, [1000]);
});
test("permanent HTTP errors and untrusted diagnostic headers never produce a retry or leak", async () => {
  for (const status of [400, 401, 403, 404, 422]) {
    const h = harness([
      new Response("secret body", {
        status,
        headers: {
          "x-ratelimit-remaining": "secret",
          "x-github-request-id": "secret token arbitrary",
        },
      }),
    ]);
    await assert.rejects(
      fetchChecked(api, h.options),
      (error) => !error.message.includes("secret"),
    );
    assert.equal(h.calls.length, 1);
  }
  const h = harness([
    new Response(null, {
      status: 403,
      headers: { "x-github-request-id": "synthetic-secret" },
    }),
  ]);
  await assert.rejects(
    fetchChecked(api, h.options),
    (error) => !error.message.includes("synthetic-secret"),
  );
  await assert.rejects(
    fetchChecked("invalid-url-with-private-secret", h.options),
    (error) => !error.message.includes("private-secret"),
  );
});
