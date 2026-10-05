import { test } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { createServer } from "node:http";
import { runtimeReady, watchRuntime } from "./edge_runtime.mjs";

function child() {
  const value = new EventEmitter();
  value.stdout = new EventEmitter();
  value.stderr = new EventEmitter();
  value.exitCode = null;
  value.signalCode = null;
  return value;
}
test("ready old server is ignored until the CURRENT serve marker; read-only probes", async () => {
  const process = child(), requests = [];
  const server = createServer((req, res) => {
    requests.push([req.method, req.url, req.headers.connection]);
    res.writeHead(
      req.url.includes("verify-certificate")
        ? 405
        : req.url.includes("functions")
        ? 401
        : 200,
    );
    res.end("{}");
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const local = {
    API_URL: `http://127.0.0.1:${server.address().port}`,
    ANON_KEY: "synthetic",
  };
  const runtime = { current: watchRuntime(process) };
  const ready = runtimeReady(runtime, local, 2000);
  try {
    await new Promise((r) => setTimeout(r, 150));
    assert.equal(requests.length, 0);
    process.stdout.emit(
      "data",
      Buffer.from("private discarded output\nServing func"),
    );
    assert.equal(runtime.current(), false);
    process.stdout.emit("data", Buffer.from("tions on loopback"));
    await ready;
    assert.deepEqual(requests.map((r) => r[0]), [
      "GET",
      "GET",
      "GET",
      "POST",
      "GET",
    ]);
    assert.ok(requests.every((r) => r[2] === "close"));
  } finally {
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
  }
});
test("process error, signal and premature exit fail immediately and safely", () => {
  for (const mode of ["error", "exit", "signal"]) {
    const process = child(), current = watchRuntime(process);
    if (mode === "error") process.emit("error", new Error("private-secret"));
    if (mode === "exit") process.exitCode = 1;
    if (mode === "signal") process.signalCode = "SIGTERM";
    assert.throws(current, /current process failed\/exited/);
  }
});
test("absent current launch marker has a bounded deadline and no probes", async () => {
  await assert.rejects(
    runtimeReady({ current: watchRuntime(child()) }, {}, 110),
    /deadline: auth; attempts=0/,
  );
});
