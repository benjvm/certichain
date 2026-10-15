// 8D: main.dart RELEASE, production semantics/adapters, real disposable backend.
// Technical credentials, SQL, TLS keys and fixture setup remain on the host.
import { createServer } from "node:https";
import { spawnSync } from "node:child_process";
import { createHash, randomUUID, X509Certificate } from "node:crypto";
import {
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, extname, join, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import {
  cameraTestMode,
  connectCdp,
  evaluate,
  launchChrome,
  navigateDocument,
  prepareDocument,
  sourceRevision,
  stopChrome,
} from "./browser_harness.mjs";
import { cropRenderedQr, decodeQr } from "./verify_qr.mjs";
import { qrTestVideo } from "./qr_test_video.mjs";

if (process.env.CERTICHAIN_TEST_DISPOSABLE !== "1") {
  throw new Error("8D requires disposable stack");
}
if (process.versions.node !== "24.14.0") {
  throw new Error("8D requires Node 24.14.0");
}
const mobile = resolve("."),
  backend = resolve(process.env.CERTICHAIN_TEST_BACKEND_ROOT ?? "..");
const revision = sourceRevision(mobile);
const evaluatedAt = new Date().toISOString();
const camera = cameraTestMode();
const { fixture, check, until } = await import(
  pathToFileURL(join(backend, "supabase/tests/local_issuance_fixture.mjs"))
);
const { sql } = await import(
  pathToFileURL(join(backend, "supabase/scripts/local_supabase.mjs"))
);
const { pdfFixture } = await import(
  pathToFileURL(join(backend, "supabase/tests/pdf_fixture.mjs"))
);
const directory = mkdtempSync(join(tmpdir(), "certichain-release-8d-"));
check(
  resolve(directory).startsWith(resolve(tmpdir()) + sep),
  "Own temporary directory",
);
const build = join(mobile, "build/phase8d-release"),
  evidence = join(
    mobile,
    process.env.CERTICHAIN_EVIDENCE_DIRECTORY ?? "build/phase8d-evidence",
  );
check(
  evidence.startsWith(join(mobile, "build") + sep) &&
    /^phase8d-evidence(?:-[a-z0-9]+)?$/.test(basename(evidence)),
  "Own evidence directory",
);
mkdirSync(evidence, { recursive: true });
for (
  const name of [
    "result.json",
    "failure.json",
    "failure-synthetic.png",
    "comparison-match.png",
    "comparison-mismatch.png",
    "comparison-revoked.png",
  ]
) {
  rmSync(join(evidence, name), { force: true });
}
const origin = "https://127.0.0.1:7358";
const started = Date.now(), stages = [], timings = {};
let f,
  server,
  chrome,
  failure,
  cameraDiagnostic,
  stage = "prepare",
  assertions = 0,
  artifactChecks = 0;
const sockets = [], requests = [], candidates = [], downloads = [];
let decoderSeen = false, issuePosts = 0, publicPosts = 0, comparePosts = 0;
let fault = null, heldResponse, budgetSaved;
function verify(condition, label) {
  check(condition, `${stage}: ${label}`);
  assertions++;
}
function checkpoint(name) {
  stages.push({
    stage: name,
    result: "PASS",
    elapsed_ms: Date.now() - started,
  });
  console.log(JSON.stringify(stages.at(-1)));
  stage = name;
}
const types = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".json": "application/json",
  ".wasm": "application/wasm",
  ".ttf": "font/ttf",
  ".png": "image/png",
};
const pdf = pdfFixture(),
  digest = createHash("sha256").update(pdf).digest("hex");
const original = join(directory, "original.pdf"),
  renamed = join(directory, "renamed.pdf"),
  modified = join(directory, "modified.pdf");
writeFileSync(original, pdf);
writeFileSync(renamed, pdf);
const changed = Buffer.from(pdf);
changed[changed.length - 1] ^= 1;
writeFileSync(modified, changed);
writeFileSync(join(directory, "empty.pdf"), Buffer.alloc(0));
writeFileSync(join(directory, "limit.pdf"), Buffer.alloc(8388608));
writeFileSync(join(directory, "oversize.pdf"), Buffer.alloc(8388609));
const cameraVideo = join(directory, "camera.y4m");
// Chrome opens this file when the camera starts, after the real QR is captured.
if (camera.enabled) writeFileSync(cameraVideo, "");

