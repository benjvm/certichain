// Local disposable diagnostic, through Kong + the unmodified CLI main service.
// Revised acceptance and strict missing-header diagnostic are reported separately.
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fixture } from "./local_issuance_fixture.mjs";
import { assertDisposableStack } from "../scripts/local_supabase.mjs";
import { phase10GatewayCache } from "./phase10_backend.ts";

assertDisposableStack();
if (Deno.env.get("CERTICHAIN_TEST_CAMERA") !== "0") {
  throw new Error("Camera must remain disabled");
}
const report: Record<string, unknown> = {
  evaluated_at: new Date().toISOString(),
  environment: "local-disposable",
  hosted: "NOT_RUN",
  result: "FAIL",
  camera: "NOT_RUN",
  camera_reason:
    "Omitidas por instrucción del usuario; no hay cámara física disponible",
};
let f: Awaited<ReturnType<typeof fixture>> | undefined;
try {
  f = await fixture();
  Object.assign(
    report,
    { api_origin: f.local.API_URL },
    await phase10GatewayCache({ f }),
  );
} catch {
  report.failure = "Gateway probe failed; no upstream details retained";
} finally {
  f?.stopRuntime();
  const directory = resolve(
    Deno.env.get("CERTICHAIN_SOURCE_ROOT") ?? Deno.cwd(),
    "mobile/build/phase10-evidence",
  );
  mkdirSync(directory, { recursive: true });
  writeFileSync(
    resolve(directory, "gateway-probe.json"),
    JSON.stringify(report, null, 2),
  );
  console.log(JSON.stringify({
    suite: "phase10-gateway",
    result: report.result,
    authentication: report.authentication_result,
    strict_gateway_cache_control: report.cache_control_result,
    application_no_store: report.application_no_store_result,
    privacy: report.privacy_result,
    external_exception_count: report.external_exception_count,
    hosted: report.hosted,
    camera: report.camera,
  }));
}
Deno.exitCode = report.result === "PASS" ? 0 : 1;
