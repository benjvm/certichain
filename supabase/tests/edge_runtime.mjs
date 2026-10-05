import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import { api, cliCommand } from "../scripts/local_supabase.mjs";
import { terminate } from "./local_issuance_fixture.mjs";

// A previous Edge container can still answer while serve replaces it. Observe
// THIS process first. Never retain raw CLI logs (they can contain credentials).
export function watchRuntime(child) {
  let marker = false, failed = false, matched = 0;
  const phrase = "Serving functions on";
  child.on("error", () => {
    failed = true;
  });
  const inspect = (chunk) => {
    for (const letter of chunk.toString()) {
      matched = letter === phrase[matched]
        ? matched + 1
        : letter === phrase[0]
        ? 1
        : 0;
      if (matched === phrase.length) {
        marker = true;
        matched = 0;
      }
    }
  };
  child.stdout.on("data", inspect);
  child.stderr.on("data", inspect);
  return () => {
    if (failed || child.exitCode !== null || child.signalCode != null) {
      throw new Error("Edge readiness: current process failed/exited");
    }
    return marker;
  };
}

export function startRuntime(envFile) {
  const [command, args] = cliCommand([
    "functions",
    "serve",
    ...(envFile ? ["--env-file", envFile] : []),
  ]);
  const child = spawn(command, args, { windowsHide: true, stdio: "pipe" });
  const current = watchRuntime(child);
  return { child, current, close: () => terminate(child) };
}

export async function runtimeReady(runtime, local, timeout = 60000) {
  const started = Date.now(), deadline = started + timeout;
  const probe = async (stage, path, expected, method = "GET", body) => {
    let attempts = 0;
    while (Date.now() < deadline) {
      if (!runtime.current()) {
        await delay(100);
        continue;
      }
      attempts++;
      try {
        const response = stage === "edge-public-handler"
          ? await fetch(`${local.API_URL}${path}`, {
            method: "GET",
            headers: { Connection: "close" },
            credentials: "omit",
            signal: AbortSignal.timeout(1500),
          })
          : await api(local, path, local.ANON_KEY, method, body, {
            Connection: "close",
          }, 1500);
        await response.arrayBuffer();
        if (response.status === expected) {
          runtime.current();
          console.log(
            JSON.stringify({
              stage: `readiness-${stage}`,
              result: "PASS",
              attempts,
              elapsed_ms: Date.now() - started,
            }),
          );
          return;
        }
      } catch { /* GET or rejected JWT only; no fixture mutation retries. */ }
      await delay(100);
    }
    throw new Error(`Edge readiness deadline: ${stage}; attempts=${attempts}`);
  };
  await probe("auth", "/auth/v1/health", 200);
  await probe("postgrest", "/rest/v1/", 200);
  await probe("storage", "/storage/v1/status", 200);
  await probe("edge-jwt", "/functions/v1/certificate-pdf", 401, "POST", "{}");
  // Invoke the actual public module without consuming a POST budget or RPC.
  await probe("edge-public-handler", "/functions/v1/verify-certificate", 405);
}
