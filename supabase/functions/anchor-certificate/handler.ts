import { authenticatedActor } from "../issue-certificate/backend.ts";
import { IssuanceError } from "../issue-certificate/contract.ts";
import { validatePdf } from "../issue-certificate/pdf.ts";
import { cors } from "../_shared/http.ts";
import {
  commitment,
  digest,
  hex,
  uuidPattern,
} from "../_shared/blockchain/application/commitment.ts";
import {
  type Hex,
  RegistryError,
} from "../_shared/blockchain/domain/registry.ts";
import { BlockchainBackend } from "../_shared/blockchain/data/backend.ts";
import { boundedBody } from "../_shared/bounded_body.ts";
export interface Config {
  url: string;
  anonKey: string;
  serviceKey: string;
  environment: string;
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
      let input: Record<string, string>;
      try {
        if (
          !/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(
            request.headers.get("content-type") ?? "",
          )
        ) throw new Error();
        const source = new TextDecoder("utf-8", { fatal: true }).decode(
          await boundedBody(request.body, 2048),
        );
        input = JSON.parse(source);
        const keys = action === "request"
          ? ["certificate_id", "idempotency_key"]
          : ["operation_id"];
        // Each flat string pair is scanned as JSON tokens, including escaped
        // keys. No duplicate key may be hidden by JSON.parse's last-key rule.
        const pairs =
          source.match(/"(?:[^"\\]|\\.)*"\s*:\s*"(?:[^"\\]|\\.)*"/g) ?? [];
        if (pairs.length !== keys.length) throw new Error();
        if (
          !input || typeof input !== "object" || Array.isArray(input) ||
          Object.keys(input).length !== keys.length || keys.some((k) =>
            typeof input[k] !== "string" || !uuidPattern.test(input[k])
          )
        ) {
          throw new Error();
        }
        for (const key of keys) {
          input[key] = input[key].toLowerCase();
        }
      } catch {
        return reply({ error: "invalid_input" }, 400);
      }
      const backend = new BlockchainBackend(config.url, config.serviceKey);
      if (action !== "request") {
        const dto = await backend.rpc<{ operation_id: string; status: string }>(
          action === "progress"
            ? "blockchain_progress"
            : "blockchain_reauthorize",
          { p_actor: actor, p_operation: input.operation_id },
        );
        return reply(
          { operation_id: dto.operation_id, status: dto.status },
          200,
        );
      }
      const args = {
        p_actor: actor,
        p_certificate: input.certificate_id,
        p_environment: config.environment,
      };
      const snapshot = await backend.rpc<
        { code: string; I: Hex; hash: string; path: string }
      >("blockchain_anchor_snapshot", args);
      try {
        const pdf = await backend.pdf(snapshot.path);
        if (await digest(pdf) !== `0x${snapshot.hash}`) throw new Error();
        await validatePdf(pdf);
      } catch {
        return reply({ error: "publication_unavailable" }, 404);
      }
      const S = hex(crypto.getRandomValues(new Uint8Array(32)));
      const { K, C } = await commitment(
        snapshot.code,
        snapshot.I,
        `0x${snapshot.hash}`,
        S,
      );
      const dto = await backend.rpc<
        { operation_id: string; status: string; created: boolean }
      >("blockchain_request_anchor", {
        ...args,
        p_key: input.idempotency_key,
        p_snapshot: snapshot,
        p_salt: S,
        p_k: K,
        p_c: C,
      });
      return reply(
        { operation_id: dto.operation_id, status: dto.status },
        dto.created ? 202 : 200,
      );
    } catch (e) {
      const code = e instanceof RegistryError
        ? e.code
        : e instanceof IssuanceError && e.code === "unauthenticated"
        ? "unauthenticated"
        : "rpc_unavailable";
      const error = code === "key_conflict"
        ? "publication_unavailable"
        : code === "duplicate_key"
        ? "idempotency_conflict"
        : ["unauthenticated", "authorization_denied", "busy"].includes(code)
        ? code
        : "temporary_failure";
      const status = error === "unauthenticated"
        ? 401
        : error === "authorization_denied"
        ? 403
        : error === "publication_unavailable"
        ? 404
        : ["idempotency_conflict", "busy"].includes(error)
        ? 409
        : 503;
      return reply({ error }, status);
    }
  };
}
