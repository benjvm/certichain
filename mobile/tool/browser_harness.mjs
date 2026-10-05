import { spawn, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

// Diagnostics are allowlisted, never raw Chrome output, expression text, URLs,
// remote-object values, request bodies, tokens or application exception messages.
export function cdpFailure(method, detail = {}) {
  const kind = new Set([
      "Error",
      "TypeError",
      "ReferenceError",
      "RangeError",
      "SyntaxError",
      "URIError",
      "EvalError",
      "AggregateError",
      "DOMException",
    ]).has(detail.exception?.className)
    ? detail.exception.className
    : "Error";
  const code = Number.isInteger(detail.code) ? detail.code : "exception";
  const transient = detail.code === -32000 &&
    /^(Cannot find context with specified id|Execution context was destroyed|Inspected target navigated or closed)/
      .test(detail.message ?? "");
  const error = new Error(
    `${method}: ${kind}; code=${code}; line=${
      Number.isInteger(detail.lineNumber) ? detail.lineNumber : "unknown"
    }; column=${
      Number.isInteger(detail.columnNumber) ? detail.columnNumber : "unknown"
    }; context=${
      Number.isInteger(detail.executionContextId)
        ? detail.executionContextId
        : "unknown"
    }`,
  );
  error.transientNavigation = transient;
  return error;
}

export async function launchChrome(profile, args = [], timeout = 20000) {
  const executable = process.env.CHROME_EXECUTABLE ??
    (process.platform === "win32"
      ? "C:/Program Files/Google/Chrome/Application/chrome.exe"
      : "/usr/bin/google-chrome");
  const child = spawn(executable, [
    // Edge's Windows compatibility launcher otherwise exits successfully and
    // re-parents the actual browser, escaping process-tree teardown.
    ...(process.platform === "win32" && /msedge\.exe$/i.test(executable)
      ? ["--edge-skip-compat-layer-relaunch"]
      : []),
    "--headless=new",
    "--no-sandbox",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-debugging-port=0",
    `--user-data-dir=${profile}`,
    ...args,
  ], {
    windowsHide: true,
    detached: process.platform !== "win32",
    stdio: ["ignore", "ignore", "pipe"],
  });
  let launchError = false, launchCode = "none";
  const categories = new Set();
  child.on("error", (error) => {
    launchError = true;
    launchCode = ["ENOENT", "EACCES", "EPERM"].includes(error.code)
      ? error.code
      : "other";
  });
  child.stderr.on("data", (chunk) => {
    const sample = chunk.toString().slice(0, 4096);
    for (
      const [key, regex] of Object.entries({
        devtools: /DevTools listening/,
        profile: /Singleton|user data directory/,
        sandbox: /sandbox/,
        display: /DISPLAY|X server/,
        dbus: /dbus/,
        crash: /FATAL|crash|segmentation/i,
      })
    ) {
      if (regex.test(sample)) categories.add(key);
    }
  });
  const diagnostic = () =>
    `launch_error=${launchError}; launch_code=${launchCode}; exit=${
      child.exitCode ?? "none"
    }; signal=${child.signalCode ?? "none"}; categories=${
      [...categories].join(",") || "none"
    }`;
  const deadline = Date.now() + timeout;
  try {
    while (Date.now() < deadline) {
      if (launchError || child.exitCode !== null || child.signalCode !== null) {
        throw new Error(`Chrome exited before ready: ${diagnostic()}`);
      }
      try {
        const port = Number(
          readFileSync(join(profile, "DevToolsActivePort"), "utf8").split(
            "\n",
          )[0],
        );
        if (port > 0 && port <= 65535) {
          const response = await fetch(
            `http://127.0.0.1:${port}/json/version`,
            { signal: AbortSignal.timeout(1000) },
          );
          if (response.ok) return { child, port, diagnostic };
        }
      } catch {
        /* DevTools file/socket not ready yet; bounded startup only. */
      }
      await delay(50);
    }
    throw new Error(`Chrome startup deadline: ${diagnostic()}`);
  } catch (error) {
    await stopChrome(child);
    throw error;
  }
}

export async function connectCdp(url, onEvent = () => {}) {
  const socket = new WebSocket(url);
  const pending = new Map();
  let sequence = 0;
  const rejectAll = () => {
    for (const item of pending.values()) {
      clearTimeout(item.timer);
      item.reject(new Error("CDP socket closed"));
    }
    pending.clear();
  };
  socket.addEventListener("close", rejectAll);
  socket.addEventListener("error", rejectAll);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.close();
      reject(new Error("CDP connection deadline"));
    }, 10000);
    socket.addEventListener("open", () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
    socket.addEventListener("error", () => {
      clearTimeout(timer);
      reject(new Error("CDP connection failed"));
    }, { once: true });
  });
  socket.addEventListener("message", (event) => {
    const m = JSON.parse(event.data);
    if (m.id) {
      const item = pending.get(m.id);
      if (!item) return;
      clearTimeout(item.timer);
      pending.delete(m.id);
      m.error
        ? item.reject(cdpFailure(item.method, m.error))
        : item.resolve(m.result);
    } else onEvent(m);
  });
  const command = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++sequence;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`CDP deadline: ${method}`));
      }, 25000);
      pending.set(id, { resolve, reject, timer, method });
      socket.send(JSON.stringify({ id, method, params }));
    });
  command.close = () => {
    rejectAll();
    socket.close();
  };
  return command;
}

