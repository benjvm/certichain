import assert from "node:assert/strict";
import { test } from "node:test";
import { quantity, requireLoopback, words } from "./rpc.mjs";

test("Local harness rejects remote, ambiguous and credential-bearing endpoints", () => {
  for (
    const value of [
      "https://127.0.0.1:8545",
      "http://example.com:8545",
      "http://0.0.0.0:8545",
      "http://localhost:8545",
      "http://127.0.0.1",
      "http://127.1:8545",
      "http://2130706433:8545",
      "http://127.0.0.1:8545/path",
      "http://user:pass@127.0.0.1:8545",
      "http://127.0.0.1:8545?fork=remote",
      "http://127.0.0.1:8545#remote",
      "http://127.0.0.1:65536",
    ]
  ) assert.throws(() => requireLoopback(value));
  assert.equal(
    requireLoopback("http://127.0.0.1:8545"),
    "http://127.0.0.1:8545/",
  );
});

test("RPC helpers preserve uint64 boundaries without Number rounding", () => {
  assert.equal(quantity(18446744073709551615n), "0xffffffffffffffff");
  assert.deepEqual(words("0x" + "00".repeat(32) + "ff".repeat(32)), [
    "0x" + "00".repeat(32),
    "0x" + "ff".repeat(32),
  ]);
  assert.throws(() => words("0x1234"));
});
