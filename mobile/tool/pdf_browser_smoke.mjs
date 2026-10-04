import { createServer } from "node:http";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { extname, join, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { setTimeout as delay } from "node:timers/promises";

// Isolated headless Chrome, serving the test build only on loopback. No accounts.
const root = resolve("build/browser-smoke");
const profile = mkdtempSync(join(tmpdir(), "certichain-chrome-pdf-"));
if (!resolve(profile).startsWith(resolve(tmpdir()) + sep)) {
  throw new Error("Unsafe temporary profile");
}
const types = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".wasm": "application/wasm",
  ".json": "application/json",
  ".ttf": "font/ttf",
  ".png": "image/png",
};
const server = createServer((request, response) => {
  const path = resolve(
    root,
    "." +
      decodeURIComponent(
        new URL(request.url, "http://localhost").pathname === "/"
          ? "/index.html"
          : new URL(request.url, "http://localhost").pathname,
      ),
  );
  if (!path.startsWith(root + sep)) {
    response.writeHead(404);
    response.end();
    return;
  }
  try {
    response.writeHead(200, {
      "content-type": types[extname(path)] ?? "application/octet-stream",
    });
    response.end(readFileSync(path));
  } catch {
    response.writeHead(404);
    response.end();
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const executable = process.env.CHROME_EXECUTABLE ??
  (process.platform === "win32"
    ? "C:/Program Files/Google/Chrome/Application/chrome.exe"
    : "/usr/bin/google-chrome");
const chrome = spawn(executable, [
  "--headless=new",
  "--no-sandbox",
  "--disable-gpu",
  "--no-first-run",
  "--no-default-browser-check",
  "--remote-debugging-port=0",
  `--user-data-dir=${profile}`,
  `http://127.0.0.1:${server.address().port}`,
], { windowsHide: true, stdio: "ignore" });
let socket;
try {
  let port;
  for (let i = 0; i < 100; i++) {
    try {
      port = Number(
        readFileSync(join(profile, "DevToolsActivePort"), "utf8").split(
          "\n",
        )[0],
      );
      break;
    } catch {
      await delay(100);
    }
  }
  if (!port) throw new Error("Isolated Chrome did not start");
  let page;
  for (let i = 0; i < 100; i++) {
    const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`))
      .json();
    page = pages.find((p) => p.type === "page");
    if (page) break;
    await delay(100);
  }
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => socket.onopen = r);
  let id = 0;
  function body() {
    const current = ++id;
    return new Promise((r) => {
      socket.addEventListener("message", function listener(event) {
        const message = JSON.parse(event.data);
        if (message.id === current) {
          socket.removeEventListener("message", listener);
          r(message.result?.result?.value ?? "");
        }
      });
      socket.send(
        JSON.stringify({
          id: current,
          method: "Runtime.evaluate",
          params: {
            expression: "document.body.innerText",
            returnByValue: true,
          },
        }),
      );
    });
  }
  let result = "";
  for (let i = 0; i < 150; i++) {
    result = await body();
    if (result.startsWith("PASS") || result.startsWith("FAIL")) break;
    await delay(200);
  }
  if (!result.startsWith("PASS")) {
    throw new Error(`Chrome PDF smoke did not pass: ${result}`);
  }
  console.log(result);
} finally {
  socket?.close();
  if (process.platform === "win32") {
    spawnSync("taskkill", ["/pid", String(chrome.pid), "/t", "/f"], {
      windowsHide: true,
      stdio: "ignore",
    });
  } else chrome.kill("SIGTERM");
  server.close();
  await delay(500);
  rmSync(profile, {
    recursive: true,
    force: true,
    maxRetries: 5,
    retryDelay: 200,
  });
}
