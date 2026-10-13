// Bounded callers supply UTF-8 bytes. Reject duplicate (also escaped) keys,
// excessive nesting/nodes and nonfinite numbers before accepting any DTO.
export function strictJson(source: string): unknown {
  let at = 0, nodes = 0;
  const whitespace = () => {
    while (/[\x20\t\r\n]/.test(source[at] ?? "x")) at++;
  };
  const fail = (): never => {
    throw new Error("Invalid JSON");
  };
  function string(): string {
    const start = at++;
    while (at < source.length) {
      const c = source[at++];
      if (c === "\\") {
        at++;
        continue;
      }
      if (c === '"') return JSON.parse(source.slice(start, at));
    }
    return fail();
  }
  function value(depth: number): unknown {
    if (depth > 16 || ++nodes > 4096) fail();
    whitespace();
    if (source[at] === '"') return string();
    if (source[at] === "{") {
      at++;
      whitespace();
      const result: Record<string, unknown> = Object.create(null);
      if (source[at] === "}") {
        at++;
        return result;
      }
      while (true) {
        whitespace();
        if (source[at] !== '"') fail();
        const key = string();
        whitespace();
        if (Object.hasOwn(result, key) || source[at++] !== ":") fail();
        result[key] = value(depth + 1);
        whitespace();
        const next = source[at++];
        if (next === "}") return result;
        if (next !== ",") fail();
      }
    }
    if (source[at] === "[") {
      at++;
      whitespace();
      const result: unknown[] = [];
      if (source[at] === "]") {
        at++;
        return result;
      }
      while (true) {
        result.push(value(depth + 1));
        whitespace();
        const next = source[at++];
        if (next === "]") return result;
        if (next !== ",") fail();
      }
    }
    const token =
      /^(?:null|true|false|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(
        source.slice(at),
      );
    if (!token) return fail();
    at += token[0].length;
    const result = JSON.parse(token[0]);
    if (typeof result === "number" && !Number.isFinite(result)) fail();
    return result;
  }
  const result = value(0);
  whitespace();
  if (at !== source.length) fail();
  return result;
}

export function object(
  value: unknown,
  keys: string[],
): Record<string, unknown> {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).sort().join(",") !== [...keys].sort().join(",")
  ) throw new Error("Invalid DTO");
  return value as Record<string, unknown>;
}
export const decimal = (v: unknown): v is string =>
  typeof v === "string" && v.length <= 20 && /^(0|[1-9]\d*)$/.test(v);
export const fixedHex = (v: unknown, size = 32): v is `0x${string}` =>
  typeof v === "string" && v.length === 2 + size * 2 && /^0x[0-9a-f]+$/.test(v);
