import { cors } from "../_shared/http.ts";
import { BodyError, boundedBody } from "../_shared/bounded_body.ts";
import { object, strictJson } from "../_shared/strict_json.ts";
import { VerificationBackend } from "../_shared/verification_backend.ts";
import { credentialCode } from "../verify-certificate/contract.ts";
import { snapshot } from "./contract.ts";
import { observe } from "./observation.ts";
import {
  observeRevocation,
  revocationSnapshot,
} from "../verify-certificate-v3/observation.ts";
export interface Config {
  url: string;
  serviceKey: string;
  environment: string;
  rpcUrl?: string;
}
export function handler(config: Config, version: "2" | "3" = "2") {
  return async (request: Request): Promise<Response> => {
    const started = performance.now();
    const deadline = Date.now() + 12000;
    const reply = (body: unknown, status: number, headers = {}) =>
      Response.json(body, {
        status,
        headers: {
          ...cors,
          ...headers,
          "Server-Timing": `total;dur=${
            (performance.now() - started).toFixed(1)
          }`,
        },
      });
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return reply({ error: "method_not_allowed" }, 405, {
        Allow: "POST, OPTIONS",
      });
    }
    const backend = new VerificationBackend(
      config.url,
      config.serviceKey,
      deadline,
    );
    try {
      const budget = object(
        await backend.rpc("consume_public_verification_budget", {}),
        ["allowed", "retry_after"],
      );
      if (
        typeof budget.allowed !== "boolean" ||
        !Number.isInteger(budget.retry_after) ||
        (budget.retry_after as number) < 0 ||
        (budget.retry_after as number) > 60 ||
        (!budget.allowed && (budget.retry_after as number) < 1)
      ) throw new Error();
      if (!budget.allowed) {
        return reply({ error: "rate_limited" }, 429, {
          "Retry-After": String(budget.retry_after),
        });
      }
      if (
        !/^application\/json(?:\s*;\s*charset=utf-8)?\s*$/i.test(
          request.headers.get("content-type") ?? "",
        )
      ) return reply({ error: "invalid_input" }, 400);
      let code: string | null;
      try {
        code = credentialCode(
          strictJson(
            new TextDecoder("utf-8", { fatal: true }).decode(
              await boundedBody(request.body, 2048, backend.remaining()),
            ),
          ),
        );
      } catch (e) {
        if (e instanceof BodyError) throw e;
        return reply({ error: "invalid_input" }, 400);
      }
      if (!code) return reply({ error: "invalid_input" }, 400);
      const raw = await backend.rpc(
        version === "3"
          ? "lookup_public_certificate_v3"
          : "lookup_public_certificate_v2",
        {
          p_credential_code: code,
          p_environment: config.environment,
        },
      );
      const v = version === "3"
        ? object(raw, ["registry", "anchor", "revocation"])
        : null;
      const s = await snapshot(
        v ? { registry: v.registry, anchor: v.anchor } : raw,
        code,
        config.environment,
      );
      const blockchain = s.registry.result === "not_found"
        ? null
        : await observe(s, config.rpcUrl, deadline);
      const revocation = v
        ? await observeRevocation(
          s,
          revocationSnapshot(v.revocation, s),
          config.rpcUrl,
          deadline,
        )
        : null;
      return reply(
        {
          schema_version: version,
          registry: s.registry,
          blockchain,
          ...(v ? { revocation } : {}),
        },
        200,
      );
    } catch (e) {
      const status = e instanceof BodyError ? e.status : 503;
      return reply({
        error: status === 413
          ? "payload_too_large"
          : status === 400
          ? "invalid_input"
          : "temporary_failure",
      }, status);
    }
  };
}
