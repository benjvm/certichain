import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import {
  connectCdp,
  evaluate,
  launchChrome,
  navigateDocument,
  stopChrome,
} from "./browser_harness.mjs";

const profile = mkdtempSync(join(tmpdir(), "certichain-cdp-smoke-"));
assert(resolve(profile).startsWith(resolve(tmpdir()) + sep));
const server = createServer((_req, res) => {
  res.writeHead(200, {
    "content-type": "text/html",
    "cache-control": "no-store",
  });
  res.end(
    "<!doctype html><html data-ready='new'><body>synthetic DOM only</body></html>",
  );
});
let child;
const connections = [];
let assertions = 0;
const originalExecutable = process.env.CHROME_EXECUTABLE;
try {
  process.env.CHROME_EXECUTABLE = join(profile, "missing-executable");
  await assert.rejects(
    launchChrome(profile),
    /Chrome exited before ready: launch_error=true/,
  );
  assertions++;
  process.env.CHROME_EXECUTABLE = process.execPath; // Node exits on Chrome flags.
  await assert.rejects(launchChrome(profile), /Chrome exited before ready/);
  assertions++;
  if (originalExecutable) process.env.CHROME_EXECUTABLE = originalExecutable;
  else delete process.env.CHROME_EXECUTABLE;
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const launch = await launchChrome(profile, ["about:blank"]);
  child = launch.child;
  const version =
    await (await fetch(`http://127.0.0.1:${launch.port}/json/version`)).json();
  const browser = await connectCdp(version.webSocketDebuggerUrl);
  connections.push(browser);
  const { browserContextId } = await browser("Target.createBrowserContext");
  const { targetId } = await browser("Target.createTarget", {
    url: "about:blank",
    browserContextId,
  });
  const targets =
    await (await fetch(`http://127.0.0.1:${launch.port}/json/list`)).json();
  const page = await connectCdp(
    targets.find((p) => p.id === targetId).webSocketDebuggerUrl,
  );
  connections.push(page);
  await page("Page.enable");
  await navigateDocument(page, "Page.navigate", {
    url: `http://127.0.0.1:${server.address().port}`,
  });
  for (let i = 0; i < 20; i++) {
    const oldContext = page.documentContext;
    await navigateDocument(page, "Page.reload", { ignoreCache: true });
    assert.equal(
      await evaluate(
        page,
        "document.documentElement.getAttribute('data-ready')",
      ),
      "new",
    );
    assertions++;
    await assert.rejects(
      page("Runtime.evaluate", { expression: "1", contextId: oldContext }),
      (error) => error.transientNavigation === true,
    );
    assertions++;
  }
  // Demonstrate the unchecked DOM probe's failure mechanism without alleging
  // that this synthetic state was the undocumented historical CI exception.
  await evaluate(page, "document.documentElement.remove()");
  await assert.rejects(
    evaluate(page, "document.documentElement.getAttribute('data-ready')"),
    /TypeError/,
  );
  assertions++;
  await navigateDocument(page, "Page.reload", { ignoreCache: true });
  await assert.rejects(
    evaluate(page, "throw new Error('synthetic-private-payload')"),
    (error) =>
      !error.message.includes("synthetic-private-payload") &&
      !error.transientNavigation,
  );
  assertions++;
  const pending = page("Runtime.evaluate", {
    expression: "new Promise(()=>{})",
    awaitPromise: true,
  });
  page.close();
  await assert.rejects(pending, /CDP socket closed/);
  assertions++;
  console.log(
    `PASS: ${assertions} real Chrome harness assertions; anonymous reload/context/DOM, launch errors and socket cleanup; ${process.platform}`,
  );
} finally {
  if (originalExecutable) process.env.CHROME_EXECUTABLE = originalExecutable;
  else delete process.env.CHROME_EXECUTABLE;
  connections.forEach((c) => c.close());
  await stopChrome(child);
  await new Promise((r) => server.close(r));
  rmSync(profile, {
    recursive: true,
    force: true,
    maxRetries: 5,
    retryDelay: 200,
  });
}
