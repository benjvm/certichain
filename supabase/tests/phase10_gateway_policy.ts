// Test-harness policy only. Never retain upstream bodies or arbitrary headers.
import { strictJson } from "../functions/_shared/strict_json.ts";
import { boundedBody } from "../functions/_shared/bounded_body.ts";
import { normalizeReason } from "../functions/revoke-certificate/handler.ts";
import { publicTimestamp } from "../functions/verify-certificate/contract.ts";
import { uuidPattern } from "../functions/_shared/blockchain/application/commitment.ts";

export const privateRoutes = [
  "revoke-certificate",
  "revocation-progress",
  "reauthorize-revocation",
] as const;
const gatewayMessages: Record<string, string> = {
  UNAUTHORIZED_NO_AUTH_HEADER: "Missing authorization header",
  UNAUTHORIZED_INVALID_JWT_FORMAT: "Invalid JWT format",
  UNAUTHORIZED_ASYMMETRIC_JWT: "Invalid JWT",
  UNAUTHORIZED_LEGACY_JWT: "Invalid JWT",
};
const gatewayScenarios: Record<string, string[]> = {
  no_token: ["UNAUTHORIZED_NO_AUTH_HEADER"],
  invalid_token: ["UNAUTHORIZED_INVALID_JWT_FORMAT"],
  expired_token: ["UNAUTHORIZED_ASYMMETRIC_JWT", "UNAUTHORIZED_LEGACY_JWT"],
};
const handlerScenarios: Record<string, [number, string | null]> = {
  valid_session_invalid_input: [400, "invalid_input"],
  anonymous_api_jwt: [401, "unauthenticated"],
  valid_owner_authorized: [200, null],
  valid_foreign_denied: [404, "revocation_unavailable"],
};
function closed(value: unknown, keys: string[]) {
  return value !== null && typeof value === "object" &&
    !Array.isArray(value) &&
    Object.keys(value).sort().join() === keys.sort().join();
}

export async function gatewayObservation(
  endpoint: string,
  scenario: string,
  response: Response,
  certificate?: string,
) {
  // Bound and decode before inspecting; network/size/UTF-8/JSON failures fail
  // the probe, never qualify for the external infrastructure exception.
  const bytes = await boundedBody(response.body, 8192);
  let data: Record<string, unknown> = {};
  let parsed = false;
  try {
    if (
      !/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(
        response.headers.get("content-type") ?? "",
      )
    ) throw new Error();
    const value = strictJson(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error();
    }
    data = value as Record<string, unknown>;
    parsed = true;
  } catch { /* Report only the failed check, never the private input. */ }
  const gatewayCode = response.headers.get("sb-error-code");
  const cache = response.headers.get("cache-control");
  const gateway = Object.hasOwn(gatewayScenarios, scenario);
  const expected = gateway ? 401 : handlerScenarios[scenario]?.[0];
  const knownRoute = (privateRoutes as readonly string[]).includes(endpoint);
  const generic = parsed && gatewayCode !== null &&
    gatewayScenarios[scenario]?.includes(gatewayCode) === true &&
    data.code === gatewayCode &&
    closed(
      data,
      Object.hasOwn(data, "msg")
        ? ["code", "message", "msg"]
        : ["code", "message"],
    ) &&
    data.message === gatewayMessages[gatewayCode] &&
    (!Object.hasOwn(data, "msg") || data.msg === data.message);
  // The fixture is active in the isolated probe and revoked by full acceptance.
  // Inspect its private DTO in memory; retain none of its values in the report.
  const uuid = (value: unknown) =>
    typeof value === "string" && value.length === 36 && uuidPattern.test(value);
  let canonicalReason = data.reason === null;
  try {
    canonicalReason ||= normalizeReason(data.reason) === data.reason;
  } catch { /* invalid */ }
  const ownerDTO = certificate !== undefined && closed(data, [
    "certificate_id",
    "request_id",
    "status",
    "revoked_at",
    "reason",
    "synchronization",
  ]) && data.certificate_id === certificate &&
    (data.request_id === null || uuid(data.request_id)) &&
    canonicalReason && (data.reason === null) === (data.request_id === null) &&
    ["active", "revoked"].includes(data.status as string) &&
    (data.status === "active"
      ? data.revoked_at === null && data.request_id === null
      : publicTimestamp(data.revoked_at)) &&
    Array.isArray(data.synchronization) && data.synchronization.length === 0;
  const handlerBody = parsed && gatewayCode === null &&
    (scenario === "valid_owner_authorized"
      ? ownerDTO
      : closed(data, ["error"]) &&
        data.error === handlerScenarios[scenario]?.[1]);
  const privacy = gateway ? generic : handlerBody;
  const authentication = knownRoute && response.status === expected && privacy;
  const exception = gateway && authentication && cache === null;
  const applicationCache = gateway ? null : cache === "no-store";
  return {
    endpoint: knownRoute ? endpoint : "unexpected",
    scenario: gateway || Object.hasOwn(handlerScenarios, scenario)
      ? scenario
      : "unexpected",
    status: response.status,
    expected_status: expected ?? null,
    component: gateway ? "supabase-pre-handler" : "certichain-handler",
    cache_control: cache === null || cache === "no-store"
      ? cache
      : "unexpected",
    sb_error_code: gatewayCode === null
      ? null
      : Object.hasOwn(gatewayMessages, gatewayCode)
      ? gatewayCode
      : "unexpected",
    authentication_result: authentication ? "PASS" : "FAIL",
    privacy_result: privacy ? "PASS" : "FAIL",
    application_no_store_result: applicationCache === null
      ? "NOT_APPLICABLE"
      : applicationCache
      ? "PASS"
      : "FAIL",
    strict_no_store_result: cache === "no-store" ? "PASS" : "FAIL",
    external_exception_applied: exception,
    result: authentication && (cache === "no-store" || exception)
      ? "PASS"
      : "FAIL",
  };
}

export function gatewayPolicy(
  observations: Awaited<ReturnType<typeof gatewayObservation>>[],
) {
  const expected = privateRoutes.flatMap((route) =>
    [
      ...Object.keys(gatewayScenarios),
      "valid_session_invalid_input",
      "anonymous_api_jwt",
    ].map((scenario) => `${route}/${scenario}`)
  ).concat([
    "revocation-progress/valid_owner_authorized",
    "revocation-progress/valid_foreign_denied",
  ]).sort();
  const complete =
    observations.map((r) => `${r.endpoint}/${r.scenario}`).sort().join() ===
      expected.join();
  const all = (
    key:
      | "result"
      | "authentication_result"
      | "privacy_result"
      | "strict_no_store_result",
  ) => complete && observations.every((r) => r[key] === "PASS");
  return {
    result: all("result") ? "PASS" : "FAIL",
    authentication_result: all("authentication_result") ? "PASS" : "FAIL",
    privacy_result: all("privacy_result") ? "PASS" : "FAIL",
    application_no_store_result: complete &&
        observations.filter((r) => r.component === "certichain-handler").every((
          r,
        ) => r.application_no_store_result === "PASS")
      ? "PASS"
      : "FAIL",
    // Strict historical diagnostic remains FAIL when the header is absent.
    cache_control_result: all("strict_no_store_result") ? "PASS" : "FAIL",
    external_exception_count:
      observations.filter((r) => r.external_exception_applied).length,
    policy: "10B-2026-10-18-generic-supabase-jwt-only",
    verify_jwt: true,
    observations,
  };
}
