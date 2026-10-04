import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { decodeQr } from "./verify_qr.mjs";

if (process.env.CERTICHAIN_TEST_DISPOSABLE !== "1") {
  throw new Error("Requires an explicitly disposable local stack");
}
const build = resolve("build/public-verification-e2e");
const mainBuild = resolve("build/public-verification-main");
const backend = resolve(process.env.CERTICHAIN_TEST_BACKEND_ROOT ?? "..");
const { fixture, check, until, terminate } = await import(
  pathToFileURL(join(backend, "supabase/tests/local_issuance_fixture.mjs"))
);
const { sql } = await import(
  pathToFileURL(join(backend, "supabase/scripts/local_supabase.mjs"))
);
const profile = mkdtempSync(join(tmpdir(), "certichain-chrome-8b-"));
check(resolve(profile).startsWith(resolve(tmpdir()) + sep), "Unsafe profile");
const initialDirectory = process.cwd();
process.chdir(backend); // runtime/status always target this stack
const f = await fixture();
let chrome, server, failure;
const sockets = [];
let assertions = 0, publicRequests = 0;
function verify(condition, label) {
  check(condition, label);
  assertions++;
}
const origin = "http://127.0.0.1:7357";
let cert, record, originalBytes;
try {
  const issued = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: randomUUID(),
    title: "8B Public Certificate",
    expires_at: "2030-01-01T00:00:00Z",
  });
  verify(
    issued.status === 201,
    `Existing 7B production publication HTTP ${issued.status}`,
  );
  cert = issued.data.certificate_id;
  record = JSON.parse(
    sql(`SELECT row_to_json(c) FROM public.certificates c WHERE id='${cert}';`),
  );
  originalBytes = await f.stored(f.verified, cert);
  verify(
    record.credential_code !== cert,
    "Public code is independent of private id",
  );
  const expiredCode = randomUUID(),
    expiredCert = randomUUID(),
    expiredOp = randomUUID();
  // Synthetic historical publication with all production constraints enabled.
  // No clock, limiter counter or dates of an existing certificate are adjusted.
  sql(
    `INSERT INTO public.certificate_issuance_operations(id,institution_id,actor_id,holder_id,idempotency_key,request_fingerprint,pdf_hash,target_certificate_id,stored_hash,status,title,expires_at)
    VALUES('${expiredOp}','${f.verified}','${f.owner.id}','${f.holder.id}',gen_random_uuid(),repeat('a',64),'${record.document_hash}','${expiredCert}','${record.document_hash}','finalizing','8B Expired','2021-01-01T00:00:00.123456Z');
    INSERT INTO public.certificates(id,institution_id,issued_by,holder_id,title,credential_code,issued_at,expires_at,document_path,document_hash,issuance_operation_id)
    VALUES('${expiredCert}','${f.verified}','${f.owner.id}','${f.holder.id}','8B Expired','${expiredCode}','2020-01-01T00:00:00.654321Z','2021-01-01T00:00:00.123456Z','${f.verified}/${expiredCert}.pdf','${record.document_hash}','${expiredOp}');
    UPDATE public.certificate_issuance_operations SET status='completed',certificate_id='${expiredCert}' WHERE id='${expiredOp}';`,
  );
  const data = {
    apiUrl: f.local.API_URL,
    publicKey: f.local.ANON_KEY,
    holder: {
      id: f.holder.id,
      email: f.holder.email,
      password: f.holder.password,
    },
    outsider: {
      id: f.outsider.id,
      email: f.outsider.email,
      password: f.outsider.password,
    },
  };
  verify(
    !JSON.stringify(data).includes(f.local.SERVICE_ROLE_KEY),
    "No server secret sent to test browser",
  );
  const types = {
    ".html": "text/html",
    ".js": "text/javascript",
    ".json": "application/json",
    ".wasm": "application/wasm",
    ".ttf": "font/ttf",
    ".png": "image/png",
  };
  server = createServer((req, res) => {
    try {
      const path = new URL(req.url, origin).pathname;
      res.setHeader("cache-control", "no-store");
      if (path === "/fixture") {
        res.setHeader("content-type", "application/json");
        res.end(JSON.stringify(data));
        return;
      }
      const production = path.startsWith("/production/");
      const staticRoot = production ? mainBuild : build;
      const relative = production ? path.substring(11) : path;
      const file = resolve(
        staticRoot,
        "." + decodeURIComponent(relative === "/" ? "/index.html" : relative),
      );
      check(file.startsWith(staticRoot + sep), "Safe static path");
      res.setHeader(
        "content-type",
        types[extname(file)] ?? "application/octet-stream",
      );
      res.end(readFileSync(file));
    } catch (_) {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise((r, j) => {
    server.once("error", j);
    server.listen(7357, "127.0.0.1", r);
  });
  verify(
    !readFileSync(join(build, "main.dart.js"), "utf8").includes(
      f.local.SERVICE_ROLE_KEY,
    ),
    "No service key in Web build",
  );
  chrome = spawn(
    process.env.CHROME_EXECUTABLE ??
      (process.platform === "win32"
        ? "C:/Program Files/Google/Chrome/Application/chrome.exe"
        : "/usr/bin/google-chrome"),
    [
      "--headless=new",
      "--no-sandbox",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--remote-debugging-port=0",
      `--user-data-dir=${profile}`,
      "about:blank",
    ],
    { windowsHide: true, stdio: "ignore" },
  );
  let port;
  await until(() => {
    try {
      port = Number(
        readFileSync(join(profile, "DevToolsActivePort"), "utf8").split(
          "\n",
        )[0],
      );
      return Boolean(port);
    } catch {
      return false;
    }
  }, "Chrome startup");
  async function connect(url) {
    const socket = new WebSocket(url);
    sockets.push(socket);
    await new Promise((r) => socket.onopen = r);
    let seq = 0;
    const pending = new Map();
    const publicIds = new Set(), extra = new Map();
    function assertHeaders(headers) {
      if (
        Object.keys(headers).some((k) =>
          ["authorization", "apikey", "cookie"].includes(k.toLowerCase())
        )
      ) {
        failure = new Error("Actual public browser request sent credentials");
      }
    }
    socket.addEventListener("message", (event) => {
      const m = JSON.parse(event.data);
      if (m.id) {
        const p = pending.get(m.id);
        if (p) {
          clearTimeout(p.timer);
          pending.delete(m.id);
          m.error
            ? p.reject(new Error("CDP command failed"))
            : p.resolve(m.result);
        }
      }
      if (
        m.method === "Network.requestWillBeSent" &&
        m.params.request.url.endsWith("/functions/v1/verify-certificate") &&
        m.params.request.method === "POST"
      ) {
        publicRequests++;
        publicIds.add(m.params.requestId);
        if (extra.has(m.params.requestId)) {
          assertHeaders(extra.get(m.params.requestId));
        }
        const headers = Object.keys(m.params.request.headers).map((k) =>
          k.toLowerCase()
        );
        if (
          headers.some((k) => ["authorization", "apikey", "cookie"].includes(k))
        ) failure = new Error("Public browser sent credentials");
        const body = JSON.parse(m.params.request.postData ?? "{}");
        if (Object.keys(body).join(",") !== "credential_code") {
          failure = new Error("Public browser widened body");
        }
      }
      if (m.method === "Network.requestWillBeSentExtraInfo") {
        extra.set(m.params.requestId, m.params.headers);
        if (publicIds.has(m.params.requestId)) assertHeaders(m.params.headers);
      }
    });
    return async (method, params = {}) =>
      await new Promise((resolve, reject) => {
        const id = ++seq,
          timer = setTimeout(() => {
            pending.delete(id);
            reject(new Error("CDP deadline"));
          }, 25000);
        pending.set(id, { resolve, reject, timer });
        socket.send(JSON.stringify({ id, method, params }));
      });
  }
  const version = await (await fetch(`http://127.0.0.1:${port}/json/version`))
    .json();
  const browser = await connect(version.webSocketDebuggerUrl);
  const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`))
    .json();
  const page = await connect(
    pages.find((p) => p.type === "page").webSocketDebuggerUrl,
  );
  await page("Network.enable");
  await page("Page.enable");
  await page("Emulation.setDeviceMetricsOverride", {
    width: 390,
    height: 844,
    deviceScaleFactor: 1,
    mobile: false,
  });
  async function evaluate(cdp, expression) {
    const r = await cdp("Runtime.evaluate", {
      expression,
      returnByValue: true,
      awaitPromise: true,
      userGesture: true,
    });
    if (r.exceptionDetails) throw new Error("Browser expression failed");
    return r.result?.value;
  }
  async function state(cdp = page) {
    if (failure) throw failure;
    return JSON.parse(
      await evaluate(
        cdp,
        "document.documentElement.getAttribute('data-8b-state') || '{}'",
      ),
    );
  }
  async function ready(cdp = page) {
    await until(
      async () => {
        const v = await evaluate(
          cdp,
          "document.documentElement.getAttribute('data-8b-ready') || ''",
        );
        if (v === "FAIL") throw new Error("Flutter harness startup failed");
        return v === "1";
      },
      "App ready",
      60000,
    );
  }
  let commandId = 0;
  async function command(action, fields = {}, cdp = page) {
    const id = ++commandId;
    await evaluate(
      cdp,
      `document.documentElement.setAttribute('data-8b-command',${
        JSON.stringify(JSON.stringify({ id, action, ...fields }))
      })`,
    );
    let result;
    await until(
      async () => {
        result = JSON.parse(
          await evaluate(
            cdp,
            "document.documentElement.getAttribute('data-8b-result') || '{}'",
          ),
        );
        return result.id === id;
      },
      `UI action ${action}`,
      25000,
    );
    verify(result.ok, `UI action ${action}`);
  }
  async function outcome(label, cdp = page) {
    await until(
      async () => (await state(cdp)).texts?.includes(label),
      label,
      25000,
    );
  }
  const link = `${origin}/#/verify/${record.credential_code}`;
  await page("Page.navigate", { url: link });
  await ready();
  await outcome("Registro encontrado y vigente");
  writeFileSync(
    join(build, "public-390.png"),
    Buffer.from(
      (await page("Page.captureScreenshot", { format: "png" })).data,
      "base64",
    ),
  );
  verify(
    (await state()).session === null && (await state()).queries === 1,
    "Direct link anonymous, Auth initialization caused exactly one query",
  );
  await page("Page.reload", { ignoreCache: true });
  await ready();
  await outcome("Registro encontrado y vigente");
  verify(
    (await state()).code === record.credential_code &&
      (await state()).queries === 1,
    "Reload preserved code, one query",
  );
  await command("rebuild");
  verify((await state()).queries === 1, "Rebuild has no automatic query");
  await command("login", { user: "holder" });
  await until(
    async () => (await state()).session === f.holder.id,
    "Holder session",
  );
  verify(
    (await state()).public && (await state()).queries === 1,
    "Auth change preserved public result",
  );
  await command("renew");
  verify(
    (await state()).queries === 1,
    "Token restore/refresh does not duplicate query",
  );
  await command("click", { label: "Consultar otro código" });
  await command("enter", {
    label: "Código del certificado",
    value: randomUUID(),
  });
  await command("click", { label: "Verificar" });
  await outcome("No encontramos un registro verificable con este código");
  const unknown = (await state()).code;
  verify(
    (await evaluate(page, "location.hash")).endsWith(unknown),
    "Manual code is navigable URL",
  );
  await evaluate(page, "history.back()");
  await until(async () => (await state()).code === "", "Back to form");
  await evaluate(page, "history.back()");
  await outcome("Registro encontrado y vigente");
  verify(
    (await state()).code === record.credential_code,
    "Browser back restores certificate code",
  );
  await evaluate(page, "history.forward()");
  await until(async () => (await state()).code === "", "Forward to form");
  await evaluate(page, "history.forward()");
  await outcome("No encontramos un registro verificable con este código");
  verify(
    (await state()).code === unknown,
    "Browser forward restores unknown code",
  );
  await page("Page.navigate", { url: `${origin}/#/verify/${expiredCode}` });
  await ready();
  await outcome("Certificado caducado");
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "suspended",
  }, f.platform.token);
  await page("Page.navigate", { url: link });
  await ready();
  await outcome("Emisor sin aprobación vigente");
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "pending",
  }, f.platform.token);
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "verified",
  }, f.platform.token);
  // Server error must keep holder session and remain distinct from not_found.
  sql(
    "REVOKE EXECUTE ON FUNCTION public.lookup_public_certificate(text) FROM service_role;",
  );
  try {
    await command("click", { label: "Actualizar comprobación" });
    await outcome("La comprobación está temporalmente no disponible.");
    verify(
      (await state()).session === f.holder.id,
      "Public 503 preserves private session",
    );
  } finally {
    sql(
      "GRANT EXECUTE ON FUNCTION public.lookup_public_certificate(text) TO service_role;",
    );
  }
  await command("click", { label: "Volver" });
  await command("open", { certificate: cert });
  await command("click", { label: "Mostrar QR y enlace" });
  await until(async () => (await state()).qr, "Own QR");
  await browser("Browser.grantPermissions", {
    origin,
    permissions: ["clipboardReadWrite", "clipboardSanitizedWrite"],
  });
  await page("Page.bringToFront");
  await command("click", { label: "Copiar enlace" });
  await outcome("Enlace copiado");
  const copied = await evaluate(page, "navigator.clipboard.readText()");
  verify(copied === link, "Real clipboard contains exact public link");
  await command("qr");
  writeFileSync(
    join(build, "share-390.png"),
    Buffer.from(
      (await page("Page.captureScreenshot", { format: "png" })).data,
      "base64",
    ),
  );
  decodeQr(
    Buffer.from(
      await evaluate(
        page,
        "document.documentElement.getAttribute('data-8b-qr')",
      ),
      "base64",
    ),
    link,
  );
  assertions++;
  // New isolated context has no private session storage.
  const { browserContextId } = await browser("Target.createBrowserContext");
  const { targetId } = await browser("Target.createTarget", {
    url: copied,
    browserContextId,
  });
  let isolated;
  await until(async () => {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`))
      .json();
    isolated = list.find((p) => p.id === targetId);
    return Boolean(isolated);
  }, "Anonymous context target");
  const anonymous = await connect(isolated.webSocketDebuggerUrl);
  await anonymous("Network.enable");
  await ready(anonymous);
  await outcome("Registro encontrado y vigente", anonymous);
  verify(
    (await state(anonymous)).session === null &&
      (await state(anonymous)).code === record.credential_code,
    "Copied link resolves same record without session",
  );
  await anonymous("Page.reload", { ignoreCache: true });
  await ready(anonymous);
  await outcome("Registro encontrado y vigente", anonymous);
  verify(
    (await state(anonymous)).queries === 1,
    "Anonymous copied link reload",
  );
  sql(`UPDATE public.certificates SET status='revoked' WHERE id='${cert}';`);
  await command("click", { label: "Actualizar comprobación" }, anonymous);
  await outcome("Certificado revocado", anonymous);
  await command("qr");
  decodeQr(
    Buffer.from(
      await evaluate(
        page,
        "document.documentElement.getAttribute('data-8b-qr')",
      ),
      "base64",
    ),
    link,
  );
  assertions++;
  verify(
    (await f.stored(f.verified, cert)).equals(originalBytes),
    "Sharing/revocation preserves exact PDF bytes",
  );
  await command("click", { label: "Volver" });
  await command("open", { certificate: f.legacy });
  await command("click", { label: "Mostrar QR y enlace" });
  await outcome("Este certificado no dispone de enlace verificable.");
  verify(!(await state()).qr, "Legacy own certificate has no invented QR");
  await command("click", { label: "Volver" });
  await command("open", { certificate: cert });
  await command("click", { label: "Mostrar QR y enlace" });
  await until(
    async () => (await state()).qr,
    "Revoked publication remains shareable",
  );
  await command("logout");
  await until(
    async () => !(await state()).detail && !(await state()).qr,
    "Logout removes private share",
  );
  await evaluate(page, "history.back()");
  await delay(400);
  verify(
    !(await state()).detail && !(await state()).qr,
    "Back after logout cannot recover private route",
  );
  await command("login", { user: "outsider" });
  verify((await state()).session === f.outsider.id, "Different account");
  await command("probeOwn", { certificate: cert });
  verify(
    JSON.parse(
      await evaluate(
        page,
        "document.documentElement.getAttribute('data-8b-own-code')",
      ),
    ) === null,
    "Other account cannot read own share code for holder certificate",
  );
  await page("Page.navigate", { url: link });
  await ready();
  await outcome("Certificado revocado");
  verify(
    (await state()).public,
    "Existing other session can use public verification",
  );
  console.log(
    "Checked production adapters, anonymous links, history, states, QR, clipboard and private logout",
  );
  const { targetId: mainId } = await browser("Target.createTarget", {
    url: "about:blank",
    browserContextId,
  });
  let mainTarget;
  await until(async () => {
    mainTarget =
      (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(
        (p) => p.id === mainId,
      );
    return Boolean(mainTarget);
  }, "main target");
  const main = await connect(mainTarget.webSocketDebuggerUrl);
  await main("Network.enable");
  let beforeMain = publicRequests;
  await main("Page.navigate", {
    url: `${origin}/production/#/verify/${record.credential_code}`,
  });
  async function mainResult() {
    await until(
      async () =>
        await evaluate(
          main,
          "!!document.querySelector('flt-semantics-placeholder')",
        ),
      "main semantics ready",
      60000,
    );
    await evaluate(
      main,
      "document.querySelector('flt-semantics-placeholder').click()",
    );
    await until(
      async () => {
        const tree = await main("Accessibility.getFullAXTree");
        return tree.nodes.some((n) =>
          n.name?.value?.includes("Certificado revocado")
        );
      },
      "Actual main public result after failed private startup",
      30000,
    );
  }
  await mainResult();
  verify(
    publicRequests - beforeMain === 1,
    "Actual main startup failure causes one public query",
  );
  verify(
    (await evaluate(main, "location.hash")).endsWith(record.credential_code),
    "main retains public code during private startup failure",
  );
  beforeMain = publicRequests;
  await main("Page.reload", { ignoreCache: true });
  await mainResult();
  verify(
    publicRequests - beforeMain === 1,
    "Actual main reload causes one public query",
  );
  verify(
    (await evaluate(main, "location.hash")).endsWith(record.credential_code),
    "actual main reload keeps public route",
  );
  verify(
    publicRequests > 8 && publicRequests < 40,
    "Bounded observed public queries, production budget unchanged",
  );
  if (failure) throw failure;
  console.log(
    `PASS: ${assertions} host assertions; ${publicRequests} observed public browser POSTs; real Auth/Edge/PostgreSQL/QR/clipboard/history`,
  );
} finally {
  sockets.forEach((s) => s.close());
  terminate(chrome);
  server?.close();
  try {
    await f.close();
  } finally {
    process.chdir(initialDirectory);
    await delay(300);
    rmSync(profile, {
      recursive: true,
      force: true,
      maxRetries: 5,
      retryDelay: 200,
    });
  }
}
