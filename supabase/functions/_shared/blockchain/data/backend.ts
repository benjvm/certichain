import { RegistryError } from "../domain/registry.ts";
import { readLimited } from "../../../issue-certificate/contract.ts";
export class BlockchainBackend {
  deadline = Infinity;
  constructor(readonly url: string, private key: string) {}
  async rpc<T>(name: string, args: Record<string, unknown> = {}): Promise<T> {
    let response: Response;
    try {
      response = await fetch(`${this.url}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
          apikey: this.key,
          Authorization: `Bearer ${this.key}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(
          Math.max(1, Math.min(10000, this.deadline - Date.now())),
        ),
      });
    } catch {
      throw new RegistryError("rpc_unavailable");
    }
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      if (error.message === "nonce_conflict") {
        throw new RegistryError("nonce_conflict");
      }
      const code = error.code === "42501"
        ? "authorization_denied"
        : error.code === "PT404"
        ? "key_conflict"
        : error.code === "23505"
        ? "duplicate_key"
        : ["PT409", "40001", "40P01"].includes(error.code)
        ? "busy"
        : "rpc_unavailable";
      throw new RegistryError(code);
    }
    if (response.status === 204) return undefined as T;
    try {
      return await response.json();
    } catch {
      throw new RegistryError("rpc_unavailable");
    }
  }
  async pdf(path: string) {
    const response = await fetch(
      `${this.url}/storage/v1/object/authenticated/certificates/${path}`,
      {
        headers: { apikey: this.key, Authorization: `Bearer ${this.key}` },
        signal: AbortSignal.timeout(10000),
      },
    );
    if (
      !response.ok ||
      response.headers.get("content-type")?.split(";")[0] !== "application/pdf"
    ) throw new RegistryError("opening_unavailable");
    return readLimited(response.body, 8388608);
  }
}
