// Run identity for the existing local runner, CI, preflight and release journey.
// Never retain bodies, environment variables, paths or upstream diagnostics.
import { randomUUID } from "node:crypto";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import process from "node:process";

const directory = (root) => resolve(root, "mobile/build/phase10-evidence");
const read = (root, file) =>
  JSON.parse(
    readFileSync(resolve(directory(root), file), "utf8").replace(/^\uFEFF/, ""),
  );
const write = (root, file, data) =>
  writeFileSync(resolve(directory(root), file), JSON.stringify(data, null, 2));
export function beginEvidence(root, mode, revision) {
  if (!["full", "backend-only"].includes(mode)) {
    throw new Error("Invalid acceptance mode");
  }
  const context = {
    ...revision(root),
    run_id: randomUUID(),
    started_at: new Date().toISOString(),
    mode,
  };
  const dir = directory(root);
  mkdirSync(dir, { recursive: true });
  const history = resolve(dir, "history", context.run_id);
  for (
    const file of [
      "run.json",
      "preflight.json",
      "result.json",
      "full.json",
      "backend-only.json",
      "browser.json",
    ]
  ) {
    if (existsSync(resolve(dir, file))) {
      mkdirSync(history, { recursive: true });
      renameSync(resolve(dir, file), resolve(history, file));
    }
  }
  write(root, "run.json", context);
  saveEvidence(root, {
    ...context,
    evaluated_at: context.started_at,
    stage: "initialization",
    result: "NOT_RUN",
    flutter: "NOT_RUN",
    cleanup: "NOT_RUN",
    stack_cleanup: "NOT_RUN",
    camera: "NOT_RUN",
    camera_reason:
      "Omitidas por instrucción del usuario; no hay cámara física disponible",
  });
  return context;
}
export function evidenceContext(
  root,
  runId = process.env.CERTICHAIN_ACCEPTANCE_RUN_ID,
) {
  const context = read(root, "run.json");
  if (
    !runId || context.run_id !== runId || !/^[0-9a-f-]{36}$/.test(runId) ||
    !["full", "backend-only"].includes(context.mode)
  ) {
    throw new Error("Current acceptance run identity required");
  }
  return context;
}
export function belongsToRun(value, context) {
  return value?.run_id === context.run_id &&
    value.source_commit === context.source_commit &&
    value.working_tree_dirty === context.working_tree_dirty &&
    Number.isFinite(Date.parse(value.evaluated_at)) &&
    Date.parse(value.evaluated_at) >= Date.parse(context.started_at);
}
export function currentBrowser(root, context) {
  try {
    const value = read(root, "browser.json");
    return belongsToRun(value, context) ? value : null;
  } catch {
    return null;
  }
}
export function saveEvidence(root, summary) {
  write(root, "result.json", summary);
  write(
    root,
    summary.mode === "full" ? "full.json" : "backend-only.json",
    summary,
  );
}
export function finishEvidence(root, runId, exitCode, cleanup) {
  const context = evidenceContext(root, runId);
  if (
    !["PASS", "FAIL", "NOT_RUN"].includes(cleanup) || ![0, 1].includes(exitCode)
  ) throw new Error("Invalid acceptance outcome");
  const summary = read(root, "result.json");
  if (!belongsToRun(summary, context) || summary.finalized_at) {
    throw new Error("Cannot finalize stale or completed acceptance");
  }
  const browser = currentBrowser(root, context);
  if (
    context.mode === "full" && summary.flutter === "PASS" &&
    browser?.result !== "PASS"
  ) summary.flutter = "NOT_RUN";
  summary.stack_cleanup = cleanup;
  summary.result =
    exitCode === 0 && cleanup === "PASS" && summary.result === "PASS" &&
      (context.mode === "backend-only" || summary.flutter === "PASS")
      ? "PASS"
      : "FAIL";
  summary.finalized_at = new Date().toISOString();
  saveEvidence(root, summary);
  appendFileSync(
    resolve(directory(root), "attempts.ndjson"),
    JSON.stringify(summary) + "\n",
  );
  return summary;
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  const [action, ...args] = process.argv.slice(2),
    root = process.env.CERTICHAIN_SOURCE_ROOT ?? process.cwd();
  if (action === "begin") {
    const { sourceRevision } = await import(
      pathToFileURL(resolve(root, "mobile/tool/browser_harness.mjs")).href
    );
    console.log(
      beginEvidence(
        root,
        args.includes("--backend-only") ? "backend-only" : "full",
        sourceRevision,
      ).run_id,
    );
  } else if (action === "stage") {
    const context = evidenceContext(root), summary = read(root, "result.json");
    if (
      !belongsToRun(summary, context) ||
      !/^[A-Za-z0-9 ,.-]{1,100}$/.test(args[0] ?? "")
    ) throw new Error("Invalid acceptance stage");
    saveEvidence(root, { ...summary, stage: args[0] });
  } else if (action === "finish") {
    const summary = finishEvidence(
      root,
      process.env.CERTICHAIN_ACCEPTANCE_RUN_ID,
      Number(args[0]),
      args[1],
    );
    console.log(
      JSON.stringify({
        run_id: summary.run_id,
        result: summary.result,
        stack_cleanup: summary.stack_cleanup,
        flutter: summary.flutter,
      }),
    );
    if (summary.result !== "PASS") process.exitCode = 1;
  } else throw new Error("Unknown acceptance evidence action");
}
