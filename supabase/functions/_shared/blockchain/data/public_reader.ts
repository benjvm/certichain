import { EvmRegistry } from "./evm_registry.ts";
import { boundedBody } from "../../bounded_body.ts";
import { fixedHex, object, strictJson } from "../../strict_json.ts";
import { RegistryError } from "../domain/registry.ts";

const methods = new Set([
  "eth_chainId",
  "eth_getBlockByNumber",
  "eth_getCode",
  "eth_call",
  "eth_getTransactionReceipt",
  "eth_getTransactionByHash",
  "eth_getLogs",
]);
const quantity = (v: unknown) =>
  typeof v === "string" && v.length <= 66 &&
  /^0x(?:0|[1-9a-f][0-9a-f]*)$/.test(v);
const data = (v: unknown) =>
  typeof v === "string" && v.length <= 32770 && /^0x(?:[0-9a-f]{2})*$/.test(v);
function validate(method: string, result: unknown, params: unknown[]) {
  if (
    result === null &&
    [
      "eth_getBlockByNumber",
      "eth_getTransactionReceipt",
      "eth_getTransactionByHash",
    ].includes(method)
  ) return;
  if (method === "eth_chainId") {
    if (!quantity(result)) throw new Error();
    return;
  }
  if (["eth_call", "eth_getCode"].includes(method)) {
    if (!data(result)) throw new Error();
    return;
  }
  function fields(
    value: unknown,
    quantities: string[],
    hashes: string[],
    addresses: string[],
    blobs: string[] = [],
  ) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error();
    }
    const v = value as Record<string, unknown>;
    if (
      quantities.some((k) => !quantity(v[k])) ||
      hashes.some((k) => !fixedHex(v[k])) ||
      addresses.some((k) => !fixedHex(v[k], 20)) ||
      blobs.some((k) => !data(v[k]))
    ) throw new Error();
    return v;
  }
  function logs(value: unknown) {
    if (!Array.isArray(value) || value.length > 64) throw new Error();
    for (const log of value) {
      const v = fields(
        log,
        ["logIndex", "blockNumber", "transactionIndex"],
        ["transactionHash", "blockHash"],
        ["address"],
        ["data"],
      );
      if (
        !Array.isArray(v.topics) || v.topics.length > 4 || v.topics.some((x) =>
          !fixedHex(x)
        ) || typeof v.removed !== "boolean"
      ) throw new Error();
      if (v.removed) throw new RegistryError("reorg");
    }
  }
  if (method === "eth_getLogs") {
    logs(result);
    return;
  }
  if (method === "eth_getBlockByNumber") {
    const block = fields(result, ["number", "timestamp"], ["hash"], []);
    if (
      BigInt(block.number as string) > 9223372036854775807n ||
      BigInt(block.timestamp as string) > 253402300799n ||
      (quantity(params[0]) &&
        BigInt(params[0] as string) !== BigInt(block.number as string))
    ) throw new Error();
    return;
  }
  if (method === "eth_getTransactionByHash") {
    fields(result, ["nonce", "chainId", "value", "type"], ["hash"], [
      "from",
      "to",
    ], ["input"]);
    return;
  }
  const v = fields(
    result,
    ["status", "blockNumber", "transactionIndex", "gasUsed"],
    ["transactionHash", "blockHash"],
    ["from", "to"],
  );
  logs(v.logs);
}

// Uses the existing signer-free EvmRegistry. Public queries cannot call even
// a write-oriented RPC through this adapter; no privateKey is accepted.
export class PublicEvmReader extends EvmRegistry {
  override async rpc<T>(method: string, params: unknown[] = []): Promise<T> {
    if (!methods.has(method)) throw new RegistryError("authorization_denied");
    const remaining = () => {
      const ms = this.deadline - Date.now();
      if (ms <= 0) throw new RegistryError("rpc_timeout");
      return Math.min(10000, ms);
    };
    try {
      const response = await fetch(this.readUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(remaining()),
      });
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        throw new Error();
      }
      const envelope = strictJson(
        new TextDecoder("utf-8", { fatal: true }).decode(
          await boundedBody(response.body, 65536, remaining()),
        ),
      );
      const r = object(envelope, ["jsonrpc", "id", "result"]);
      if (r.jsonrpc !== "2.0" || r.id !== 1) throw new Error();
      validate(method, r.result, params);
      return r.result as T;
    } catch (e) {
      if (e instanceof RegistryError) throw e;
      throw new RegistryError("rpc_unavailable");
    }
  }
  constructor(
    private readUrl: string,
    deployment: ConstructorParameters<typeof EvmRegistry>[1],
  ) {
    super(readUrl, deployment);
  }
}
