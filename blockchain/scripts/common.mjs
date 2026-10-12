import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const lock = JSON.parse(
  readFileSync(resolve(root, "toolchain.lock.json")),
);
export const suffix = process.platform === "win32" ? ".exe" : "";
export const bin = (name) => resolve(root, ".tools/bin", name + suffix);
export const sha256 = (bytes) =>
  createHash("sha256").update(bytes).digest("hex");
export function run(executable, args, options = {}) {
  const result = spawnSync(executable, args, {
    cwd: root,
    encoding: "utf8",
    windowsHide: true,
    maxBuffer: 32 * 1024 * 1024,
    env: {
      ...process.env,
      CERTICHAIN_TEST_CAMERA: "0",
      FOUNDRY_PROFILE: "default",
      FOUNDRY_SOLC: bin("solc"),
    },
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${executable} exited ${result.status}\n${result.stdout ?? ""}\n${
        result.stderr ?? ""
      }`,
    );
  }
  return result.stdout?.trim() ?? "";
}
export const forge = (...args) => run(bin("forge"), args);
export const cast = (...args) => run(bin("cast"), args);
export function verifyVersions() {
  for (const name of ["forge", "cast", "anvil"]) {
    const output = run(bin(name), ["--version"]);
    if (
      !output.includes(lock.foundry.version) ||
      !output.includes(lock.foundry.commit)
    ) {
      throw new Error(`Unexpected ${name} version`);
    }
  }
  const compiler = run(bin("solc"), ["--version"]);
  if (!compiler.includes(`0.8.37+commit.${lock.solidity.commit.slice(0, 8)}`)) {
    throw new Error("Unexpected compiler version");
  }
}
