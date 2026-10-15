import { authenticatedActor } from "../issue-certificate/backend.ts";
import { IssuanceError } from "../issue-certificate/contract.ts";
import { BlockchainBackend } from "../_shared/blockchain/data/backend.ts";
import { RegistryError } from "../_shared/blockchain/domain/registry.ts";
import { BodyError, boundedBody } from "../_shared/bounded_body.ts";
import { cors } from "../_shared/http.ts";
import { object, strictJson } from "../_shared/strict_json.ts";
import { uuidPattern } from "../_shared/blockchain/application/commitment.ts";

export function normalizeReason(value: unknown): string {
  if (typeof value !== "string") throw new Error();
  const reason = value.normalize("NFC").replace(/\r\n?/g, "\n").replace(
    /^[ \t\n]+|[ \t\n]+$/g,
    "",
  );
  if (
    [...reason].length < 1 || [...reason].length > 500 ||
    [...reason].some((c) => {
      const n = c.codePointAt(0)!;
      return n < 32 && ![9, 10].includes(n) || n === 127 ||
        n >= 0xd800 && n <= 0xdfff;
    })
  ) throw new Error();
  return reason;
}
export interface Config {
  url: string;
  anonKey: string;
  serviceKey: string;
}
export function handler(
  config: Config,
  action: "request" | "progress" | "reauthorize" = "request",
) {
  return async (request: Request): Promise<Response> => {
    const reply = (body: unknown, status: number) =>
      Response.json(body, { status, headers: cors });
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return reply({ error: "method_not_allowed" }, 405);
    }
    try {
      const actor = await authenticatedActor(
        request,
        config.url,
        config.anonKey,
      );
      let input: Record<string, unknown>;
      try {
        if (
          !/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(
            request.headers.get("content-type") ?? "",
          )
        ) throw new Error();
        input = object(
          strictJson(
            new TextDecoder("utf-8", { fatal: true }).decode(
              await boundedBody(request.body, 8192),
            ),
          ),
          action === "request"
            ? ["certificate_id", "idempotency_key", "reason"]
            : action === "progress"
            ? ["certificate_id"]
            : ["operation_id"],
        );
        for (const key of Object.keys(input).filter((k) => k !== "reason")) {
          if (
            typeof input[key] !== "string" ||
            !uuidPattern.test(input[key] as string)
          ) throw new Error();
          input[key] = (input[key] as string).toLowerCase();
        }
        if (action === "request") input.reason = normalizeReason(input.reason);
      } catch (e) {
        return reply({
          error: e instanceof BodyError && e.status === 413
            ? "payload_too_large"
            : "invalid_input",
        }, e instanceof BodyError && e.status === 413 ? 413 : 400);
      }
      const backend = new BlockchainBackend(config.url, config.serviceKey);
      const dto = action === "reauthorize"
        ? await backend.rpc("reauthorize_certificate_revocation", {
          p_actor: actor,
          p_operation: input.operation_id,
        })
        : await backend.rpc<Record<string, unknown>>(
          action === "request"
            ? "request_certificate_revocation"
            : "certificate_revocation_progress",
          {
            p_actor: actor,
            p_certificate: input.certificate_id,
            ...(action === "request"
              ? { p_key: input.idempotency_key, p_reason: input.reason }
              : {}),
          },
        );
      const { created, ...result } = dto as Record<string, unknown>;
      return reply(result, created === true ? 202 : 200);
    } catch (e) {
      const code = e instanceof RegistryError
        ? e.code
        : e instanceof IssuanceError && e.code === "unauthenticated"
        ? "unauthenticated"
        : "rpc_unavailable";
      const [error, status] = code === "unauthenticated"
        ? ["unauthenticated", 401]
        : code === "key_conflict" || code === "authorization_denied"
        ? ["revocation_unavailable", 404]
        : code === "duplicate_key"
        ? ["idempotency_conflict", 409]
        : code === "busy"
        ? ["busy", 409]
        : ["temporary_failure", 503];
      return reply({ error }, status as number);
    }
  };
}
