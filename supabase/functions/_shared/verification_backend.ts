import { boundedBody } from "./bounded_body.ts";
import { strictJson } from "./strict_json.ts";
export class VerificationBackend {
  constructor(
    private url: string,
    private key: string,
    readonly deadline: number,
  ) {}
  remaining() {
    const ms = this.deadline - Date.now();
    if (ms <= 0) throw new Error("Deadline");
    return ms;
  }
  async rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
    const response = await fetch(`${this.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: this.key,
        Authorization: `Bearer ${this.key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(this.remaining()),
    });
    if (!response.ok) {
      void response.body?.cancel().catch(() => {});
      throw new Error("Backend unavailable");
    }
    try {
      return strictJson(new TextDecoder("utf-8", { fatal: true }).decode(
        await boundedBody(response.body, 16384, this.remaining()),
      ));
    } catch {
      throw new Error("Backend unavailable");
    }
  }
}
