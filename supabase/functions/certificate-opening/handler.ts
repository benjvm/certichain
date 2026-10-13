import { cors } from "../_shared/http.ts";
import { BodyError, boundedBody } from "../_shared/bounded_body.ts";
import { object, strictJson } from "../_shared/strict_json.ts";
import { VerificationBackend } from "../_shared/verification_backend.ts";
import { UUID } from "../verify-certificate/contract.ts";
import { openingProjection } from "../verify-certificate-v2/contract.ts";
interface Config {
  url: string;
  anonKey: string;
  serviceKey: string;
  environment: string;
}
export function handler(config: Config) {
  return async (request: Request): Promise<Response> => {
    const reply = (body: unknown, status: number) =>
      Response.json(body, { status, headers: cors });
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return reply({ error: "method_not_allowed" }, 405);
    }
    const deadline = Date.now() + 12000;
    const backend = new VerificationBackend(
      config.url,
      config.serviceKey,
      deadline,
    );
    try {
      const auth = request.headers.get("authorization");
      if (!auth || auth.length > 8192 || !/^Bearer \S+$/i.test(auth)) {
        return reply({ error: "unauthenticated" }, 401);
      }
      const response = await fetch(`${config.url}/auth/v1/user`, {
        headers: { apikey: config.anonKey, Authorization: auth },
        signal: AbortSignal.timeout(backend.remaining()),
      });
      if (response.status >= 500 || response.status === 429) throw new Error();
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        return reply({ error: "unauthenticated" }, 401);
      }
      let user: Record<string, unknown>;
      try {
        user = strictJson(new TextDecoder("utf-8", { fatal: true }).decode(
          await boundedBody(response.body, 16384, backend.remaining()),
        )) as Record<string, unknown>;
      } catch {
        throw new Error("Auth unavailable");
      }
      if (
        !user || typeof user.id !== "string" || user.id.length !== 36 ||
        !UUID.test(user.id) || user.is_anonymous !== false
      ) return reply({ error: "unauthenticated" }, 401);
      let id: string;
      try {
        if (
          !/^application\/json(?:\s*;\s*charset=utf-8)?\s*$/i.test(
            request.headers.get("content-type") ?? "",
          )
        ) throw new Error();
        const input = object(
          strictJson(
            new TextDecoder("utf-8", { fatal: true }).decode(
              await boundedBody(request.body, 2048, backend.remaining()),
            ),
          ),
          ["certificate_id"],
        );
        if (
          typeof input.certificate_id !== "string" ||
          input.certificate_id.length !== 36 || !UUID.test(input.certificate_id)
        ) throw new Error();
        id = input.certificate_id.toLowerCase();
      } catch (e) {
        if (e instanceof BodyError) throw e;
        return reply({ error: "invalid_input" }, 400);
      }
      const opening = await backend.rpc("authorize_certificate_opening", {
        p_certificate: id,
        p_actor: user.id,
        p_environment: config.environment,
      });
      if (opening === null) return reply({ error: "opening_unavailable" }, 404);
      if (!openingProjection(opening)) throw new Error();
      return reply(opening, 200);
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
