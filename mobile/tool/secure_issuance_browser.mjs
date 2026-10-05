import { createServer } from "node:http";
import {
  connectCdp,
  evaluate,
  launchChrome,
  navigateDocument,
  stopChrome,
} from "./browser_harness.mjs";
import { createHash, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join, resolve, sep } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";
const backend = resolve(process.env.CERTICHAIN_TEST_BACKEND_ROOT ?? "..");
const { api, sql } = await import(
  pathToFileURL(join(backend, "supabase/scripts/local_supabase.mjs"))
);
const { check, fixture, until } = await import(
  pathToFileURL(join(backend, "supabase/tests/local_issuance_fixture.mjs"))
);
const { expiredToken } = await import(
  pathToFileURL(join(backend, "supabase/tests/issuance_hardening.mjs"))
);
const { pdfFixture } = await import(
  pathToFileURL(join(backend, "supabase/tests/pdf_fixture.mjs"))
);

// Starts its own JWT-verified Edge runtime, synthetic accounts and Chrome profile.
// Never serve on a public interface; test credentials live only in memory.
const root = resolve("build/secure-issuance-e2e");
const profile = mkdtempSync(join(tmpdir(), "certichain-chrome-7d-"));
check(
  resolve(profile).startsWith(resolve(tmpdir()) + sep),
  "Unsafe Chrome profile",
);
const initialDirectory = process.cwd();
process.chdir(backend);
const f = await fixture().catch((error) => {
  process.chdir(initialDirectory);
  rmSync(profile, { recursive: true, force: true });
  throw error;
});
const pdf = pdfFixture();
let chrome, socket;
let assertions = 0, checkpointError;
let issuedId;
function verify(condition, label) {
  check(condition, label);
  assertions++;
}
async function published(body) {
  const state = f.snapshot(f.verified, body.key);
  verify(
    state.operations.length === 1 && state.certificates.length === 1,
    "UI attempt has exactly one PostgreSQL certificate/operation",
  );
  const [op] = state.operations, [cert] = state.certificates;
  verify(
    op.status === "completed" && cert.id === op.certificate_id &&
      cert.id === op.target_certificate_id && cert.id === body.certificateId,
    "UI confirmed only persisted publication",
  );
  verify(
    op.request_fingerprint === body.digest && op.actor_id === f.owner.id &&
      cert.holder_id === f.holder.id && cert.title === "7D UI Certificate",
    "UI receipt fingerprint and normalized data match backend",
  );
  const bytes = await f.stored(f.verified, cert.id);
  verify(
    bytes.equals(pdf) &&
      createHash("sha256").update(bytes).digest("hex") === cert.document_hash &&
      op.pdf_hash === cert.document_hash &&
      op.stored_hash === cert.document_hash,
    "UI PDF exact final bytes/SHA-256",
  );
  verify(
    sql(
      `SELECT count(*) FROM storage.objects WHERE bucket_id='certificates' AND name='${f.verified}/${cert.id}.pdf';`,
    ) === "1",
    "One Storage object for UI attempt",
  );
  issuedId = cert.id;
  return { certificateId: cert.id };
}
const types = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".wasm": "application/wasm",
  ".json": "application/json",
  ".ttf": "font/ttf",
  ".png": "image/png",
};
const server = createServer(async (req, res) => {
  try {
    const path = new URL(req.url, "http://localhost").pathname;
    res.setHeader("cache-control", "no-store");
    if (path === "/fixture" && req.method === "GET") {
      const credentials = (user) => ({
        id: user.id,
        email: user.email,
        password: user.password,
      });
      const data = {
        apiUrl: f.local.API_URL,
        publicKey: f.local.ANON_KEY,
        owner: credentials(f.owner),
        holder: credentials(f.holder),
        outsider: credentials(f.outsider),
        issuer: credentials(f.issuer),
        verified: f.verified,
        pending: f.pending,
        suspended: f.suspended,
        legacy: f.legacy,
        pdf: pdf.toString("base64"),
        expiredToken: expiredToken(f.local, f.holder.token),
      };
      verify(
        !JSON.stringify(data).includes(f.local.SERVICE_ROLE_KEY) &&
          !JSON.stringify(data).includes(f.local.JWT_SECRET),
        "No server credential reaches browser fixture",
      );
      res.setHeader("content-type", "application/json");
      res.end(JSON.stringify(data));
      return;
    }
    if (path.startsWith("/checkpoint/") && req.method === "POST") {
      let raw = "";
      for await (const chunk of req) {
        raw += chunk;
        check(raw.length <= 4096, "Checkpoint budget");
      }
      const body = JSON.parse(raw || "{}");
      let data = {};
      if (path === "/checkpoint/published") data = await published(body);
      else if (path === "/checkpoint/denials") {
        const baseline = sql(
          `SELECT count(*) FROM public.certificates WHERE institution_id='${f.verified}';`,
        );
        for (const actor of [f.owner, f.holder, f.outsider]) {
          const direct = await f.json("/rest/v1/certificates", actor.token, {
            institution_id: f.verified,
            holder_id: f.holder.id,
            issued_by: actor.id,
            title: "Forbidden",
            credential_code: randomUUID(),
          });
          verify(
            direct.response.status === 403,
            "Direct certificate write denied",
          );
          const path = `${f.verified}/${issuedId}.pdf`;
          for (const method of ["POST", "PUT"]) {
            const r = await api(
              f.local,
              `/storage/v1/object/certificates/${path}`,
              actor.token,
              method,
              pdf,
              { "Content-Type": "application/pdf", "x-upsert": "true" },
            );
            verify(!r.ok, "Direct Storage create/replace denied");
            await r.arrayBuffer();
          }
          const deleted = await f.json(
            "/storage/v1/object/certificates",
            actor.token,
            { prefixes: [path] },
            "DELETE",
          );
          // Storage may return 200 [] for an RLS-filtered deletion: final state is decisive.
          verify(
            !deleted.response.ok || deleted.data.length === 0,
            "Direct Storage delete affected no object",
          );
        }
        verify(
          sql(
                `SELECT count(*) FROM public.certificates WHERE institution_id='${f.verified}';`,
              ) === baseline &&
            (await f.stored(f.verified, issuedId)).equals(pdf),
          "Rejected direct writes preserve row/object/bytes",
        );
      } else if (path === "/checkpoint/remove-member") {
        await f.rpc("remove_institution_member", {
          p_institution: f.verified,
          p_member: f.issuer.id,
        }, f.owner.token);
      } else if (path === "/checkpoint/suspend") {
        await f.rpc("set_institution_status", {
          p_institution: f.verified,
          p_status: "suspended",
        }, f.platform.token);
      } else if (path === "/checkpoint/final") {
        verify(
          sql(
            `SELECT count(*) FROM public.certificates WHERE institution_id='${f.verified}' AND issuance_operation_id IS NOT NULL;`,
          ) === "1",
          "One final publication across response-loss/UI recovery",
        );
        verify(
          sql(
            `SELECT count(*) FROM public.certificate_issuance_operations WHERE institution_id='${f.verified}' AND status<>'completed';`,
          ) === "0",
          "No unsuccessful UI operation remains",
        );
        verify(
          sql(
            `SELECT count(*) FROM storage.objects WHERE bucket_id='certificates' AND name LIKE '${f.verified}/%';`,
          ) === "1",
          "One final PDF/no orphan",
        );
      } else throw new Error("Unknown checkpoint");
      console.log(`Checked ${path.slice(12)}`);
      res.setHeader("content-type", "application/json");
      res.end(JSON.stringify(data));
      return;
    }
    const file = resolve(
      root,
      "." + decodeURIComponent(path === "/" ? "/index.html" : path),
    );
    if (!file.startsWith(root + sep)) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.setHeader(
      "content-type",
      types[extname(file)] ?? "application/octet-stream",
    );
    res.end(readFileSync(file));
  } catch (error) {
    if (req.url.startsWith("/checkpoint/") || req.url === "/fixture") {
      checkpointError = error;
    }
    res.writeHead(500);
    res.end("Local harness failed");
  }
});
try {
  verify(
    !readFileSync(join(root, "main.dart.js"), "utf8").includes(
      f.local.SERVICE_ROLE_KEY,
    ),
    "No service_role key in Web build",
  );
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const launched = await launchChrome(profile, ["about:blank"]);
  chrome = launched.child;
  const port = launched.port;
  const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`))
    .json();
  socket = await connectCdp(
    pages.find((p) => p.type === "page").webSocketDebuggerUrl,
  );
  await socket("Page.enable");
  await socket("Page.setInterceptFileChooserDialog", { enabled: true });
  await navigateDocument(socket, "Page.navigate", {
    url: `http://127.0.0.1:${server.address().port}`,
  });
  async function result() {
    return await evaluate(
      socket,
      "document.documentElement.getAttribute('data-7d-result') || ''",
    );
  }
  let outcome;
  await until(
    async () => {
      if (checkpointError) throw checkpointError;
      outcome = await result();
      return outcome.startsWith("PASS") || outcome.startsWith("FAIL");
    },
    "Flutter complete UI E2E",
    240_000,
  );
  verify(outcome.startsWith("PASS"), outcome);
  console.log(
    `${outcome}; ${assertions} host assertions; PostgreSQL/Storage/Auth/Edge verified`,
  );
} catch (error) {
  console.error(error.message);
  throw error;
} finally {
  socket?.close();
  await stopChrome(chrome);
  server.close();
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
