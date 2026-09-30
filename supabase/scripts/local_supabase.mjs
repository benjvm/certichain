import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

// Shared local-only operator/test infrastructure. No remote URL is accepted.
// setup-cli installs a binary in CI; development may use the npm CLI.
export function cliCommand(args) {
  const binary = process.env.SUPABASE_CLI ?? "supabase";
  const probe = spawnSync(binary, ["--version"], { encoding: "utf8" });
  if (probe.status === 0) return [binary, args];
  const require = createRequire(import.meta.url);
  const folder = dirname(require.resolve("supabase/package.json"));
  return [process.execPath, [join(folder, "dist", "supabase.js"), ...args]];
}
export function cli(args, options = {}) {
  const [command, parameters] = cliCommand(args);
  return spawnSync(command, parameters, {
    encoding: "utf8",
    timeout: 30_000,
    ...options,
  });
}
export function localStatus() {
  const result = cli(["status", "-o", "json"]);
  if (result.status !== 0) throw new Error("Local Supabase status unavailable");
  const local = JSON.parse(result.stdout);
  if (!/^http:\/\/(127\.0\.0\.1|localhost):54321$/.test(local.API_URL)) {
    throw new Error("Requires the CertiChain local API");
  }
  return local;
}
export async function api(
  local,
  path,
  token,
  method = "GET",
  body,
  headers = {},
) {
  const result = await fetch(`${local.API_URL}${path}`, {
    method,
    body,
    headers: {
      apikey: local.ANON_KEY,
      Authorization: `Bearer ${token}`,
      ...headers,
    },
    signal: AbortSignal.timeout(30_000),
  });
  return result;
}
export function sql(statement, user = "postgres") {
  const r = spawnSync("docker", [
    "exec",
    "-i",
    "supabase_db_certichain",
    "psql",
    "-X",
    "-q",
    "-A",
    "-t",
    "-U",
    user,
    "-d",
    "postgres",
    "-v",
    "ON_ERROR_STOP=1",
  ], { input: statement, encoding: "utf8", timeout: 30_000 });
  if (r.status !== 0) throw new Error(`Local fixture SQL failed: ${r.stderr}`);
  return r.stdout.trim();
}
