import { cors } from "./http.ts";
import { BodyError, boundedBody } from "./bounded_body.ts";
import {
  credentialCode,
  publicProjection,
} from "../verify-certificate/contract.ts";

interface Config {
  url: string;
  serviceKey: string;
}

export function publicHandler(config: Config, compare = false) {
  return async (request: Request): Promise<Response> => {
    const respond = (body: unknown, status: number, extra = {}) =>
      Response.json(body, { status, headers: { ...cors, ...extra } });
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return respond({ error: "method_not_allowed" }, 405, {
        Allow: "POST, OPTIONS",
      });
    }
    const rpc = async (name: string, args: Record<string, unknown>) => {
      const response = await fetch(`${config.url}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
          apikey: config.serviceKey,
          Authorization: `Bearer ${config.serviceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        throw new Error("Backend unavailable");
      }
      try {
        const bytes = await boundedBody(response.body, 8192);
        return JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
      } catch {
        throw new Error("Backend unavailable");
      }
    };
    try {
      // Every POST consumes a committed budget before input validation/lookup.
      const budget = await rpc("consume_public_verification_budget", {});
      if (
        typeof budget?.allowed !== "boolean" ||
        !Number.isInteger(budget.retry_after) || budget.retry_after < 0 ||
        budget.retry_after > 60 || (!budget.allowed && budget.retry_after < 1)
      ) {
        throw new Error("Invalid budget");
      }
      if (!budget.allowed) {
        return respond({ error: "rate_limited" }, 429, {
          "Retry-After": String(budget.retry_after),
        });
      }
      const contentType = request.headers.get("content-type") ?? "";
      if (
        !/^application\/json(?:\s*;\s*charset=utf-8)?\s*$/i.test(contentType)
      ) {
        return respond({ error: "invalid_input" }, 400);
      }
      const bytes = await boundedBody(request.body, 2048);
      let input: unknown;
      try {
        input = JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
      } catch {
        return respond({ error: "invalid_input" }, 400);
      }
      const value = input as Record<string, unknown> | null;
      const code = compare
        ? credentialCode({ credential_code: value?.credential_code })
        : credentialCode(input);
      if (
        compare &&
        (!value || Array.isArray(value) ||
          Object.keys(value).sort().join(",") !==
            "credential_code,document_sha256" ||
          typeof value.document_sha256 !== "string" ||
          value.document_sha256.length !== 64 ||
          !/^[0-9a-f]{64}$/.test(value.document_sha256))
      ) return respond({ error: "invalid_input" }, 400);
      if (!code) return respond({ error: "invalid_input" }, 400);
      const result = await rpc(
        compare
          ? "compare_public_certificate_hash"
          : "lookup_public_certificate",
        {
          p_credential_code: code,
          ...(compare ? { p_document_sha256: value!.document_sha256 } : {}),
        },
      );
      const projection = compare ? result?.verification : result;
      if (
        !publicProjection(projection, code) ||
        (compare &&
          (result?.schema_version !== "1" ||
            Object.keys(result).sort().join(",") !==
              "file_integrity,schema_version,verification" ||
            !(projection.result === "not_found"
              ? result.file_integrity === "unavailable"
              : ["match", "integrity_mismatch"].includes(
                result.file_integrity,
              ))))
      ) {
        throw new Error("Invalid projection");
      }
      return respond(result, 200);
    } catch (error) {
      const status = error instanceof BodyError ? error.status : 503;
      return respond({
        error: status === 413
          ? "payload_too_large"
          : status === 400
          ? "invalid_input"
          : "temporary_failure",
      }, status);
    }
  };
}
