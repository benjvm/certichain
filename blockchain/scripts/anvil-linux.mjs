// Reuse the frozen 9B Linux archive for an isolated Docker Anvil on Windows.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { Buffer } from "node:buffer";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
const root = resolve(import.meta.dirname, "..");
const lock = JSON.parse(
  readFileSync(resolve(root, "toolchain.lock.json"), "utf8"),
);
const entry = lock.foundry.platforms["linux-x64"];
const folder = resolve(root, ".tools/anvil-linux");
mkdirSync(folder, { recursive: true });
const archive = resolve(folder, "foundry.tar.gz");
if (!existsSync(archive)) {
  const response = await fetch(entry.url, {
    signal: AbortSignal.timeout(120000),
  });
  assert(response.ok, "Frozen Linux Foundry archive unavailable");
  writeFileSync(archive, Buffer.from(await response.arrayBuffer()));
}
assert.equal(
  createHash("sha256").update(readFileSync(archive)).digest("hex"),
  entry.sha256,
);
const result = spawnSync("tar", ["-xf", archive, "-C", folder, "anvil"], {
  encoding: "utf8",
  timeout: 30000,
});
assert.equal(result.status, 0, "Frozen Linux Anvil extraction failed");
console.log("PASS frozen Linux Anvil archive verified and extracted");
