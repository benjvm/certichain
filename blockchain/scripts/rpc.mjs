import assert from "node:assert/strict";

export function requireLoopback(value) {
  assert.match(
    value,
    /^http:\/\/127\.0\.0\.1:[1-9][0-9]{0,4}\/?$/,
    "Literal loopback endpoint required",
  );
  const url = new URL(value);
  assert.equal(url.protocol, "http:", "Local RPC must use HTTP loopback");
  assert.equal(
    url.hostname,
    "127.0.0.1",
    "Only literal IPv4 loopback is allowed",
  );
  assert(
    url.port && Number(url.port) > 0 && Number(url.port) <= 65535,
    "Explicit port required",
  );
  assert.equal(url.pathname, "/");
  assert(
    !url.username && !url.password && !url.search && !url.hash,
    "RPC credentials/path/query/fragment forbidden",
  );
  return url.href;
}

export function localRpc(value) {
  const url = requireLoopback(value);
  let id = 0;
  return async (method, params = []) => {
    const requestId = ++id;
    const response = await fetch(url, {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(10_000),
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params }),
    });
    assert(response.ok, `RPC HTTP ${response.status}`);
    const json = await response.json();
    assert.equal(json.id, requestId);
    if (json.error) {
      const error = new Error(
        `RPC ${method} rejected (code ${json.error.code})`,
      );
      error.rpcError = json.error;
      throw error;
    }
    assert(Object.hasOwn(json, "result"), "Missing RPC result");
    return json.result;
  };
}

export const quantity = (n) => "0x" + BigInt(n).toString(16);
export const decimal = (hex) => BigInt(hex).toString();
export const words = (data) => {
  assert.match(data, /^0x(?:[0-9a-fA-F]{64})*$/);
  return data.slice(2).match(/.{64}/g)?.map((w) => "0x" + w.toLowerCase()) ??
    [];
};
