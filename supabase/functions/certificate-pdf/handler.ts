import { authenticatedActor, Backend } from "../issue-certificate/backend.ts";
import {
  IssuanceError,
  readLimited,
  sha256,
} from "../issue-certificate/contract.ts";
import { cors } from "../_shared/http.ts";

interface Config {
  url: string;
  anonKey: string;
  serviceKey: string;
}
export function handler(config: Config) {
  return async (request: Request): Promise<Response> => {
    const respond = (body: unknown, status: number) =>
      Response.json(body, {
        status,
        headers: cors,
      });
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return respond({ error: "method_not_allowed" }, 405);
    }
    try {
      const actor = await authenticatedActor(
        request,
        config.url,
        config.anonKey,
      );
      let input;
      try {
        const bytes = await readLimited(request.body, 1024);
        input = JSON.parse(new TextDecoder().decode(bytes));
      } catch {
        return respond({ error: "invalid_input" }, 400);
      }
      if (
        !input || typeof input !== "object" || Array.isArray(input) ||
        Object.keys(input).length !== 1 ||
        typeof input.certificate_id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          input.certificate_id ?? "",
        )
      ) {
        return respond({ error: "invalid_input" }, 400);
      }
      const backend = new Backend(config.url, config.serviceKey);
      const authorize = () =>
        backend.rpc("authorize_certificate_document", {
          p_certificate: input.certificate_id,
          p_actor: actor,
        });
      const document = await authorize();
      if (!document?.path) {
        return respond({ error: "document_unavailable" }, 404);
      }
      const path = String(document.path);
      // Object availability and exact immutable bytes, followed by fresh authorization.
      try {
        const bytes = await backend.download(path);
        if (await sha256(bytes) !== document.hash) {
          return respond({ error: "document_unavailable" }, 404);
        }
      } catch {
        return respond({ error: "document_unavailable" }, 404);
      }
      const fresh = await authorize();
      if (!fresh?.path || fresh.path !== path || fresh.hash !== document.hash) {
        return respond({ error: "document_unavailable" }, 404);
      }
      const signed = await fetch(
        `${config.url}/storage/v1/object/sign/certificates/${path}`,
        {
          method: "POST",
          headers: {
            apikey: config.serviceKey,
            Authorization: `Bearer ${config.serviceKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ expiresIn: 60 }),
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (!signed.ok) return respond({ error: "document_unavailable" }, 404);
      const data = await signed.json();
      if (
        typeof data.signedURL !== "string" ||
        !data.signedURL.startsWith(`/object/sign/certificates/${path}?`)
      ) {
        return respond({ error: "document_unavailable" }, 404);
      }
      // Relative signed URL resolves against the client's configured API origin,
      // never the internal Kong hostname. No standalone path/hash/credential fields.
      return respond({
        signed_url: `/storage/v1${data.signedURL}`,
        expires_in: 60,
      }, 200);
    } catch (error) {
      const status =
        error instanceof IssuanceError && error.code === "unauthenticated"
          ? 401
          : 503;
      return respond({
        error: status === 401 ? "unauthenticated" : "temporary_failure",
      }, status);
    }
  };
}
