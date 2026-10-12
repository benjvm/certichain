import { type Hex, RegistryError } from "../domain/registry.ts";
export const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function bytes(hex: string, length?: number): Uint8Array {
  if (
    !/^0x(?:[0-9a-f]{2})+$/.test(hex) ||
    (length !== undefined && hex.length !== 2 + length * 2)
  ) {
    throw new RegistryError("invalid_input");
  }
  return Uint8Array.from(hex.slice(2).match(/../g)!, (v) => parseInt(v, 16));
}
export function hex(value: Uint8Array): Hex {
  return `0x${
    Array.from(value, (v) => v.toString(16).padStart(2, "0")).join("")
  }`;
}
export async function digest(...parts: Uint8Array[]): Promise<Hex> {
  const joined = new Uint8Array(parts.reduce((n, v) => n + v.length, 0));
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", joined)));
}
export async function commitment(code: string, I: Hex, H: Hex, S: Hex) {
  if (!uuidPattern.test(code)) throw new RegistryError("invalid_input");
  const encode = new TextEncoder();
  const K = await digest(
    encode.encode("certichain:certificate-key:v1\0"),
    bytes(`0x${code.toLowerCase().replaceAll("-", "")}`, 16),
  );
  const C = await digest(
    encode.encode("certichain:document-commitment:v1\0"),
    bytes(K, 32),
    bytes(I, 32),
    bytes(H, 32),
    bytes(S, 32),
  );
  return { K, C };
}
