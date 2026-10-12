import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { bin, lock, root, run, sha256, verifyVersions } from "./common.mjs";

verifyVersions();
mkdirSync(resolve(root, "evidence"), { recursive: true });
mkdirSync(resolve(root, "coverage"), { recursive: true });
const evidence = {
  schemaVersion: 1,
  status: "RUNNING",
  observedAt: new Date().toISOString(),
  platform: `${process.platform}-${process.arch}`,
  node: process.version,
  executionContext: process.env.GITHUB_ACTIONS === "true"
    ? "github_actions"
    : "local",
  github: process.env.GITHUB_ACTIONS === "true"
    ? {
      sha: process.env.GITHUB_SHA,
      runId: process.env.GITHUB_RUN_ID,
      attempt: process.env.GITHUB_RUN_ATTEMPT,
    }
    : null,
  gitHead: run("git", ["rev-parse", "HEAD"]),
  workingTreeDirty: run("git", ["status", "--porcelain"]).length > 0,
  toolchain: {
    foundry: lock.foundry.version,
    compiler: lock.solidity.version,
    dependencies: lock.dependencies,
  },
  toolchainLockSha256: sha256(
    readFileSync(resolve(root, "toolchain.lock.json")),
  ),
  campaigns: {
    fuzzRunsPerProperty: 512,
    invariantRuns: 128,
    invariantDepth: 64,
    seed: "0x9b20261012",
  },
  commands: [],
  camera: {
    status: "NOT_RUN",
    reason:
      "Omitidas por instrucción del usuario; no hay cámara física disponible",
  },
  remoteCI: "NOT_OBSERVED",
};
function save() {
  writeFileSync(
    resolve(root, "evidence/validation.json"),
    JSON.stringify(evidence, null, 2) + "\n",
  );
}
function stage(name, executable, args) {
  const item = {
    name,
    command: [executable === bin("forge") ? "forge" : executable, ...args].join(
      " ",
    ),
    result: "RUNNING",
  };
  evidence.commands.push(item);
  save();
  try {
    const output = run(executable, args, { stdio: "pipe" });
    writeFileSync(resolve(root, "evidence", name + ".log"), output + "\n");
    item.result = "PASS";
    console.log(`${name}: PASS`);
    return output;
  } catch (error) {
    item.result = "FAIL";
    evidence.status = "FAIL";
    save();
    throw error;
  } finally {
    save();
  }
}
try {
  stage("harness", process.execPath, ["--test", "scripts/harness.test.mjs"]);
  stage("vector-node", process.execPath, ["scripts/fixture.mjs", "--check"]);
  stage("vector-independent", "pwsh", [
    "-NoProfile",
    "-File",
    "scripts/verify-fixture.ps1",
  ]);
  stage("format", bin("forge"), ["fmt", "--check"]);
  stage("build", bin("forge"), ["build", "--force"]);
  const tests = stage("tests", bin("forge"), ["test"]);
  const count = tests.match(
    /(\d+) tests passed, (\d+) failed, (\d+) skipped \((\d+) total tests\)/,
  );
  assert(count, "Unrecognized Foundry test summary");
  evidence.tests = {
    passed: Number(count[1]),
    failed: Number(count[2]),
    skipped: Number(count[3]),
    reportedTotal: Number(count[4]),
  };
  stage("gas", bin("forge"), [
    "test",
    "--match-contract",
    "CertificateRegistryGasTest",
    "--gas-report",
  ]);
  stage("gas-snapshot", bin("forge"), [
    "snapshot",
    "--match-contract",
    "CertificateRegistryGasTest",
    "--check",
  ]);
  const coverage = stage("coverage", bin("forge"), [
    "coverage",
    "--exclude-tests",
    "--report",
    "summary",
    "--report",
    "lcov",
    "--report-file",
    "coverage/lcov.info",
  ]);
  const row = coverage.split("\n").find((line) =>
    line.includes("src/CertificateRegistry.sol") && line.includes("%")
  );
  assert(row, "Missing coverage for own contract");
  const metrics = [...row.matchAll(/([0-9.]+)% \((\d+)\/(\d+)\)/g)];
  assert.equal(metrics.length, 4);
  evidence.coverage = Object.fromEntries(
    ["lines", "statements", "branches", "functions"].map((
      name,
      n,
    ) => [name, {
      percent: Number(metrics[n][1]),
      covered: Number(metrics[n][2]),
      total: Number(metrics[n][3]),
    }]),
  );
  // Export rebuilds normally; coverage artifacts are never used in deployment or stable ABI.
  stage("artifacts", process.execPath, ["scripts/artifacts.mjs", "--check"]);
  stage("anvil", process.execPath, ["scripts/local-anvil.mjs"]);
  stage("whitespace", "git", ["diff", "--check"]);
  evidence.status = "PASS";
  save();
  console.log(
    `Validation PASS (${evidence.tests.reportedTotal} Foundry-reported cases; remote CI not observed by agent)`,
  );
} catch (error) {
  evidence.status = "FAIL";
  save();
  throw error;
}
