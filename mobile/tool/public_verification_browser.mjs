import { createServer } from "node:http";
import {
  connectCdp,
  evaluate,
  launchChrome,
  navigateDocument,
  prepareDocument,
  stopChrome,
} from "./browser_harness.mjs";
import { createHash, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { decodeQr } from "./verify_qr.mjs";
import { qrTestVideo } from "./qr_test_video.mjs";

if (process.env.CERTICHAIN_TEST_DISPOSABLE !== "1") {
  throw new Error("Requires an explicitly disposable local stack");
}
const build = resolve("build/public-verification-e2e");
const mainBuild = resolve("build/public-verification-main");
const backend = resolve(process.env.CERTICHAIN_TEST_BACKEND_ROOT ?? "..");
const { fixture, check, until } = await import(
  pathToFileURL(join(backend, "supabase/tests/local_issuance_fixture.mjs"))
);
const { sql } = await import(
  pathToFileURL(join(backend, "supabase/scripts/local_supabase.mjs"))
);
const profile = mkdtempSync(join(tmpdir(), "certichain-chrome-8b-"));
check(resolve(profile).startsWith(resolve(tmpdir()) + sep), "Unsafe profile");
const initialDirectory = process.cwd();
process.chdir(backend); // runtime/status always target this stack
const f = await fixture().catch((error) => {
  process.chdir(initialDirectory);
  rmSync(profile, { recursive: true, force: true });
  throw error;
});
let chrome, server, failure;
const sockets = [];
let assertions = 0, publicRequests = 0;
function verify(condition, label) {
  check(condition, label);
  assertions++;
}
const origin = "http://127.0.0.1:7357";
let cert, record, originalBytes;
let comparisonRequests = 0, localDecoderSeen = false;
const candidateDigests = [];
const cameraVideo = join(profile, "qr-camera.y4m");
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
  server = createServer(async (req, res) => {
    try {
      const path = new URL(req.url, origin).pathname;
      res.setHeader("cache-control", "no-store");
      if (
        [
          "/functions/v1/verify-certificate",
          "/functions/v1/compare-certificate-hash",
        ].includes(path)
      ) {
        if (
          ["authorization", "apikey", "cookie"].some((k) => k in req.headers)
        ) {
          failure = new Error("Same-origin public transport sent credentials");
        }
        const chunks = [];
        let length = 0;
        for await (const chunk of req) {
          length += chunk.length;
          check(length <= 2048, "Bounded public proxy");
          chunks.push(chunk);
        }
        const upstream = await fetch(f.local.API_URL + path, {
          method: req.method,
          headers: { "content-type": "application/json" },
          body: Buffer.concat(chunks),
          signal: AbortSignal.timeout(15000),
        });
        const headers = {};
        for (
          const name of [
            "content-type",
            "cache-control",
            "retry-after",
            "access-control-allow-origin",
            "access-control-expose-headers",
          ]
        ) {
          const value = upstream.headers.get(name);
          if (value != null) headers[name] = value;
        }
        // fetch decoded content-encoding; forward only application headers.
        res.writeHead(upstream.status, headers);
        res.end(Buffer.from(await upstream.arrayBuffer()));
        return;
      }
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
  const launched = await launchChrome(profile, [
    "--use-fake-device-for-media-stream",
    `--use-file-for-fake-video-capture=${cameraVideo}`,
    "about:blank",
  ]);
  chrome = launched.child;
  const port = launched.port;
  async function connect(url) {
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
    const cdp = await connectCdp(url, (m) => {
      if (m.method === "Network.requestWillBeSent") {
        const url = new URL(m.params.request.url);
        if (
          ["http:", "https:"].includes(url.protocol) &&
          !["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)
        ) failure = new Error("Unexpected external app/decoder resource");
        if (url.pathname.endsWith("/decoder/zxing-0.23.0.min.js")) {
          localDecoderSeen = true;
        }
      }
      if (
        m.method === "Network.requestWillBeSent" &&
        (m.params.request.url.endsWith("/functions/v1/verify-certificate") ||
          m.params.request.url.endsWith(
            "/functions/v1/compare-certificate-hash",
          )) &&
        m.params.request.method === "POST"
      ) {
        const comparison = m.params.request.url.endsWith(
          "/compare-certificate-hash",
        );
        if (comparison) comparisonRequests++;
        else publicRequests++;
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
        if (
          Object.keys(body).sort().join(",") !==
            (comparison ? "credential_code,document_sha256" : "credential_code")
        ) {
          failure = new Error("Public browser widened body");
        }
        if (comparison) {
          if (
            body.credential_code !== record.credential_code ||
            !/^[0-9a-f]{64}$/.test(body.document_sha256) ||
            body.document_sha256.length !== 64
          ) failure = new Error("Comparison candidate contract");
          candidateDigests.push(body.document_sha256);
        }
      }
      if (m.method === "Network.requestWillBeSentExtraInfo") {
        extra.set(m.params.requestId, m.params.headers);
        if (publicIds.has(m.params.requestId)) assertHeaders(m.params.headers);
      }
    });
    sockets.push(cdp);
    return cdp;
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
    if (!cdp.documentContext) await prepareDocument(cdp);
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
  await navigateDocument(page, "Page.navigate", { url: link });
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
  await navigateDocument(page, "Page.reload", { ignoreCache: true });
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
  await navigateDocument(page, "Page.navigate", {
    url: `${origin}/#/verify/${expiredCode}`,
  });
  await ready();
  await outcome("Certificado caducado");
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "suspended",
  }, f.platform.token);
  await navigateDocument(page, "Page.navigate", { url: link });
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
  qrTestVideo(
    Buffer.from(
      await evaluate(
        page,
        "document.documentElement.getAttribute('data-8b-qr')",
      ),
      "base64",
    ),
    cameraVideo,
  );
  const originalPath = join(profile, "original.pdf"),
    renamedPath = join(profile, "same-bytes-new-name.pdf"),
    changedPath = join(profile, "changed.pdf");
  writeFileSync(originalPath, originalBytes);
  writeFileSync(renamedPath, originalBytes);
  const changed = Buffer.from(originalBytes);
  changed[changed.length - 1] ^= 1;
  writeFileSync(changedPath, changed);
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
  await anonymous("Emulation.setDeviceMetricsOverride", {
    width: 390,
    height: 844,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await anonymous("Page.enable");
  await anonymous("Page.setInterceptFileChooserDialog", { enabled: true });
  await ready(anonymous);
  await outcome("Registro encontrado y vigente", anonymous);
  verify(
    (await state(anonymous)).session === null &&
      (await state(anonymous)).code === record.credential_code,
    "Copied link resolves same record without session",
  );
  await navigateDocument(anonymous, "Page.reload", { ignoreCache: true });
  await ready(anonymous);
  await outcome("Registro encontrado y vigente", anonymous);
  verify(
    (await state(anonymous)).queries === 1,
    "Anonymous copied link reload",
  );
  await command("click", { label: "Consultar otro código" }, anonymous);
  await evaluate(
    anonymous,
    "document.cookie='certichain_test_cookie=synthetic; path=/'",
  );
  verify(
    (await evaluate(anonymous, "document.cookie")).includes(
      "certichain_test_cookie",
    ),
    "Same-origin cookie present before public requests",
  );
  const beforeScan = publicRequests;
  await browser("Browser.setPermission", {
    permission: { name: "camera" },
    setting: "denied",
    origin,
    browserContextId,
  });
  const beforeDeniedCamera = publicRequests;
  await command("click", { label: "Escanear QR" }, anonymous);
  try {
    await outcome(
      "Permiso de cámara denegado. Puedes introducir el código manualmente.",
      anonymous,
    );
  } catch (error) {
    writeFileSync(
      join(build, "camera-denied-diagnostic.png"),
      Buffer.from(
        (await anonymous("Page.captureScreenshot", { format: "png" })).data,
        "base64",
      ),
    );
    const permission = await evaluate(
      anonymous,
      "navigator.permissions.query({name:'camera'}).then(p => p.state)",
    );
    throw new Error(
      `Camera denied deadline; browser permission=${permission}`,
      { cause: error },
    );
  }
  verify(
    publicRequests === beforeDeniedCamera,
    "Real camera denial makes no verification request",
  );
  await browser("Browser.setPermission", {
    permission: { name: "camera" },
    setting: "granted",
    origin,
    browserContextId,
  });
  await command("click", { label: "Activar cámara" }, anonymous);
  await outcome("Código identificado", anonymous);
  verify(localDecoderSeen, "Production decoder asset fetched locally; no CDN");
  verify(
    publicRequests === beforeScan,
    "Real video scanner identifies without query",
  );
  await command("click", { label: "Verificar código identificado" }, anonymous);
  await outcome("Registro encontrado y vigente", anonymous);
  verify(
    publicRequests === beforeScan + 1,
    "Repeated video detections yield one confirmed public query",
  );
  await until(
    async () =>
      await evaluate(
        anonymous,
        "[...document.querySelectorAll('video')].every(v => !v.srcObject || v.srcObject.getTracks().every(t => t.readyState === 'ended'))",
      ),
    "Camera resources released",
  );
  async function compareFile(path, expected) {
    await command("click", { label: "Comparar mi PDF" }, anonymous);
    await until(
      async () =>
        await evaluate(
          anonymous,
          "!!document.querySelector('#certichain-comparison-pdf-input')",
        ),
      "Real comparison input",
    );
    const { root } = await anonymous("DOM.getDocument");
    const { nodeId } = await anonymous("DOM.querySelector", {
      nodeId: root.nodeId,
      selector: "#certichain-comparison-pdf-input",
    });
    await anonymous("DOM.setFileInputFiles", { nodeId, files: [path] });
    await outcome(expected, anonymous);
    await until(
      async () =>
        !(await evaluate(
          anonymous,
          "!!document.querySelector('#certichain-comparison-pdf-input')",
        )),
      "Picker resources released",
    );
  }
  const emptyPath = join(profile, "empty.pdf"),
    largePath = join(profile, "too-large.pdf");
  writeFileSync(emptyPath, Buffer.alloc(0));
  writeFileSync(largePath, Buffer.alloc(8388609));
  await command("click", { label: "Comparar mi PDF" }, anonymous);
  await until(
    async () =>
      await evaluate(
        anonymous,
        "!!document.querySelector('#certichain-comparison-pdf-input')",
      ),
    "Cancel picker ready",
  );
  await evaluate(
    anonymous,
    "document.querySelector('#certichain-comparison-pdf-input').dispatchEvent(new Event('cancel'))",
  );
  await outcome("Comparación cancelada.", anonymous);
  await compareFile(emptyPath, "El archivo está vacío.");
  await compareFile(
    largePath,
    "El archivo supera el límite de 8 MiB (8.388.608 bytes).",
  );
  verify(
    comparisonRequests === 0,
    "Cancel/empty/large selection never makes HTTP",
  );
  const matchLabel = "El PDF coincide byte a byte con el documento registrado.";
  await compareFile(originalPath, matchLabel);
  await compareFile(renamedPath, matchLabel);
  await compareFile(
    changedPath,
    "El PDF no coincide con el documento registrado.",
  );
  verify(
    candidateDigests[0] ===
        createHash("sha256").update(originalBytes).digest("hex") &&
      candidateDigests[1] === candidateDigests[0] &&
      candidateDigests[2] ===
        createHash("sha256").update(changed).digest("hex"),
    "Only candidate SHA-256 travels; exact bytes, renamed copy and one-byte change",
  );
  sql(`UPDATE public.certificates SET status='revoked' WHERE id='${cert}';`);
  await command("click", { label: "Actualizar comprobación" }, anonymous);
  await outcome("Certificado revocado", anonymous);
  await compareFile(originalPath, matchLabel);
  await outcome("Certificado revocado", anonymous);
  writeFileSync(
    join(build, "comparison-revoked-390.png"),
    Buffer.from(
      (await anonymous("Page.captureScreenshot", { format: "png" })).data,
      "base64",
    ),
  );
  verify(
    comparisonRequests === 4,
    "Matching PDF never hides revocation; explicit comparisons only",
  );
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
  await navigateDocument(page, "Page.navigate", { url: link });
  await ready();
  await outcome("Certificado revocado");
  verify(
    (await state()).public,
    "Existing other session can use public verification",
  );
  await browser("Browser.setPermission", {
    permission: { name: "camera" },
    setting: "granted",
    origin,
  });
  const beforeSignedScan = publicRequests;
  await command("click", { label: "Escanear QR" });
  await outcome("Código identificado");
  await command("click", { label: "Verificar código identificado" });
  await outcome("Certificado revocado");
  await until(
    async () => publicRequests === beforeSignedScan + 1,
    "Signed-in scanner single confirmation",
  );
  verify(
    (await state()).session === f.outsider.id,
    "Real scanner also works with an existing session without using its credentials",
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
  await navigateDocument(main, "Page.navigate", {
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
  await navigateDocument(main, "Page.reload", { ignoreCache: true });
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
    `PASS: ${assertions} host assertions; ${publicRequests} verification and ${comparisonRequests} comparison POSTs; real emulated camera/decoder/PDF; real Auth/Edge/PostgreSQL/QR/clipboard/history`,
  );
} finally {
  sockets.forEach((s) => s.close());
  await stopChrome(chrome);
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
