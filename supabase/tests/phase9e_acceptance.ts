import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { runVerificationAcceptance } from "./blockchain_verification_integration.ts";
import { phase9eChecks } from "./phase9e_checks.ts";

const root = Deno.env.get("CERTICHAIN_SOURCE_ROOT") ?? Deno.cwd();
const { sourceRevision } = await import(
  pathToFileURL(resolve(root, "mobile/tool/browser_harness.mjs")).href
);
const evidence = resolve(root, "mobile/build/phase9e-evidence");
mkdirSync(evidence, { recursive: true });
const preflight = JSON.parse(
  readFileSync(resolve(evidence, "preflight.json"), "utf8"),
);
const backendOnly = Deno.args.includes("--backend-only");
const scenarios: { case: string; result: string }[] = [];
const summary: Record<string, unknown> = {
  ...sourceRevision(root),
  evaluated_at: new Date().toISOString(),
  mode: backendOnly ? "backend-only" : "full",
  versions: preflight.versions,
  result: "FAIL",
  scenarios,
  flutter: "NOT_RUN",
  cleanup: "NOT_RUN",
  camera: "NOT_RUN",
  camera_reason:
    "Omitidas por instrucción del usuario; no hay cámara física disponible",
  platforms: {
    android: "NOT_RUN",
    ios: "NOT_RUN",
    firefox: "NOT_RUN",
    safari: "NOT_RUN",
    sepolia: "NOT_RUN",
    human_accessibility: "NOT_RUN",
  },
};
try {
  const result = await runVerificationAcceptance({
    phase: "9e",
    backendOnly,
    extend: phase9eChecks,
    onScenario: (scenario) => scenarios.push(scenario),
  });
  Object.assign(summary, result, {
    result: "PASS",
    flutter: backendOnly ? "NOT_RUN" : "PASS",
    cleanup: "PASS owned Anvil network Edge and restore destinations",
  });
} catch {
  if (!backendOnly && existsSync(resolve(evidence, "browser.json"))) {
    summary.flutter = "FAIL";
    summary.browser = JSON.parse(
      readFileSync(resolve(evidence, "browser.json"), "utf8"),
    );
  }
  summary.reason =
    "Acceptance failed; inspect the last sanitized scenario or stage. No PASS for unexecuted stages.";
  throw new Error("9E acceptance failed");
} finally {
  writeFileSync(
    resolve(evidence, "result.json"),
    JSON.stringify(summary, null, 2),
  );
  appendFileSync(
    resolve(evidence, "attempts.ndjson"),
    JSON.stringify(summary) + "\n",
  );
  writeFileSync(
    resolve(evidence, backendOnly ? "backend-only.json" : "full.json"),
    JSON.stringify(summary, null, 2),
  );
  console.log(
    JSON.stringify({
      suite: "phase9e-acceptance",
      result: summary.result,
      mode: summary.mode,
      flutter: summary.flutter,
    }),
  );
}
