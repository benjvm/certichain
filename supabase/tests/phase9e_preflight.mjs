import process from "node:process";
import { spawnSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { lock, verifyVersions } from "../../blockchain/scripts/common.mjs";
import { sourceRevision } from "../../mobile/tool/browser_harness.mjs";
import { evidenceContext } from "./phase10_evidence.mjs";

const backendOnly = process.argv.includes("--backend-only");
const context = process.argv.includes("--phase10")
  ? evidenceContext(process.cwd())
  : sourceRevision(process.cwd());
const run = (command, args) => {
  const result =
    process.platform === "win32" && ["flutter", "npx"].includes(command)
      ? spawnSync("cmd.exe", ["/d", "/c", command, ...args], {
        encoding: "utf8",
        windowsHide: true,
        timeout: 60000,
      })
      : spawnSync(command, args, {
        encoding: "utf8",
        windowsHide: true,
        timeout: 60000,
      });
  if (result.status !== 0) {
    throw new Error(`Required tool unavailable: ${command}`);
  }
  return result.stdout.trim();
};
if (process.version !== "v24.14.0") {
  throw new Error("Use Node 24.14.0 from .node-version");
}
if (process.env.CERTICHAIN_TEST_CAMERA !== "0") {
  throw new Error("Camera must be disabled");
}
verifyVersions();
const supabase = run(process.env.SUPABASE_CLI ?? "supabase", ["--version"]);
if (supabase !== "2.117.0") throw new Error("Expected Supabase CLI 2.117.0");
const deno = run("npx", ["--yes", "deno@2.2.12", "--version"]);
if (!deno.startsWith("deno 2.2.12 ")) throw new Error("Expected Deno 2.2.12");
const docker = run("docker", ["version", "--format", "{{.Server.Version}}"]);
let flutter = null;
if (!backendOnly) {
  flutter = JSON.parse(run("flutter", ["--version", "--machine"]));
  if (
    flutter.frameworkVersion !== "3.47.4" ||
    flutter.frameworkRevision !== "9584c6713b324636289d067944a46fd6b49df14b" ||
    flutter.dartSdkVersion !== "3.13.3"
  ) {
    throw new Error(
      "Use the existing pinned Flutter 3.47.4 / Dart 3.13.3 revision",
    );
  }
}
const versions = {
  node: process.version,
  supabase,
  deno: "2.2.12",
  docker,
  foundry: lock.foundry.version,
  solidity: lock.solidity.version,
  flutter: flutter?.frameworkVersion ?? "NOT_RUN",
  dart: flutter?.dartSdkVersion ?? "NOT_RUN",
  flutter_revision: flutter?.frameworkRevision ?? null,
};
const evidence = resolve(
  process.argv.includes("--phase10")
    ? "mobile/build/phase10-evidence"
    : "mobile/build/phase9e-evidence",
);
mkdirSync(evidence, { recursive: true });
if (!backendOnly) rmSync(resolve(evidence, "browser.json"), { force: true });
writeFileSync(
  resolve(evidence, "preflight.json"),
  JSON.stringify(
    {
      ...context,
      evaluated_at: new Date().toISOString(),
      versions,
      result: "PASS",
    },
    null,
    2,
  ),
);
writeFileSync(
  resolve(evidence, "result.json"),
  JSON.stringify(
    {
      ...context,
      evaluated_at: new Date().toISOString(),
      result: "NOT_RUN",
      mode: backendOnly ? "backend-only" : "full",
      reason: "Acceptance has not completed",
      versions,
      flutter: "NOT_RUN",
      cleanup: "NOT_RUN",
      stack_cleanup: "NOT_RUN",
      camera: "NOT_RUN",
      camera_reason:
        "Omitidas por instrucción del usuario; no hay cámara física disponible",
    },
    null,
    2,
  ),
);
console.log(
  JSON.stringify({
    stage: process.argv.includes("--phase10") ? "10 preflight" : "9E preflight",
    result: "PASS",
    versions,
  }),
);
