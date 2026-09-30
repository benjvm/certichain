import { IssuanceError, MAX_PDF, readLimited } from "./contract.ts";

export class Backend {
  constructor(private url: string, private key: string) {}
  private async request(
    path: string,
    init: RequestInit = {},
  ): Promise<Response> {
    try {
      return await fetch(`${this.url}${path}`, {
        ...init,
        headers: {
          apikey: this.key,
          Authorization: `Bearer ${this.key}`,
          ...init.headers,
        },
        signal: AbortSignal.timeout(15_000),
      });
    } catch {
      throw new IssuanceError("temporary_failure", 503);
    }
  }
  async rpc(
    name: string,
    args: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const response = await this.request(`/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      if (error.code === "42501") throw new IssuanceError("forbidden", 403);
      if (error.code === "23505") {
        throw new IssuanceError("idempotency_conflict", 409);
      }
      if (error.code === "22023") throw new IssuanceError("invalid_input", 422);
      if (["PT409", "40001", "40P01"].includes(error.code)) {
        throw new IssuanceError("operation_in_progress", 409);
      }
      throw new IssuanceError("temporary_failure", 503);
    }
    return response.json();
  }
  async upload(path: string, bytes: Uint8Array): Promise<void> {
    const response = await this.request(
      `/storage/v1/object/certificates/${path}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/pdf", "x-upsert": "false" },
        body: bytes,
      },
    );
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      if (
        response.status === 409 || error.statusCode === "409" ||
        error.error === "Duplicate"
      ) return;
      throw new IssuanceError("temporary_failure", 503);
    }
  }
  async download(path: string): Promise<Uint8Array> {
    const response = await this.request(
      `/storage/v1/object/authenticated/certificates/${path}`,
    );
    if (!response.ok) throw new IssuanceError("temporary_failure", 503);
    if (
      response.headers.get("content-type")?.split(";")[0] !== "application/pdf"
    ) throw new IssuanceError("stored_object_invalid", 503);
    try {
      return await readLimited(response.body, MAX_PDF);
    } catch {
      throw new IssuanceError("stored_object_invalid", 503);
    }
  }
}

// This client has only the caller's token and public key, never service_role.
export async function authenticatedActor(
  request: Request,
  url: string,
  publicKey: string,
): Promise<string> {
  const authorization = request.headers.get("authorization");
  if (!authorization || !/^Bearer \S+$/i.test(authorization)) {
    throw new IssuanceError("unauthenticated", 401);
  }
  let response: Response;
  try {
    response = await fetch(`${url}/auth/v1/user`, {
      headers: { apikey: publicKey, Authorization: authorization },
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw new IssuanceError("temporary_failure", 503);
  }
  if (response.status >= 500 || response.status === 429) {
    throw new IssuanceError("temporary_failure", 503);
  }
  if (!response.ok) throw new IssuanceError("unauthenticated", 401);
  const user = await response.json();
  if (!user.id || user.is_anonymous) {
    throw new IssuanceError("unauthenticated", 401);
  }
  return user.id;
}
