import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { createHash } from "node:crypto";
import {
  connectCdp,
  evaluate,
  launchChrome,
  stopChrome,
} from "../../mobile/tool/browser_harness.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const work = join(root, "tools/branding/.render");
const output = join(root, "docs/assets");
const assets = new Map([
  ["/", ["docs/branding/preview.html", "text/html"]],
  ...["html", "css", "js"].map((ext) => [
    `/docs/branding/preview.${ext}`,
    [
      `docs/branding/preview.${ext}`,
      { html: "text/html", css: "text/css", js: "text/javascript" }[ext],
    ],
  ]),
  [
    "/tools/branding/node_modules/lottie-web/build/player/lottie.min.js",
    [
      "tools/branding/node_modules/lottie-web/build/player/lottie.min.js",
      "text/javascript",
    ],
  ],
  [
    "/mobile/assets/animations/certichain_intro.json",
    ["mobile/assets/animations/certichain_intro.json", "application/json"],
  ],
  [
    "/assets/branding/certichain-logo.svg",
    ["assets/branding/certichain-logo.svg", "image/svg+xml"],
  ],
]);
// Deliberately serve only branding assets, never the whole repository.
const server = createServer(async (request, response) => {
  const asset = assets.get(new URL(request.url, "http://localhost").pathname);
  if (!asset || !["GET", "HEAD"].includes(request.method)) {
    response.writeHead(404);
    response.end();
    return;
  }
  try {
    const data = await readFile(join(root, asset[0]));
    response.writeHead(200, {
      "Content-Type": `${asset[1]}; charset=utf-8`,
      "Cache-Control": "no-store",
    });
    response.end(request.method === "HEAD" ? undefined : data);
  } catch {
    response.writeHead(404);
    response.end("Run npm ci in tools/branding and generate the assets first.");
  }
});
const serve = process.argv.includes("--serve");
await new Promise((ready) =>
  server.listen(serve ? 8787 : 0, "127.0.0.1", ready),
);
const origin = `http://127.0.0.1:${server.address().port}`;
if (serve) {
  console.log(`${origin}/docs/branding/preview.html`);
} else {
  process.env.CERTICHAIN_TEST_CAMERA = "0";
  await mkdir(work, { recursive: true });
  await mkdir(output, { recursive: true });
  const profile = await mkdtemp(join(tmpdir(), "certichain-branding-"));
  let chrome, cdp;
  const errors = [],
    requests = [];
  try {
    chrome = await launchChrome(profile, ["about:blank"]);
    const tabs = await (
      await fetch(`http://127.0.0.1:${chrome.port}/json/list`)
    ).json();
    cdp = await connectCdp(
      tabs.find((tab) => tab.type === "page").webSocketDebuggerUrl,
      (event) => {
        if (event.method === "Runtime.exceptionThrown")
          errors.push("Browser exception");
        if (event.method === "Network.requestWillBeSent")
          requests.push(event.params.request.url);
      },
    );
    await cdp("Page.enable");
    await cdp("Runtime.enable");
    await cdp("Network.enable");
    await cdp("Emulation.setDeviceMetricsOverride", {
      width: 1000,
      height: 1040,
      deviceScaleFactor: 1,
      mobile: false,
    });
    await cdp("Page.navigate", { url: `${origin}/docs/branding/preview.html` });
    let ready = false;
    for (let attempt = 0; attempt < 120; attempt++) {
      ready = await evaluate(cdp, "window.branding?.ready === true");
      if (ready) break;
      await delay(100);
    }
    assert(
      ready,
      `Preview did not load: ${JSON.stringify(await evaluate(cdp, "window.branding?.errors"))}`,
    );
    const data = await evaluate(
      cdp,
      "({fr:branding.data.fr,op:branding.data.op,ip:branding.data.ip})",
    );
    const count = Math.ceil(data.op - data.ip);
    const end = count - 1;
    // Live playback, completion, controls and no-loop final state.
    await evaluate(
      cdp,
      "branding.animation.setSpeed(1); document.getElementById('restart').click()",
    );
    await delay(350);
    const playing = await evaluate(cdp, "branding.animation.currentFrame");
    assert(playing > 0 && playing < 40);
    await evaluate(cdp, "document.getElementById('play').click()");
    const paused = await evaluate(cdp, "branding.animation.currentFrame");
    await delay(120);
    assert.equal(
      await evaluate(cdp, "branding.animation.currentFrame"),
      paused,
    );
    await evaluate(cdp, "document.getElementById('play').click()");
    await delay(Math.ceil((count / data.fr) * 1000) + 200);
    assert.equal(
      await evaluate(
        cdp,
        `branding.animation.isPaused && Math.floor(branding.animation.currentFrame) === ${end}`,
      ),
      true,
    );
    const preview = await cdp("Page.captureScreenshot", {
      format: "png",
      captureBeyondViewport: false,
    });
    await writeFile(
      join(output, "certichain_intro_preview.png"),
      Buffer.from(preview.data, "base64"),
    );

    const writePng = async (path, expression) => {
      const url = await evaluate(cdp, expression);
      assert(url.startsWith("data:image/png;base64,"));
      await writeFile(path, Buffer.from(url.split(",")[1], "base64"));
    };
    // SVG-rendered Lottie frames are the sole input to GIF/WebP encoding.
    for (let frame = 0; frame < count; frame++) {
      await writePng(
        join(work, `frame-${String(frame).padStart(3, "0")}.png`),
        `branding.snapshot(${frame},600)`,
      );
    }
    for (let frame = 0; frame < count; frame++) {
      await writePng(
        join(work, `alpha-${frame}.png`),
        `branding.snapshot(${frame},600,null)`,
      );
    }
    await writePng(
      join(work, "static.png"),
      `(async()=>branding.rasterize(await(await fetch('/assets/branding/certichain-logo.svg')).text(),600,'#080B1C'))()`,
    );
    // A second lottie-web renderer catches SVG-only gradient/path mistakes.
    await evaluate(
      cdp,
      `new Promise(resolve => {
      const host = document.createElement('div'); host.style.cssText='width:600px;height:600px;position:absolute;left:-2000px'; document.body.append(host);
      window.canvasAnimation=lottie.loadAnimation({container:host,renderer:'canvas',loop:false,autoplay:false,animationData:structuredClone(branding.data),rendererSettings:{dpr:1}});
      canvasAnimation.addEventListener('DOMLoaded',()=>{canvasAnimation.goToAndStop(${end},true);resolve()});
    })`,
    );
    await writePng(
      join(work, "canvas.png"),
      "canvasAnimation.renderer.canvasContext.canvas.toDataURL('image/png')",
    );
    await cdp("Network.emulateNetworkConditions", {
      offline: true,
      latency: 0,
      downloadThroughput: 0,
      uploadThroughput: 0,
    });
    await writePng(join(work, "offline.png"), `branding.snapshot(${end},600)`);
    for (const size of [160, 256, 512, 600]) {
      await evaluate(
        cdp,
        `document.getElementById('size').value='${size}';document.getElementById('size').dispatchEvent(new Event('change'))`,
      );
      assert.equal(
        await evaluate(
          cdp,
          "Math.round(document.getElementById('animation').getBoundingClientRect().width)",
        ),
        size,
      );
    }
    for (const background of ["transparent", "light", "dark"]) {
      await evaluate(
        cdp,
        `document.getElementById('background').value='${background}';document.getElementById('background').dispatchEvent(new Event('change'))`,
      );
      assert(
        await evaluate(
          cdp,
          `document.getElementById('stage').classList.contains('${background}')`,
        ),
      );
    }
    await writePng(
      join(work, "light.png"),
      `branding.snapshot(${end},600,'#F5F6FA')`,
    );
    await writePng(join(work, "small.png"), `branding.snapshot(${end},160)`);
    assert.deepEqual(errors, []);
    assert.deepEqual(await evaluate(cdp, "branding.errors"), []);
    const remote = requests.filter(
      (url) =>
        !url.startsWith(origin) &&
        !url.startsWith("blob:") &&
        !url.startsWith("data:") &&
        !url.startsWith("chrome://"),
    );
    assert.deepEqual(remote, [], "Unexpected remote resource");
    const source = await readFile(
      join(root, "mobile/assets/animations/certichain_intro.json"),
    );
    const report = {
      renderer: "lottie-web 5.13.0 / SVG + Canvas",
      browser: (await cdp("Browser.getVersion")).product,
      node: process.version,
      sha256: createHash("sha256").update(source).digest("hex"),
      frames: count,
      fps: data.fr,
      size: 600,
      playback: "PASS",
      controls: "PASS",
      offline: "PASS",
      sizes: [160, 256, 512, 600],
      backgrounds: ["dark", "transparent", "light"],
      errors,
      camera: {
        result: "NOT_RUN",
        reason:
          "Omitidas por instrucción del usuario; no hay cámara física disponible",
      },
    };
    await writeFile(
      join(work, "render-report.json"),
      JSON.stringify(report, null, 2) + "\n",
    );
    console.log(JSON.stringify(report, null, 2));
  } finally {
    cdp?.close();
    await stopChrome(chrome?.child);
    server.close();
    // Keep the isolated temp profile outside the checkout for diagnostics;
    // never delete a computed directory recursively on Windows.
  }
}
