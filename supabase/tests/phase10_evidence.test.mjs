import { test } from "node:test";
import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import {
  beginEvidence,
  belongsToRun,
  currentBrowser,
  evidenceContext,
  finishEvidence,
  saveEvidence,
} from "./phase10_evidence.mjs";

const revision = () => ({
  source_commit: "a".repeat(40),
  working_tree_dirty: true,
});
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), "certichain-evidence-test-"));
  const dir = join(root, "mobile/build/phase10-evidence");
  mkdirSync(dir, { recursive: true });
  t.after(() => {
    assert.ok(resolve(root).startsWith(resolve(tmpdir()) + sep));
    assert.match(root, /certichain-evidence-test-[^/\\]+$/);
    rmSync(root, { recursive: true });
  });
  const read = (name) => JSON.parse(readFileSync(join(dir, name), "utf8"));
  const write = (name, value) =>
    writeFileSync(join(dir, name), JSON.stringify(value));
  return { root, dir, read, write };
}
test("new run archives all old success artifacts before preflight can fail", (t) => {
  const f = fixture(t);
  for (
    const file of ["browser.json", "result.json", "full.json", "preflight.json"]
  ) f.write(file, { result: "PASS", run_id: "old" });
  const c = beginEvidence(f.root, "full", revision);
  assert.equal(f.read("result.json").flutter, "NOT_RUN");
  assert.equal(f.read("full.json").result, "NOT_RUN");
  assert.equal(f.read(`history/${c.run_id}/browser.json`).result, "PASS");
  assert.equal(currentBrowser(f.root, c), null);
  assert.throws(() => evidenceContext(f.root, "old"));
  const failed = finishEvidence(f.root, c.run_id, 1, "NOT_RUN");
  assert.equal(failed.result, "FAIL");
  assert.equal(failed.flutter, "NOT_RUN");
  assert.equal(failed.stack_cleanup, "NOT_RUN");
});
test("old browser success cannot accredit a failed current acceptance", (t) => {
  const f = fixture(t), c = beginEvidence(f.root, "full", revision);
  const summary = { ...f.read("result.json"), result: "PASS", flutter: "PASS" };
  saveEvidence(f.root, summary);
  f.write("browser.json", { ...summary, run_id: "different" });
  assert.equal(currentBrowser(f.root, c), null);
  const failed = finishEvidence(f.root, c.run_id, 0, "PASS");
  assert.equal(failed.flutter, "NOT_RUN");
  assert.equal(failed.result, "FAIL");
});
test("source, timestamp and run ID all belong to this execution", (t) => {
  const f = fixture(t), c = beginEvidence(f.root, "full", revision);
  const value = {
    ...c,
    evaluated_at: new Date().toISOString(),
    result: "PASS",
  };
  assert.equal(belongsToRun(value, c), true);
  for (
    const changed of [
      { run_id: "old" },
      { source_commit: "b".repeat(40) },
      { working_tree_dirty: false },
      { evaluated_at: "2000-01-01T00:00:00Z" },
      { evaluated_at: "bad" },
    ]
  ) {
    assert.equal(belongsToRun({ ...value, ...changed }, c), false);
  }
});
test("release and cleanup PASS finalize once, preserving current evidence", (t) => {
  const f = fixture(t), c = beginEvidence(f.root, "full", revision);
  const value = { ...f.read("result.json"), result: "PASS", flutter: "PASS" };
  saveEvidence(f.root, value);
  f.write("browser.json", value);
  assert.equal(finishEvidence(f.root, c.run_id, 0, "PASS").result, "PASS");
  assert.equal(f.read("full.json").stack_cleanup, "PASS");
  assert.throws(() => finishEvidence(f.root, c.run_id, 0, "PASS"));
  assert.equal(
    readFileSync(join(f.dir, "attempts.ndjson"), "utf8").trim().split("\n")
      .length,
    1,
  );
});
test("failed cleanup cannot be hidden by a successful backend-only result", (t) => {
  const f = fixture(t), c = beginEvidence(f.root, "backend-only", revision);
  saveEvidence(f.root, { ...f.read("result.json"), result: "PASS" });
  const summary = finishEvidence(f.root, c.run_id, 0, "FAIL");
  assert.equal(summary.result, "FAIL");
  assert.equal(summary.flutter, "NOT_RUN");
  assert.equal(f.read("backend-only.json").stack_cleanup, "FAIL");
});
test("a stale result is rejected instead of being rewritten as current cleanup", (t) => {
  const f = fixture(t), c = beginEvidence(f.root, "full", revision);
  f.write("result.json", { result: "PASS", run_id: "old" });
  assert.throws(() => finishEvidence(f.root, c.run_id, 0, "PASS"));
});
