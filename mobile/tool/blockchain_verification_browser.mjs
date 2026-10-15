// Production main.dart, HTTPS, real Auth/SQL/Storage/Edge/Anvil. Host-only worker.
// No screenshots or dumps of opening/PDF/credentials; temporary inputs cleaned.
import { createServer } from "node:https";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { createHash, X509Certificate } from "node:crypto";
import { Buffer } from "node:buffer";
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
import { setTimeout as delay } from "node:timers/promises";
import {
  connectCdp,
  evaluate,
  launchChrome,
  navigateDocument,
  prepareDocument,
  sourceRevision,
  stopChrome,
} from "./browser_harness.mjs";
import {
  countPublicPost,
  expectSinglePublicPost,
  publicEndpoint,
  publicHeadersAreAnonymous,
} from "./public_verification_requests.mjs";

export async function runBrowserJourney(env) {
  const root = resolve(process.env.CERTICHAIN_SOURCE_ROOT ?? ".."),
    mobile = join(root, "mobile");
  const f = env.f, origin = "https://127.0.0.1:7360";
  const phase = env.phase ?? "9d";
  const directory = mkdtempSync(join(tmpdir(), "certichain-browser-9d-"));
  if (!resolve(directory).startsWith(resolve(tmpdir()) + sep)) {
    throw new Error("Unsafe own directory");
  }
  const build = join(mobile, `build/phase${phase}-release`),
    evidence = join(mobile, `build/phase${phase}-evidence`);
  mkdirSync(evidence, { recursive: true });
  let server, chrome, wireFailure, heldOpening, holdOpening = false;
  let heldRevocation, holdRevocation = false, revokePosts = 0;
  let assertions = 0,
    publicPosts = 0,
    issuePosts = 0,
    anchorPosts = 0,
    openingPosts = 0;
  const sockets = [], stages = [], httpStatuses = [];
  const check = (v, label) => {
    if (!v) {
      console.log(JSON.stringify({ case: label, result: "FAIL" }));
      throw new Error(label);
    }
    assertions++;
  };
  const until = async (predicate, label, ms = 25000) => {
    const deadline = Date.now() + ms;
    while (Date.now() < deadline) {
      if (wireFailure) throw wireFailure;
      if (await predicate()) return;
      await delay(60);
    }
    console.log(
      JSON.stringify({ stage: label, result: "FAIL", reason: "deadline" }),
    );
    throw new Error(`Deadline: ${label}`);
  };
  const stage = (name) => {
    stages.push({ stage: name, result: "PASS" });
    console.log(JSON.stringify(stages.at(-1)));
  };
  const pub = [
    "/functions/v1/verify-certificate",
    "/functions/v1/verify-certificate-v2",
    "/functions/v1/verify-certificate-v3",
    "/functions/v1/compare-certificate-hash",
  ];
  try {
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
    check(tls.status === 0, "Ephemeral TLS");
    const spki = createHash("sha256").update(
      new X509Certificate(readFileSync(cert)).publicKey.export({
        type: "spki",
        format: "der",
      }),
    ).digest("base64");
    const config = join(directory, "public-config.json");
    writeFileSync(
      config,
      JSON.stringify({
        SUPABASE_URL: origin,
        SUPABASE_PUBLISHABLE_KEY: f.local.ANON_KEY,
        PUBLIC_VERIFICATION_BASE_URL: origin + "/",
      }),
    );
    const args = [
      "build",
      "web",
      "--release",
      "--no-pub",
      "--no-web-resources-cdn",
      "--target=lib/main.dart",
      `--dart-define-from-file=${config}`,
      `--output=build/phase${phase}-release`,
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
    check(built.status === 0, "Production main.dart release builds");
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
                "No backend secret in Flutter artifact",
              );
            }
          }
        }
      }
    };
    scan(build);
    stage("main-release-no-backend-secrets");
    server = createServer(
      { key: readFileSync(key), cert: readFileSync(cert) },
      async (req, res) => {
        try {
          const path = new URL(req.url, origin).pathname;
          res.setHeader("cache-control", "no-store");
          if (
            ["/auth/v1/", "/rest/v1/", "/storage/v1/", "/functions/v1/"].some(
              (prefix) => path.startsWith(prefix),
            )
          ) {
            const chunks = [];
            let size = 0;
            // Deno's Node compatibility can leave an empty IncomingMessage
            // iterator waiting on GET. Read only actual HTTP request bodies.
            if (
              req.headers["content-length"] &&
                req.headers["content-length"] !== "0" ||
              req.headers["transfer-encoding"]
            ) {
              for await (const chunk of req) {
                size += chunk.length;
                if (size > 9 * 1048576) throw new Error("Proxy bound");
                chunks.push(chunk);
              }
            }
            const body = Buffer.concat(chunks);
            if (pub.includes(path) && req.method === "POST") {
              check(
                !["authorization", "apikey", "cookie"].some((k) =>
                  req.headers[k]
                ),
                "Public wire omits credentials",
              );
              const input = JSON.parse(body);
              check(
                Object.keys(input).sort().join(",") ===
                  (path.endsWith("compare-certificate-hash")
                    ? "credential_code,document_sha256"
                    : "credential_code"),
                "Closed public input",
              );
              publicPosts++;
            }
            if (
              path.endsWith("/issue-certificate") && req.method === "POST"
            ) issuePosts++;
            if (
              path.endsWith("/anchor-certificate") && req.method === "POST"
            ) anchorPosts++;
            if (path.endsWith("/revoke-certificate") && req.method === "POST") {
              revokePosts++;
            }
            if (
              path.endsWith("/certificate-opening") && req.method === "POST"
            ) openingPosts++;
            const upstream = await fetch(
              f.local.API_URL + path + new URL(req.url, origin).search,
              {
                method: req.method,
                headers: {
                  ...req.headers,
                  host: new URL(f.local.API_URL).host,
                  connection: "close",
                },
                ...(["GET", "HEAD"].includes(req.method) ? {} : { body }),
                signal: AbortSignal.timeout(45000),
              },
            );
            if (path.startsWith("/auth/v1/") || path.startsWith("/rest/v1/")) {
              httpStatuses.push({
                path: path.split("/").at(-1),
                status: upstream.status,
              });
            }
            const response = Buffer.from(await upstream.arrayBuffer());
            if (path.startsWith("/rest/v1/") && !upstream.ok) {
              const error = JSON.parse(response.toString());
              console.log(
                JSON.stringify({
                  stage: "rest-failure",
                  resource: path.split("/").at(-1),
                  status: upstream.status,
                  code: /^[A-Z0-9_]+$/.test(error.code ?? "")
                    ? error.code
                    : "OTHER",
                }),
              );
            }
            if (
              path.endsWith("/certificate-opening") && holdOpening &&
              req.method === "POST"
            ) {
              holdOpening = false;
              await new Promise((r) => heldOpening = r);
            }
            if (
              path.endsWith("/revocation-progress") && holdRevocation &&
              req.method === "POST"
            ) {
              holdRevocation = false;
              await new Promise((r) => heldRevocation = r);
            }
            res.writeHead(
              upstream.status,
              Object.fromEntries([...upstream.headers].filter(([k]) =>
                ![
                  "content-length",
                  "connection",
                  "transfer-encoding",
                  "content-encoding",
                ].includes(k)
              )),
            );
            res.end(response);
            return;
          }
          const relative = path === "/" ? "index.html" : path.slice(1);
          const file = resolve(build, relative);
          if (!file.startsWith(resolve(build) + sep)) {
            throw new Error("Static path");
          }
          res.setHeader(
            "content-type",
            ({
              ".html": "text/html",
              ".js": "text/javascript",
              ".json": "application/json",
              ".wasm": "application/wasm",
              ".ttf": "font/ttf",
            })[extname(file)] ?? "application/octet-stream",
          );
          res.end(readFileSync(file));
        } catch {
          wireFailure = new Error("Owned HTTPS proxy failed");
          if (!res.headersSent) res.writeHead(503);
          res.end('{"error":"temporary_failure"}');
        }
      },
    );
    await new Promise((r, j) => {
      server.once("error", j);
      server.listen(7360, "127.0.0.1", r);
    });
    const launch = await launchChrome(
      join(directory, "chrome"),
      [
        `--ignore-certificate-errors-spki-list=${spki}`,
        "about:blank",
      ],
      20000,
      { visible: process.env.CERTICHAIN_9E_VISIBLE_BROWSER === "1" },
    );
    chrome = launch.child;
    const browserInfo =
      await (await fetch(`http://127.0.0.1:${launch.port}/json/version`))
        .json();
    const browser = await connectCdp(browserInfo.webSocketDebuggerUrl);
    sockets.push(browser);
    async function page() {
      const publicPosts = { v1: 0, v2: 0, v3: 0, comparison: 0 };
      const publicIds = new Set(), extra = new Map();
      const assertHeaders = (headers) => {
        if (!publicHeadersAreAnonymous(headers)) {
          wireFailure = new Error("Public browser request sent credentials");
        }
      };
      const context = await browser("Target.createBrowserContext");
      await browser("Browser.setDownloadBehavior", {
        behavior: "allow",
        downloadPath: join(directory, "downloads"),
        browserContextId: context.browserContextId,
      });
      const target = await browser("Target.createTarget", {
        url: "about:blank",
        browserContextId: context.browserContextId,
      });
      const list =
        await (await fetch(`http://127.0.0.1:${launch.port}/json/list`)).json();
      const cdp = await connectCdp(
        list.find((t) => t.id === target.targetId).webSocketDebuggerUrl,
        (event) => {
          if (event.method === "Page.fileChooserOpened") {
            cdp.chooser = event.params;
          }
          if (event.method === "Network.requestWillBeSent") {
            const url = new URL(event.params.request.url);
            if (publicEndpoint(url.pathname)) {
              publicIds.add(event.params.requestId);
              assertHeaders(event.params.request.headers);
              if (extra.has(event.params.requestId)) {
                assertHeaders(extra.get(event.params.requestId));
              }
            }
            countPublicPost(publicPosts, event.params.request);
            if (
              ["http:", "https:"].includes(url.protocol) &&
              !["127.0.0.1", "localhost"].includes(url.hostname)
            ) wireFailure = new Error("External client request");
          }
          if (event.method === "Network.requestWillBeSentExtraInfo") {
            extra.set(event.params.requestId, event.params.headers);
            if (publicIds.has(event.params.requestId)) {
              assertHeaders(event.params.headers);
            }
          }
        },
      );
      sockets.push(cdp);
      await cdp("Page.enable");
      await cdp("Runtime.enable");
      await cdp("Network.enable");
      await cdp("DOM.enable");
      await cdp("Page.setInterceptFileChooserDialog", { enabled: true });
      cdp.browserContextId = context.browserContextId;
      cdp.publicPosts = publicPosts;
      await cdp("Emulation.setDeviceMetricsOverride", {
        width: 390,
        height: 844,
        deviceScaleFactor: 1,
        mobile: false,
      });
      return cdp;
    }
    const domSearch =
      `globalThis.ccElements=(selector)=>{const result=[];const visit=(root)=>{result.push(...root.querySelectorAll(selector));for(const e of root.querySelectorAll('*'))if(e.shadowRoot)visit(e.shadowRoot);};visit(document);return result;}`;
    async function semantics(cdp) {
      const tree = await cdp("Accessibility.getFullAXTree");
      return tree.nodes.filter((n) => !n.ignored).map((n) =>
        n.name?.value ?? ""
      ).join(" ");
    }
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
        "Production semantics ready",
        45000,
      );
    }
    async function outcome(cdp, text) {
      await until(
        async () => (await semantics(cdp)).includes(text),
        `UI outcome: ${text}`,
      );
    }
    async function element(cdp, label, input = false) {
      const expression = `${domSearch};(()=>{const a=ccElements(${
        JSON.stringify(
          input
            ? "flt-semantics input,flt-semantics textarea"
            : "flt-semantics",
        )
      });const match=e=>e.getAttribute('aria-label')===${
        JSON.stringify(label)
      }||(e.getAttribute('aria-label')||'').split('\\n').includes(${
        JSON.stringify(label)
      })||e.textContent===${
        JSON.stringify(label)
      }||(e.getAttribute('role')==='button'&&e.textContent.includes(${
        JSON.stringify(label)
      }));const e=a.find(e=>e.getAttribute('role')==='button'&&match(e))||a.find(match);if(!e)return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,width:r.width,height:r.height};})()`;
      let found;
      try {
        await until(async () => {
          found = await evaluate(cdp, expression);
          return found && found.width > 0;
        }, "Semantic control");
      } catch (e) {
        console.log(
          JSON.stringify({
            stage: "control-diagnostic",
            control: label,
            http: httpStatuses.slice(-15),
          }),
        );
        throw e;
      }
      await delay(200);
      return await evaluate(
        cdp,
        expression.replace("e.scrollIntoView({block:'center'});", ""),
      );
    }
    async function click(cdp, label) {
      await cdp("Page.bringToFront");
      await element(cdp, label);
      await evaluate(
        cdp,
        `${domSearch};(()=>{const a=ccElements('flt-semantics');const match=e=>e.getAttribute('aria-label')===${
          JSON.stringify(label)
        }||(e.getAttribute('aria-label')||'').split('\\n').includes(${
          JSON.stringify(label)
        })||e.textContent===${
          JSON.stringify(label)
        }||(e.getAttribute('role')==='button'&&e.textContent.includes(${
          JSON.stringify(label)
        }));const e=a.find(e=>e.getAttribute('role')==='button'&&match(e))||a.find(match);e.click();})()`,
      );
      await delay(150);
    }
    async function enter(cdp, label, text) {
      await cdp("Page.bringToFront");
      for (let attempt = 0; attempt < 3; attempt++) {
        const p = await element(cdp, label, true);
        for (const type of ["mousePressed", "mouseReleased"]) {
          await cdp("Input.dispatchMouseEvent", {
            type,
            x: p.x,
            y: p.y,
            button: "left",
            clickCount: 1,
          });
        }
        await evaluate(
          cdp,
          `${domSearch};ccElements('input,textarea').filter(e=>e.getAttribute('aria-label')===${
            JSON.stringify(label)
          }&&e.getBoundingClientRect().width>0).at(-1)?.focus()`,
        );
        await delay(250);
        for (const type of ["keyDown", "keyUp"]) {
          await cdp("Input.dispatchKeyEvent", {
            type,
            key: "a",
            code: "KeyA",
            modifiers: 2,
            windowsVirtualKeyCode: 65,
          });
        }
        await cdp("Input.insertText", { text });
        await delay(150);
        if (
          await evaluate(
            cdp,
            `${domSearch};ccElements('input,textarea').some(e=>e.value===${
              JSON.stringify(text)
            })`,
          )
        ) return;
      }
      throw new Error("UI field entry");
    }
    async function select(cdp, label, file) {
      cdp.chooser = null;
      await click(cdp, label);
      await until(() => !!cdp.chooser, `Production file chooser: ${label}`);
      if (!file) {
        await click(cdp, "Cancelar comprobación");
        await until(
          async () =>
            await evaluate(
              cdp,
              "!document.querySelector('#certichain-opening-input') && !document.querySelector('#certichain-comparison-pdf-input')",
            ),
          "Production cancellation removes owned picker input",
        );
        return;
      }
      await cdp("DOM.setFileInputFiles", {
        files: [file],
        backendNodeId: cdp.chooser.backendNodeId,
      });
    }
    async function login(cdp, user) {
      await navigateDocument(cdp, "Page.navigate", { url: origin + "/" });
      await ready(cdp, "Comenzar");
      await click(cdp, "Comenzar");
      await outcome(cdp, "Iniciar sesión");
      await enter(cdp, "Email", user.email);
      await enter(cdp, "Contraseña", user.password);
      const fields = await evaluate(
        cdp,
        `${domSearch};({email:ccElements('input').some(e=>e.getAttribute('aria-label')==='Email'&&e.value===${
          JSON.stringify(user.email)
        }),password:ccElements('input').some(e=>e.getAttribute('aria-label')==='Contraseña'&&e.value===${
          JSON.stringify(user.password)
        })})`,
      );
      check(
        fields.email && fields.password,
        "Both production login fields have expected values",
      );
      await click(cdp, "Iniciar sesión");
      try {
        await outcome(cdp, "Cerrar sesión");
      } catch (e) {
        const visible = await semantics(cdp);
        console.log(JSON.stringify({
          stage: "login-diagnostic",
          http: httpStatuses,
          labels: [
            "Iniciar sesión",
            "Email",
            "Contraseña",
            "No pudimos",
            "incorrect",
            "Cerrar sesión",
            "Mi perfil",
            "Introduce tu email",
            "Introduce un email válido",
            "Introduce tu contraseña",
          ].filter((label) => visible.includes(label)),
        }));
        throw e;
      }
    }
    const original = join(directory, "original.pdf"),
      modified = join(directory, "modified.pdf");
    const pdf = readFileSync(join(root, "blockchain/fixtures/synthetic.pdf"));
    writeFileSync(original, pdf);
    const changed = Buffer.from(pdf);
    changed[changed.length - 1] ^= 1;
    writeFileSync(modified, changed);
    const issuer = await page();
    await login(issuer, f.owner);
    await click(issuer, "Espacio institucional");
    await outcome(issuer, "Emitir certificado");
    const workspace = await semantics(issuer);
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
    await enter(issuer, "Título", "9D Browser Certificate");
    await click(issuer, "Siguiente");
    await select(issuer, "Seleccionar PDF", original);
    await outcome(issuer, "original.pdf");
    await click(issuer, "Siguiente");
    await click(issuer, "Emitir certificado");
    await outcome(issuer, "Ir a Certificados emitidos");
    check(issuePosts === 1, "Single production issuance");
    // SQL is host-only test evidence. Only minimal IDs are retained here.
    // The copied backend helper has the owned container name; injected closure
    // avoids reading the habitual stack from the browser harness's source path.
    const certificate = env.lookupCertificate("9D Browser Certificate");
    await click(issuer, "Ir a Certificados emitidos");
    await outcome(issuer, "9D Browser Certificate");
    await click(issuer, "Solicitar anclaje / consultar operación");
    await outcome(issuer, "Solicitar anclaje");
    await click(issuer, "Solicitar anclaje");
    await click(issuer, "Confirmar solicitud");
    await outcome(issuer, "Solicitud pendiente del worker.");
    check(anchorPosts === 1, "Single production anchor POST");
    stage("flutter-issue-request-real-pending");
    const operation = env.lookupOperation(certificate);
    await env.run(operation);
    await env.run(operation);
    await click(issuer, "Actualizar estado");
    await outcome(issuer, "Confirmación persistida.");
    stage("trusted-worker-and-flutter-explicit-refresh");
    const holder = await page();
    await login(holder, f.holder);
    await click(holder, "9D Browser Certificate");
    await outcome(holder, "Detalle del certificado");
    await click(holder, "Mostrar QR y enlace");
    await outcome(holder, "Copiar enlace");
    const code = env.lookupCode(certificate);
    const link = origin + "/#/verify/" + code;
    await element(holder, "QR del enlace de verificación");
    const decoded = spawnSync("node", [
      "--input-type=module",
      "-e",
      "import {readFileSync} from 'node:fs'; import {decodeQr} from './tool/verify_qr.mjs'; const input=JSON.parse(readFileSync(0,'utf8')); decodeQr(Buffer.from(input.png,'base64'),input.link);",
    ], {
      cwd: mobile,
      input: JSON.stringify({
        png: (await holder("Page.captureScreenshot", { format: "png" })).data,
        link,
      }),
      windowsHide: true,
      timeout: 10000,
    });
    check(
      decoded.status === 0,
      "Static production QR decodes independently to exact public link",
    );
    stage("production-qr-decoded-from-static-image");
    await browser("Browser.grantPermissions", {
      origin,
      browserContextId: holder.browserContextId,
      permissions: ["clipboardReadWrite", "clipboardSanitizedWrite"],
    });
    await click(holder, "Copiar enlace");
    await outcome(holder, "Enlace copiado");
    check(
      await evaluate(holder, "navigator.clipboard.readText()") === link,
      "Existing sharing link carries only code",
    );
    await click(holder, "Blockchain");
    await click(holder, "Consultar evidencia blockchain");
    await outcome(holder, "Anclaje confirmado.");
    await click(holder, "Obtener apertura");
    await outcome(holder, "Apertura obtenida.");
    stage("holder-public-evidence-and-private-opening");
    // Explicit export uses production adapter. Obtain same authorized opening
    // in host memory for verifier input; never write it to evidence/artifacts.
    await click(holder, "Exportar apertura JSON");
    await until(() => {
      try {
        return readdirSync(join(directory, "downloads")).includes(
          "apertura.json",
        );
      } catch {
        return false;
      }
    }, "Explicit opening export");
    const openingFile = join(directory, "downloads", "apertura.json"),
      openingData = JSON.parse(readFileSync(openingFile, "utf8"));
    check(
      openingData.credential_code === code,
      "Exported production opening belongs to certificate",
    );
    const anonymous = await page();
    let beforePage = { ...anonymous.publicPosts };
    await navigateDocument(anonymous, "Page.navigate", { url: link });
    await ready(anonymous, "Registro encontrado y vigente");
    await outcome(anonymous, "Anclaje confirmado.");
    await expectSinglePublicPost(
      anonymous.publicPosts,
      beforePage,
      "Anonymous startup uses one v3 POST",
      until,
      "v3",
    );
    await click(anonymous, "Comprobar con apertura");
    await select(anonymous, "Importar apertura JSON", openingFile);
    const beforeLocal = publicPosts;
    await select(anonymous, "Seleccionar PDF y comprobar apertura", original);
    await outcome(
      anonymous,
      "Apertura válida: el PDF corresponde al compromiso comprobado.",
    );
    check(
      publicPosts === beforeLocal,
      "Opening and PDF stay local without public POST",
    );
    await enter(
      anonymous,
      "JSON de apertura (máximo 2 KiB)",
      JSON.stringify(openingData),
    );
    await select(anonymous, "Seleccionar PDF y comprobar apertura", modified);
    await outcome(anonymous, "Mi copia: PDF no coincidente con la apertura.");
    check(
      publicPosts === beforeLocal,
      "Altered document comparison stays local",
    );
    check(
      readFileSync(original).equals(pdf),
      "Comparison preserves original bytes",
    );
    if (phase === "9e") {
      await select(anonymous, "Importar apertura JSON", null);
      await delay(300);
      check(
        publicPosts === beforeLocal,
        "JSON chooser cancellation does not query public verifier",
      );
      const malformed = join(directory, "invalid.json"),
        oversized = join(directory, "oversized.json");
      writeFileSync(malformed, '{"schema_version":"1","salt":null}');
      writeFileSync(oversized, " ".repeat(2049));
      for (const file of [malformed, oversized]) {
        await select(anonymous, "Importar apertura JSON", file);
        await outcome(
          anonymous,
          "Apertura inválida o de otro certificado/contrato.",
        );
      }
      await select(anonymous, "Importar apertura JSON", openingFile);
      await select(anonymous, "Seleccionar PDF y comprobar apertura", null);
      await delay(300);
      check(
        publicPosts === beforeLocal,
        "PDF chooser cancellation leaves explicit recovery without upload",
      );
      for (
        const [name, bytes, label] of [
          ["empty.pdf", Buffer.alloc(0), "El PDF está vacío."],
          ["too-large.pdf", Buffer.alloc(8388609), "El PDF supera 8 MiB."],
        ]
      ) {
        const file = join(directory, name);
        writeFileSync(file, bytes);
        await select(anonymous, "Importar apertura JSON", openingFile);
        await select(anonymous, "Seleccionar PDF y comprobar apertura", file);
        await outcome(anonymous, label);
      }
      await select(anonymous, "Importar apertura JSON", openingFile);
      await select(anonymous, "Seleccionar PDF y comprobar apertura", original);
      await outcome(
        anonymous,
        "Apertura válida: el PDF corresponde al compromiso comprobado.",
      );
      check(
        publicPosts === beforeLocal,
        "Explicit file recovery still makes no public request",
      );
      stage("real-file-cancellation-invalid-json-bounds-and-recovery");
    }
    stage("anonymous-v2-and-local-original-altered-opening");
    await click(anonymous, "Cerrar comprobación con apertura");
    beforePage = { ...anonymous.publicPosts };
    await navigateDocument(anonymous, "Page.reload");
    await ready(anonymous, "Registro encontrado y vigente");
    await expectSinglePublicPost(
      anonymous.publicPosts,
      beforePage,
      "Reload uses one v3 POST including late duplicates",
      until,
      "v3",
    );
    check(
      await evaluate(anonymous, `location.hash==='#/verify/${code}'`),
      "Reload retains old share route",
    );
    env.pause();
    try {
      await click(anonymous, "Actualizar comprobación");
      await outcome(anonymous, "No se pudo comprobar blockchain actualmente.");
      await outcome(anonymous, "Evidencia anterior");
    } finally {
      env.unpause();
    }
    await click(anonymous, "Actualizar comprobación");
    await outcome(anonymous, "Anclaje confirmado.");
    stage("actual-rpc-outage-previous-evidence-and-manual-recovery");
    if (phase === "10") {
      await click(issuer, "Revocación / consultar estado");
      await outcome(issuer, "Motivo privado obligatorio");
      await enter(
        issuer,
        "Motivo privado obligatorio",
        "Synthetic private browser revocation",
      );
      await click(issuer, "Revocar certificado");
      await outcome(issuer, "Revocación irreversible");
      await click(issuer, "Confirmar revocación");
      await outcome(issuer, "Revocado en CertiChain");
      check(
        revokePosts === 1,
        "Explicit confirmation submits one real revocation request",
      );
      await click(anonymous, "Actualizar comprobación");
      await outcome(
        anonymous,
        "Revocación blockchain pendiente de sincronización",
      );
      check(
        !(await semantics(anonymous)).includes(
          "Synthetic private browser revocation",
        ),
        "Anonymous page never receives private reason",
      );
      const revocation = env.lookupRevocation(certificate);
      await env.run(revocation);
      await env.run(revocation);
      await click(anonymous, "Actualizar comprobación");
      await outcome(anonymous, "Revocación EVM confirmada.");
      await outcome(anonymous, "Transacción de revocación");
      await click(issuer, "Consultar revocación / recuperar respuesta");
      await outcome(issuer, "Sincronización blockchain: confirmada");
      check(
        !readFileSync(join(build, "main.dart.js"), "utf8").includes(
          "Synthetic private browser revocation",
        ),
        "Private reason never enters release artifact",
      );
      stage(
        "production-revocation-sql-immediate-private-reason-durable-evm-public-evidence",
      );
      holdRevocation = true;
      await click(issuer, "Consultar revocación / recuperar respuesta");
      await until(
        () => !!heldRevocation,
        "Held real private revocation response",
      );
      await navigateDocument(issuer, "Page.navigate", { url: origin + "/" });
      await ready(issuer, "Cerrar sesión");
      await click(issuer, "Cerrar sesión");
      await outcome(issuer, "Comenzar");
      await login(issuer, f.outsider);
      heldRevocation();
      heldRevocation = null;
      await delay(300);
      check(
        !(await semantics(issuer)).includes(
          "Synthetic private browser revocation",
        ),
        "Real late private reason is discarded across owner logout and account B login",
      );
      stage("revocation-private-response-account-a-to-b-discarded");
    }
    if (phase === "9e") {
      env.exhaustBudget();
      beforePage = { ...anonymous.publicPosts };
      await click(anonymous, "Actualizar comprobación");
      await outcome(anonymous, "Temporalmente no se admiten más consultas.");
      await outcome(anonymous, "Espera");
      await delay(4500);
      check(
        anonymous.publicPosts.v3 === beforePage.v3 + 1 &&
          anonymous.publicPosts.v1 === beforePage.v1 &&
          anonymous.publicPosts.comparison === beforePage.comparison,
        "Real shared 429 and Retry-After expiry produce no polling or automatic request",
      );
      await click(anonymous, "Actualizar comprobación");
      await outcome(anonymous, "Anclaje confirmado.");
      check(
        anonymous.publicPosts.v3 === beforePage.v3 + 2,
        "Recovery after shared budget expiry requires manual action",
      );
      stage("real-shared-429-no-request-on-expiry");
    }
    // Retain a real authorized response across logout, then deliver it late.
    await click(holder, "Descartar apertura");
    holdOpening = true;
    await click(holder, "Obtener apertura");
    await until(() => !!heldOpening, "Held real opening response");
    await navigateDocument(holder, "Page.navigate", { url: origin + "/" });
    await ready(holder, "Cerrar sesión");
    await click(holder, "Cerrar sesión");
    await outcome(holder, "Comenzar");
    check(
      !(await semantics(holder)).includes("Copiar apertura"),
      "Logout clears private opening before delayed response",
    );
    if (phase === "9e") await login(holder, f.outsider);
    heldOpening();
    heldOpening = null;
    await delay(300);
    check(
      !(await semantics(holder)).includes("Copiar apertura"),
      "Late private opening never appears after logout",
    );
    stage("logout-invalidates-real-private-response");
    if (phase === "9e") {
      check(
        !(await semantics(holder)).includes("9D Browser Certificate"),
        "Account B has no holder A certificate",
      );
      check(
        await evaluate(
          holder,
          `!Object.values(localStorage).some(value => value.includes(${
            JSON.stringify(openingData.salt)
          }) || value.includes(${
            JSON.stringify(openingData.document_sha256)
          }))`,
        ),
        "No opening salt or registered hash in persistent browser preferences",
      );
      stage("account-a-to-b-discards-real-late-opening");
    }
    check(!wireFailure, "Wire has only local configured traffic");
    check(openingPosts >= 2, "Production opening endpoint called explicitly");
    const result = {
      result: "PASS",
      ...sourceRevision(root),
      evaluated_at: new Date().toISOString(),
      assertions,
      stages,
      issue_posts: issuePosts,
      anchor_posts: anchorPosts,
      opening_posts: openingPosts,
      revoke_posts: revokePosts,
      public_posts: publicPosts,
      anonymous_posts: { ...anonymous.publicPosts },
      browser_version: browserInfo.Browser,
      camera: "NOT_RUN",
      camera_reason:
        "Omitidas por instrucción del usuario; no hay cámara física disponible",
    };
    writeFileSync(
      join(evidence, "browser.json"),
      JSON.stringify(
        result,
        null,
        2,
      ),
    );
    console.log(
      JSON.stringify({
        suite: `phase${phase}-production-browser`,
        assertions,
        result: "PASS",
      }),
    );
    if (phase === "9d") {
      writeFileSync(
        join(evidence, "result.json"),
        JSON.stringify(result, null, 2),
      );
    }
    return result;
  } catch (error) {
    const failure = {
      ...sourceRevision(root),
      evaluated_at: new Date().toISOString(),
      result: "FAIL",
      assertions,
      stages,
      last_stage: stages.at(-1)?.stage ?? "prepare",
      wire_failure: !!wireFailure,
    };
    writeFileSync(
      join(evidence, "browser.json"),
      JSON.stringify(failure, null, 2),
    );
    if (
      error instanceof Error &&
      error.message.includes(
        "endpoint=/functions/v1/verify-certificate-v2 method=POST",
      )
    ) {
      console.log(error.message);
    }
    throw error;
  } finally {
    heldOpening?.();
    heldRevocation?.();
    for (const socket of sockets) socket.close();
    await stopChrome(chrome);
    if (server) {
      server.closeAllConnections();
      await new Promise((r) => server.close(r));
    }
    if (
      !resolve(directory).startsWith(resolve(tmpdir()) + sep) ||
      !/^certichain-browser-9d-/.test(basename(directory))
    ) throw new Error("Unsafe cleanup");
    rmSync(directory, { recursive: true, force: true });
  }
}