try {
  process.chdir(backend);
  f = await fixture();
  budgetSaved = sql(
    "SELECT row_to_json(b) FROM certichain_private.public_verification_budget b;",
  );
  sql(
    "UPDATE certichain_private.public_verification_budget SET used=0,window_started_at=clock_timestamp();",
  );
  const openssl = process.env.OPENSSL_EXECUTABLE ??
    (process.platform === "win32"
      ? "C:/Program Files/Git/usr/bin/openssl.exe"
      : "openssl");
  const cert = join(directory, "cert.pem"), key = join(directory, "key.pem");
  const tls = spawnSync(openssl, [
    "req",
    "-x509",
    "-newkey",
    "rsa:2048",
    "-nodes",
    "-days",
    "1",
    "-keyout",
    key,
    "-out",
    cert,
    "-subj",
    "/CN=localhost",
    "-addext",
    "subjectAltName=IP:127.0.0.1,DNS:localhost",
  ], { windowsHide: true, timeout: 10000 });
  verify(tls.status === 0, "Ephemeral local TLS certificate");
  const spki = createHash("sha256").update(
    new X509Certificate(readFileSync(cert)).publicKey.export({
      type: "spki",
      format: "der",
    }),
  ).digest("base64");
  // Only public config in compiler inputs; no test entrypoint or private fixture route.
  const config = join(directory, "public-config.json");
  writeFileSync(
    config,
    JSON.stringify({
      SUPABASE_URL: origin,
      SUPABASE_PUBLISHABLE_KEY: f.local.ANON_KEY,
      PUBLIC_VERIFICATION_BASE_URL: origin + "/",
    }),
  );
  stage = "release-build";
  if (process.env.CERTICHAIN_RELEASE_SKIP_BUILD !== "1") {
    const args = [
      "build",
      "web",
      "--release",
      "--no-web-resources-cdn",
      "--target=lib/main.dart",
      `--dart-define-from-file=${config}`,
      "--output=build/phase8d-release",
    ];
    const built = process.platform === "win32"
      ? spawnSync("cmd.exe", [
        "/d",
        "/s",
        "/c",
        `flutter ${
          args.map((a) => /\s/.test(a) ? '"' + a + '"' : a).join(" ")
        }`,
      ], {
        cwd: mobile,
        windowsVerbatimArguments: true,
        windowsHide: true,
        timeout: 180000,
      })
      : spawnSync("flutter", args, { cwd: mobile, timeout: 180000 });
    if (built.status !== 0) {
      const diagnostic = String(built.stderr ?? built.error?.code ?? "")
        .replaceAll(f.local.ANON_KEY, "[public-key]").replaceAll(
          f.local.SERVICE_ROLE_KEY,
          "[redacted]",
        );
      console.error(diagnostic.slice(-3000));
    }
    verify(built.status === 0, "main.dart release build");
  }
  const scan = (folder) => {
    for (const item of readdirSync(folder, { withFileTypes: true })) {
      const path = join(folder, item.name);
      if (item.isDirectory()) scan(path);
      else {
        const content = readFileSync(path);
        for (
          const secret of [
            f.local.SERVICE_ROLE_KEY,
            f.local.JWT_SECRET,
            f.faultToken,
          ]
        ) {
          if (secret) {
            check(
              !content.includes(Buffer.from(secret)),
              "No technical secret in artifact",
            );
            artifactChecks++;
          }
        }
      }
    }
  };
  scan(build);
  checkpoint("release-build");
  server = createServer(
    { key: readFileSync(key), cert: readFileSync(cert) },
    async (req, res) => {
      try {
        const path = new URL(req.url, origin).pathname;
        res.setHeader("cache-control", "no-store");
        if (
          path.startsWith("/auth/v1/") || path.startsWith("/rest/v1/") ||
          path.startsWith("/storage/v1/") || path.startsWith("/functions/v1/")
        ) {
          const publicCall = [
            "/functions/v1/verify-certificate",
            "/functions/v1/verify-certificate-v2",
            "/functions/v1/verify-certificate-v3",
            "/functions/v1/compare-certificate-hash",
          ].includes(path);
          const chunks = [];
          let length = 0;
          for await (const chunk of req) {
            length += chunk.length;
            check(length <= 9 * 1048576, "Proxy request boundary");
            chunks.push(chunk);
          }
          const body = Buffer.concat(chunks);
          if (publicCall && req.method === "POST") {
            verify(
              !["authorization", "apikey", "cookie"].some((k) =>
                req.headers[k]
              ),
              "Same-origin public wire omits all credentials",
            );
            const input = JSON.parse(body);
            const comparison = path.endsWith("compare-certificate-hash");
            verify(
              Object.keys(input).sort().join(",") ===
                (comparison
                  ? "credential_code,document_sha256"
                  : "credential_code"),
              "Exclusive public input",
            );
            if (comparison) {
              comparePosts++;
              candidates.push(input.document_sha256);
            } else publicPosts++;
            requests.push({ comparison, code: input.credential_code });
            if (fault) {
              const current = fault;
              fault = null;
              if (current === "hold") {
                await new Promise((r) => {
                  heldResponse = r;
                });
              } else if (current === "disconnect") {
                // Once headers arrived Chrome cannot transparently replay the POST
                // as it can when a reused socket closes before a response starts.
                res.writeHead(200, {
                  "content-type": "application/json",
                  "content-length": "512",
                });
                res.write('{"');
                await delay(20);
                res.destroy();
                return;
              } else if (current === "timeout") {
                await delay(17000);
                if (res.destroyed) return;
              } else {
                res.writeHead(current === "503" ? 503 : 200, {
                  "content-type": "application/json",
                });
                res.end(
                  current === "malformed"
                    ? "{"
                    : current === "excessive"
                    ? "x".repeat(8193)
                    : '{"error":"temporary_failure"}',
                );
                return;
              }
            }
          }
          if (
            path.endsWith("/issue-certificate") && req.method === "POST"
          ) issuePosts++;
          const headers = {
            ...req.headers,
            host: new URL(f.local.API_URL).host,
            connection: "close",
          };
          delete headers["content-length"];
          delete headers["accept-encoding"];
          const upstream = await fetch(f.local.API_URL + req.url, {
            method: req.method,
            headers,
            body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
            signal: AbortSignal.timeout(30000),
            redirect: "manual",
          });
          const bytes = Buffer.from(await upstream.arrayBuffer());
          res.writeHead(upstream.status, {
            "content-type": upstream.headers.get("content-type") ??
              "application/json",
            "cache-control": "no-store",
            ...Object.fromEntries(
              ["content-range", "range-unit", "retry-after"].filter((k) =>
                upstream.headers.has(k)
              ).map((k) => [k, upstream.headers.get(k)]),
            ),
          });
          res.end(bytes);
          return;
        }
        const file = resolve(
          build,
          "." + (path === "/" ? "/index.html" : path),
        );
        check(file.startsWith(build + sep), "Static source boundary");
        res.setHeader(
          "content-type",
          types[extname(file)] ?? "application/octet-stream",
        );
        res.end(readFileSync(file));
      } catch {
        if (!res.headersSent) res.writeHead(503);
        res.end();
      }
    },
  );
  await new Promise((r, j) => {
    server.once("error", j);
    server.listen(7358, "127.0.0.1", r);
  });
  const launched = await launchChrome(join(directory, "chrome"), [
    `--ignore-certificate-errors-spki-list=${spki}`,
    ...camera.chromeArgs(cameraVideo),
    "about:blank",
  ]);
  chrome = launched.child;
  const browserInfo =
    await (await fetch(`http://127.0.0.1:${launched.port}/json/version`))
      .json();
  const browser = await connectCdp(browserInfo.webSocketDebuggerUrl);
  sockets.push(browser);
  async function page(context) {
    const target = await browser("Target.createTarget", {
      url: "about:blank",
      ...(context ? { browserContextId: context } : {}),
    });
    const list =
      await (await fetch(`http://127.0.0.1:${launched.port}/json/list`)).json();
    const cdp = await connectCdp(
      list.find((t) => t.id === target.targetId).webSocketDebuggerUrl,
      (event) => {
        if (event.method === "Network.requestWillBeSent") {
          const url = new URL(event.params.request.url);
          if (
            ["https:", "http:"].includes(url.protocol) &&
            !["127.0.0.1", "localhost"].includes(url.hostname)
          ) failure = new Error("External app/decoder request");
          if (url.pathname.endsWith("/decoder/zxing-0.23.0.min.js")) {
            decoderSeen = true;
          }
          if (
            event.params.request.method === "POST" &&
            url.pathname.startsWith("/storage/")
          ) failure = new Error("Browser uploaded PDF to Storage");
        }
        if (event.method === "Page.fileChooserOpened") {
          cdp.chooser = event.params;
        }
        if (
          event.method === "Browser.downloadProgress" &&
          event.params.state === "completed"
        ) downloads.push(event.params.guid);
      },
    );
    sockets.push(cdp);
    await cdp("Page.enable");
    await cdp("Runtime.enable");
    await cdp("Network.enable");
    await cdp("DOM.enable");
    await cdp("Page.setInterceptFileChooserDialog", { enabled: true });
    await cdp("Emulation.setDeviceMetricsOverride", {
      width: 390,
      height: 844,
      deviceScaleFactor: 1,
      mobile: false,
    });
    return cdp;
  }
  async function semantics(cdp) {
    if (failure) throw failure;
    const tree = await cdp("Accessibility.getFullAXTree");
    return tree.nodes.filter((n) => !n.ignored).map((n) => n.name?.value ?? "")
      .join(" ");
  }
  const domSearch =
    `globalThis.ccElements=(selector)=>{const result=[];const visit=(root)=>{result.push(...root.querySelectorAll(selector));for(const e of root.querySelectorAll('*'))if(e.shadowRoot)visit(e.shadowRoot);};visit(document);return result;}`;
  async function ready(cdp, text) {
    if (!cdp.documentContext) await prepareDocument(cdp);
    await until(
      async () => {
        await evaluate(
          cdp,
          `${domSearch};ccElements('flt-semantics-placeholder')[0]?.click()`,
        );
        return (await semantics(cdp)).includes(text);
      },
      "Release semantics ready",
      45000,
    );
  }
  async function outcome(cdp, text, timeout = 25000) {
    await until(
      async () => (await semantics(cdp)).includes(text),
      `UI outcome ${text}`,
      timeout,
    );
  }
  async function clickPoint(cdp, p) {
    await cdp("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x: p.x,
      y: p.y,
      button: "left",
      clickCount: 1,
    });
    await cdp("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: p.x,
      y: p.y,
      button: "left",
      clickCount: 1,
    });
  }
  async function element(cdp, label, input = false) {
    const expression = `${domSearch};(()=>{const a=ccElements(${
      JSON.stringify(
        input ? "flt-semantics input,flt-semantics textarea" : "flt-semantics",
      )
    });const match=e=>e.getAttribute('aria-label')===${
      JSON.stringify(label)
    } || (e.getAttribute('aria-label')||'').split('\\n').includes(${
      JSON.stringify(label)
    }) || e.textContent===${
      JSON.stringify(label)
    } || (e.getAttribute('role')==='button' && e.textContent.includes(${
      JSON.stringify(label)
    }));const e=a.find(e=>e.getAttribute('role')==='button' && match(e)) || a.find(match);if(!e)return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,width:r.width,height:r.height,left:r.x,top:r.y};})()`;
    let found;
    await until(
      async () => {
        found = await evaluate(cdp, expression);
        return found && found.width > 0;
      },
      `Semantic control ${label}`,
      15000,
    );
    await delay(200); // Semantics scrolling updates the CanvasKit frame asynchronously.
    found = await evaluate(
      cdp,
      expression.replace("e.scrollIntoView({block:'center'});", ""),
    );
    return found;
  }
  async function click(cdp, label) {
    await cdp("Page.bringToFront");
    await element(cdp, label);
    await evaluate(
      cdp,
      `${domSearch};(()=>{const a=ccElements('flt-semantics');const match=e=>e.getAttribute('aria-label')===${
        JSON.stringify(label)
      } || (e.getAttribute('aria-label')||'').split('\\n').includes(${
        JSON.stringify(label)
      }) || e.textContent===${
        JSON.stringify(label)
      } || (e.getAttribute('role')==='button' && e.textContent.includes(${
        JSON.stringify(label)
      }));const e=a.find(e=>e.getAttribute('role')==='button' && match(e)) || a.find(match);e.click();})()`,
    );
    await delay(150);
  }
  async function enter(cdp, label, text) {
    await cdp("Page.bringToFront");
    for (let attempt = 0; attempt < 3; attempt++) {
      await clickPoint(cdp, await element(cdp, label, true));
      await evaluate(
        cdp,
        `${domSearch};ccElements('input,textarea').filter(e=>e.getAttribute('aria-label')===${
          JSON.stringify(label)
        } && e.getBoundingClientRect().width>0).at(-1)?.focus()`,
      );
      await delay(250);
      await cdp("Input.dispatchKeyEvent", {
        type: "keyDown",
        key: "a",
        code: "KeyA",
        modifiers: process.platform === "darwin" ? 4 : 2,
        windowsVirtualKeyCode: 65,
      });
      await cdp("Input.dispatchKeyEvent", {
        type: "keyUp",
        key: "a",
        code: "KeyA",
        modifiers: process.platform === "darwin" ? 4 : 2,
        windowsVirtualKeyCode: 65,
      });
      await cdp("Input.insertText", { text });
      await delay(150);
      if (
        await evaluate(
          cdp,
          `${domSearch};ccElements('input,textarea').some(e=>e.value===${
            JSON.stringify(text)
          })`,
        )
      ) {
        verify(true, `UI field ${label} received text`);
        return;
      }
    }
    verify(false, `UI field ${label} received text`);
  }
  async function capturePublic(cdp, name) {
    verify(
      await evaluate(
        cdp,
        "location.hash === '#/verify' || location.hash.startsWith('#/verify/')",
      ),
      "Only public synthetic captures",
    );
    writeFileSync(
      join(evidence, name + ".png"),
      Buffer.from(
        (await cdp("Page.captureScreenshot", { format: "png" })).data,
        "base64",
      ),
    );
  }
  async function select(cdp, label, file) {
    cdp.chooser = null;
    await click(cdp, label);
    await until(() => !!cdp.chooser, "Production file chooser");
    await cdp("DOM.setFileInputFiles", {
      files: file ? [file] : [],
      backendNodeId: cdp.chooser.backendNodeId,
    });
  }
  async function login(cdp, user) {
    await ready(cdp, "Comenzar");
    await click(cdp, "Comenzar");
    await outcome(cdp, "Iniciar sesión");
    await enter(cdp, "Email", user.email);
    await enter(cdp, "Contraseña", user.password);
    await click(cdp, "Iniciar sesión");
    await outcome(cdp, "Cerrar sesión");
  }
  const issuer = await page();
  await navigateDocument(issuer, "Page.navigate", { url: origin + "/" });
  stage = "issuer-login";
  await login(issuer, f.owner);
  checkpoint("issuer-login");
  await click(issuer, "Espacio institucional");
  await outcome(issuer, "Emitir certificado");
  const workspace = await semantics(issuer);
  // Membership ordering is by opaque UUID, so select through the real dropdown.
  const selectedName = workspace.includes("owner · Suspendida")
    ? "7D Suspended"
    : workspace.includes("owner · Pendiente")
    ? "7D Pending"
    : "7D Verified";
  if (selectedName !== "7D Verified") {
    await click(issuer, selectedName);
    await click(issuer, "7D Verified");
  }
  await click(issuer, "Emitir certificado");
  await outcome(issuer, "ID del titular");
  await enter(issuer, "ID del titular", f.holder.id);
  await enter(issuer, "Título", "8D Release Certificate");
  await click(issuer, "Siguiente");
  await select(issuer, "Seleccionar PDF", original);
  await outcome(issuer, "original.pdf");
  await click(issuer, "Siguiente");
  const issueStarted = Date.now();
  await click(issuer, "Emitir certificado");
  await outcome(issuer, "Ir a Certificados emitidos");
  timings.issuance_ms = Date.now() - issueStarted;
  verify(issuePosts === 1, "Single real UI issuance");
  const row = JSON.parse(
    sql(
      `SELECT row_to_json(c) FROM public.certificates c WHERE institution_id='${f.verified}' AND title='8D Release Certificate';`,
    ),
  );
  verify(
    row.holder_id === f.holder.id && row.document_hash === digest,
    "Published exact document hash/holder",
  );
  verify(
    (await f.stored(f.verified, row.id)).equals(pdf),
    "Storage preserves every byte",
  );
  checkpoint("ui-issuance-storage");
  await click(issuer, "Ir a Certificados emitidos");
  await click(issuer, "Volver");
  await click(issuer, "Cerrar sesión");
  await outcome(issuer, "Comenzar");
  await login(issuer, f.holder);
  await click(issuer, "8D Release Certificate");
  await outcome(issuer, "Descargar PDF");
  await browser("Browser.setDownloadBehavior", {
    behavior: "allow",
    downloadPath: join(directory, "downloads"),
    eventsEnabled: true,
  });
  await click(issuer, "Descargar PDF");
  await until(() => {
    try {
      return readdirSync(join(directory, "downloads")).some((n) =>
        n.endsWith(".pdf")
      );
    } catch {
      return false;
    }
  }, "Authorized real browser download");
  const downloaded = readdirSync(join(directory, "downloads")).find((n) =>
    n.endsWith(".pdf")
  );
  verify(
    readFileSync(join(directory, "downloads", downloaded)).equals(pdf),
    "Authorized holder download exact bytes",
  );
  await click(issuer, "Mostrar QR y enlace");
  await outcome(issuer, "Copiar enlace");
  await browser("Browser.grantPermissions", {
    origin,
    permissions: ["clipboardReadWrite", "clipboardSanitizedWrite"],
  });
  await issuer("Page.bringToFront");
  await click(issuer, "Copiar enlace");
  await outcome(issuer, "Enlace copiado");
  const link = await evaluate(issuer, "navigator.clipboard.readText()");
  verify(
    link === `${origin}/#/verify/${row.credential_code}`,
    "Real clipboard exact credential-only link",
  );
  await element(issuer, "QR del enlace de verificación");
  const png = cropRenderedQr(
    Buffer.from(
      (await issuer("Page.captureScreenshot", { format: "png" })).data,
      "base64",
    ),
    link,
  );
  writeFileSync(join(evidence, "qr-synthetic.png"), png);
  decodeQr(png, link);
  assertions++;
  if (camera.enabled) qrTestVideo(png, cameraVideo);
  writeFileSync(join(evidence, "qr-synthetic.png"), png);
  checkpoint("holder-download-share");
  const context =
    (await browser("Target.createBrowserContext")).browserContextId;
  const anonymous = await page(context);
  await anonymous("Network.setCookie", {
    name: "same_origin_session_probe",
    value: "synthetic",
    url: origin,
  });
  let before = publicPosts;
  await navigateDocument(anonymous, "Page.navigate", { url: link });
  await ready(anonymous, "Registro encontrado y vigente");
  verify(publicPosts === before + 1, "Anonymous link/init single public query");
  checkpoint("anonymous-link");
  await click(anonymous, "Consultar otro código");
  await camera.run("camera-real-decoder", async () => {
    stage = "camera-real-decoder";
    await browser("Browser.setPermission", {
      permission: { name: "camera" },
      setting: "denied",
      origin,
      browserContextId: context,
    });
    await click(anonymous, "Escanear QR");
    await outcome(anonymous, "Permiso de cámara denegado");
    await browser("Browser.setPermission", {
      permission: { name: "camera" },
      setting: "granted",
      origin,
      browserContextId: context,
    });
    const detectStarted = Date.now();
    await click(anonymous, "Activar cámara");
    try {
      await outcome(anonymous, "Verificar código identificado");
    } catch (error) {
      // Only allowlisted media state and the synthetic anonymous route; no raw
      // device labels, application text, URLs, frames or decoded payload in JSON.
      cameraDiagnostic = await evaluate(
        anonymous,
        `({
      videos: [...document.querySelectorAll('video')].map(v => ({
        width: v.videoWidth, height: v.videoHeight, ready_state: v.readyState,
        tracks: v.srcObject ? v.srcObject.getTracks().map(t => ({
          kind: t.kind, state: t.readyState, enabled: t.enabled
        })) : []
      }))
    })`,
      );
      await capturePublic(anonymous, "failure-synthetic");
      throw error;
    }
    timings.qr_detection_ms = Date.now() - detectStarted;
    before = publicPosts;
    await delay(500);
    verify(
      publicPosts === before,
      "Repeated frames require explicit confirmation",
    );
    await click(anonymous, "Verificar código identificado");
    await outcome(anonymous, "Registro encontrado y vigente");
    verify(
      publicPosts === before + 1 && decoderSeen,
      "One confirmation; real local ZXing decoder",
    );
    verify(
      await evaluate(
        anonymous,
        "[...document.querySelectorAll('video')].every(v=>!v.srcObject || v.srcObject.getTracks().every(t=>t.readyState==='ended'))",
      ),
      "Camera tracks stopped after detection",
    );
    checkpoint("camera-real-decoder");
  });
  if (!camera.enabled) {
    stages.push({
      ...camera.scenarios.at(-1),
      elapsed_ms: Date.now() - started,
    });
    stage = "manual-issued-code";
    before = publicPosts;
    await enter(anonymous, "Código del certificado", row.credential_code);
    await click(anonymous, "Verificar");
    await outcome(anonymous, "Registro encontrado y vigente");
    verify(
      publicPosts === before + 1,
      "One manual query for the actual issued credential",
    );
    checkpoint("manual-issued-code");
  }
  stage = "pdf-comparison";
  for (
    const [file, message] of [[original, "El PDF coincide byte a byte"], [
      renamed,
      "El PDF coincide byte a byte",
    ], [modified, "El PDF no coincide"]]
  ) {
    before = comparePosts;
    const time = Date.now();
    await select(anonymous, "Comparar mi PDF", file);
    await outcome(anonymous, message);
    timings[extname(file) + "_" + comparePosts + "_comparison_ms"] =
      Date.now() - time;
    verify(comparePosts === before + 1, "One comparison per selected copy");
    if (file === original) await capturePublic(anonymous, "comparison-match");
  }
  verify(
    candidates[0] === digest && candidates[1] === digest &&
      candidates[2] === createHash("sha256").update(changed).digest("hex"),
    "Local hashes for original/renamed/one-byte mutation",
  );
  for (
    const [file, message] of [[null, "Comparación cancelada."], [
      join(directory, "empty.pdf"),
      "El archivo está vacío.",
    ], [
      join(directory, "oversize.pdf"),
      "El archivo supera el límite de 8 MiB",
    ]]
  ) {
    before = comparePosts;
    await select(anonymous, "Comparar mi PDF", file);
    if (!file) {
      await evaluate(
        anonymous,
        "document.querySelector('#certichain-comparison-pdf-input')?.dispatchEvent(new Event('cancel'))",
      );
    }
    await outcome(anonymous, message);
    verify(
      comparePosts === before,
      "Cancelled/empty/oversized copy sends no POST",
    );
    verify(
      await evaluate(
        anonymous,
        "!document.querySelector('#certichain-comparison-pdf-input')",
      ),
      "Picker DOM released",
    );
  }
  await capturePublic(anonymous, "comparison-mismatch");
  const largeStarted = Date.now();
  before = comparePosts;
  await select(anonymous, "Comparar mi PDF", join(directory, "limit.pdf"));
  await outcome(anonymous, "El PDF no coincide");
  timings.selection_hash_query_8mib_ms = Date.now() - largeStarted;
  verify(
    comparePosts === before + 1 &&
      candidates.at(-1) ===
        createHash("sha256").update(Buffer.alloc(8388608)).digest("hex"),
    "Exact 8 MiB hash accepted",
  );
  await f.rpc("set_institution_status", {
    p_institution: f.verified,
    p_status: "suspended",
  }, f.platform.token);
  await select(anonymous, "Comparar mi PDF", original);
  await outcome(anonymous, "Emisor sin aprobación vigente");
  await outcome(anonymous, "El PDF coincide byte a byte");
  sql(
    `UPDATE public.certificates SET status='revoked',revoked_at=clock_timestamp() WHERE id='${row.id}';`,
  );
  await select(anonymous, "Comparar mi PDF", original);
  await outcome(anonymous, "Certificado revocado");
  await outcome(anonymous, "El PDF coincide byte a byte");
  await capturePublic(anonymous, "comparison-revoked");
  checkpoint("integrity-independent-state");
  // Expired completed synthetic publication; every production guard stays on.
  const expiredOp = randomUUID(),
    expiredCert = randomUUID(),
    expiredCode = randomUUID();
  sql(
    `INSERT INTO public.certificate_issuance_operations(id,institution_id,actor_id,holder_id,idempotency_key,request_fingerprint,pdf_hash,target_certificate_id,stored_hash,status,title,expires_at)
    VALUES('${expiredOp}','${f.verified}','${f.owner.id}','${f.holder.id}',gen_random_uuid(),repeat('a',64),'${digest}','${expiredCert}','${digest}','finalizing','8D Expired','2021-01-01T00:00:00.123456Z');
    INSERT INTO public.certificates(id,institution_id,issued_by,holder_id,title,credential_code,issued_at,expires_at,document_path,document_hash,issuance_operation_id)
    VALUES('${expiredCert}','${f.verified}','${f.owner.id}','${f.holder.id}','8D Expired','${expiredCode}','2020-01-01T00:00:00.654321Z','2021-01-01T00:00:00.123456Z','${f.verified}/${expiredCert}.pdf','${digest}','${expiredOp}');
    UPDATE public.certificate_issuance_operations SET status='completed',certificate_id='${expiredCert}' WHERE id='${expiredOp}';`,
  );
  await navigateDocument(anonymous, "Page.navigate", {
    url: `${origin}/#/verify/${expiredCode}`,
  });
  await ready(anonymous, "Certificado caducado");
  await select(anonymous, "Comparar mi PDF", original);
  await outcome(anonymous, "El PDF coincide byte a byte");
  await outcome(anonymous, "Certificado caducado");
  await navigateDocument(anonymous, "Page.navigate", { url: link });
  await ready(anonymous, "Certificado revocado");
  checkpoint("expiry-independent-integrity");
  for (let race = 0; race < 2; race++) {
    stage = `race-${race}`;
    fault = "hold";
    heldResponse = null;
    await select(anonymous, "Comparar mi PDF", original);
    await until(() => !!heldResponse, "Old real comparison retained");
    await click(anonymous, "Consultar otro código");
    await enter(anonymous, "Código del certificado", randomUUID());
    await click(anonymous, "Verificar");
    await outcome(anonymous, "No encontramos un registro verificable");
    heldResponse();
    heldResponse = null;
    await delay(250);
    verify(
      !(await semantics(anonymous)).includes("El PDF coincide byte a byte"),
      "Old comparison cannot replace code B",
    );
    await navigateDocument(anonymous, "Page.navigate", { url: link });
    await ready(anonymous, "Certificado revocado");
    fault = "hold";
    await select(anonymous, "Comparar mi PDF", original);
    await until(() => !!heldResponse, "Cancelable real comparison retained");
    await click(anonymous, "Cancelar comparación");
    heldResponse();
    heldResponse = null;
    await delay(250);
    await outcome(anonymous, "Comparación cancelada.");
    verify(
      !(await semantics(anonymous)).includes("El PDF coincide byte a byte"),
      "Cancelled query cannot publish integrity",
    );
  }
  checkpoint("bounded-races");
  // Failed new queries explicitly retain the old successful checked_at.
  for (
    const mode of ["503", "malformed", "excessive", "disconnect", "timeout"]
  ) {
    stage = `failure-${mode}`;
    fault = mode;
    before = comparePosts;
    await select(anonymous, "Comparar mi PDF", original);
    await outcome(
      anonymous,
      mode === "503"
        ? "La comparación está temporalmente no disponible."
        : mode === "malformed" || mode === "excessive"
        ? "No pudimos interpretar la comparación."
        : "No pudimos conectar. Reintenta manualmente.",
      30000,
    );
    await outcome(anonymous, "Resultado anterior.");
    verify(comparePosts === before + 1, "Failure never auto retries");
    await click(anonymous, "Reintentar comparación");
    await outcome(anonymous, "El PDF coincide byte a byte");
    verify(
      !(await semantics(anonymous)).includes("Resultado anterior."),
      "Explicit recovery refreshes checked_at",
    );
    checkpoint(`failure-${mode}`);
  }
  checkpoint("public-failures-explicit-recovery");
  // Actual 60-second window, no clock/counter manipulation during renewal.
  sql(
    "UPDATE certichain_private.public_verification_budget SET used=59,window_started_at=clock_timestamp();",
  );
  await select(anonymous, "Comparar mi PDF", original);
  await outcome(anonymous, "El PDF coincide byte a byte");
  await select(anonymous, "Comparar mi PDF", original);
  await outcome(anonymous, "Temporalmente no se admiten más consultas.");
  before = comparePosts;
  const windowStarted = Date.now();
  await delay(1000);
  verify(comparePosts === before, "No automatic retry after 429");
  await until(
    async () => !(await semantics(anonymous)).includes("Espera "),
    "Real Retry-After expiry",
    65000,
  );
  verify(
    Date.now() - windowStarted >= 57000 && comparePosts === before,
    "Real time elapsed and still no automatic POST",
  );
  await click(anonymous, "Reintentar comparación");
  await outcome(anonymous, "El PDF coincide byte a byte");
  verify(
    comparePosts === before + 1 &&
      sql("SELECT used FROM certichain_private.public_verification_budget;") ===
        "1",
    "New real window begins with single explicit query",
  );
  checkpoint("real-window-renewal");
  before = publicPosts;
  await navigateDocument(anonymous, "Page.reload", { ignoreCache: true });
  await ready(anonymous, "Certificado revocado");
  verify(publicPosts === before + 1, "Release reload single public query");
  await click(anonymous, "Consultar otro código");
  await enter(anonymous, "Código del certificado", randomUUID());
  await click(anonymous, "Verificar");
  await outcome(anonymous, "No encontramos un registro verificable");
  await evaluate(anonymous, "history.back()");
  await outcome(anonymous, "Código del certificado");
  await evaluate(anonymous, "history.back()");
  await outcome(anonymous, "Certificado revocado");
  await evaluate(anonymous, "history.forward()");
  await outcome(anonymous, "Código del certificado");
  checkpoint("reload-history");
  await click(issuer, "Volver");
  await click(issuer, "Cerrar sesión");
  await login(issuer, f.outsider);
  verify(
    !(await semantics(issuer)).includes("8D Release Certificate"),
    "Private wallet isolated after account change",
  );
  await click(issuer, "Cerrar sesión");
  await outcome(issuer, "Comenzar");
  checkpoint("logout-account-isolation");
  verify(!failure, "Wire privacy and local assets");
  writeFileSync(
    join(evidence, "result.json"),
    JSON.stringify(
      {
        ...revision,
        evaluated_at: evaluatedAt,
        entrypoint: "lib/main.dart",
        mode: "release",
        build_reused: process.env.CERTICHAIN_RELEASE_SKIP_BUILD === "1",
        result: "PASS",
        camera_enabled: camera.enabled,
        camera_scenarios: camera.scenarios,
        node: process.versions.node,
        chrome: browserInfo.Browser,
        assertions,
        artifact_checks: artifactChecks,
        issue_posts: issuePosts,
        public_posts: publicPosts,
        comparison_posts: comparePosts,
        timings,
        stages,
        total_ms: Date.now() - started,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(
    `PASS 8D production release: ${assertions} assertions; ${publicPosts} verify, ${comparePosts} compare POST; camera capture ${
      camera.enabled ? "enabled" : "SKIP"
    }`,
  );
} catch (error) {
  writeFileSync(
    join(evidence, "failure.json"),
    JSON.stringify(
      {
        ...revision,
        evaluated_at: evaluatedAt,
        stage,
        result: "FAIL",
        camera_enabled: camera.enabled,
        camera_scenarios: camera.scenarios,
        error_type: error.constructor.name,
        camera: cameraDiagnostic,
        elapsed_ms: Date.now() - started,
        stages,
      },
      null,
      2,
    ) + "\n",
  );
  console.error(`8D failed at ${stage}: ${error.message}`);
  throw new Error(`8D stage ${stage} failed (${error.constructor.name})`);
} finally {
  heldResponse?.();
  for (const cdp of sockets) cdp.close();
  await stopChrome(chrome);
  if (server) {
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
  }
  try {
    if (budgetSaved) {
      const b = JSON.parse(budgetSaved);
      sql(
        `UPDATE certichain_private.public_verification_budget SET used=${
          Number(b.used)
        },window_started_at='${b.window_started_at}'::timestamptz;`,
      );
    }
  } finally {
    try {
      await f?.close();
    } finally {
      process.chdir(mobile);
      rmSync(directory, { recursive: true, force: true });
    }
  }
}