// Reload acknowledges a command, not a committed new document. Wait for a new
// loader, create a world in that document, then wait for DOM readiness. Reading
// the old ready marker or a context with no documentElement is never success.
export async function navigateDocument(cdp, method, params = {}) {
  const previous = (await cdp("Page.getFrameTree")).frameTree.frame.loaderId;
  cdp.documentContext = undefined;
  const result = await cdp(method, params);
  if (result.errorText) throw new Error("Browser navigation failed");
  // CDP omits loaderId for a same-document (hash/history) navigation.
  await prepareDocument(
    cdp,
    method === "Page.navigate" && !result.loaderId ? undefined : previous,
  );
}

export async function prepareDocument(cdp, previousLoader) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    try {
      const frame = (await cdp("Page.getFrameTree")).frameTree.frame;
      if (previousLoader && frame.loaderId === previousLoader) {
        await delay(50);
        continue;
      }
      const world = await cdp("Page.createIsolatedWorld", {
        frameId: frame.id,
        worldName: "certichain-harness",
      });
      cdp.documentContext = world.executionContextId;
      if (
        await evaluate(
          cdp,
          "!!document.documentElement && ['interactive','complete'].includes(document.readyState)",
        )
      ) return;
    } catch (error) {
      if (!error.transientNavigation) throw error;
    }
    await delay(50);
  }
  throw new Error("New browser document/context deadline");
}

export async function evaluate(cdp, expression) {
  const r = await cdp("Runtime.evaluate", {
    expression,
    contextId: cdp.documentContext,
    returnByValue: true,
    awaitPromise: true,
    userGesture: true,
  });
  if (r.exceptionDetails) {
    throw cdpFailure("Runtime.evaluate", r.exceptionDetails);
  }
  return r.result?.value;
}

// Own process group on Unix, process tree on Windows. Await bounded exit before
// removing the profile: browser children can still flush files after SIGTERM.
export async function stopChrome(child) {
  if (!child?.pid) return;
  if (process.platform === "win32") {
    if (child.exitCode === null && child.signalCode === null) {
      spawnSync("taskkill", ["/pid", String(child.pid), "/t", "/f"], {
        windowsHide: true,
        stdio: "ignore",
        timeout: 5000,
      });
    }
  } else {
    try {
      process.kill(-child.pid, "SIGTERM");
    } catch { /* already exited */ }
  }
  const deadline = Date.now() + 2000;
  while (
    child.exitCode === null && child.signalCode === null &&
    Date.now() < deadline
  ) {
    await delay(50);
  }
  if (process.platform !== "win32") {
    try {
      process.kill(-child.pid, "SIGKILL");
    } catch { /* group exited */ }
  }
  await delay(200);
}
