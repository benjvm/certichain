export const MAX_PDF = 8_388_608;
export class IssuanceError extends Error {
  constructor(public code: string, public status: number) {
    super(code);
  }
}
const encoder = new TextEncoder();
export function uuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  ) {
    throw new IssuanceError("invalid_input", 400);
  }
  return value.toLowerCase();
}
export function text(
  value: unknown,
  max: number,
  nullable = false,
): string | null {
  if (nullable && (value === null || value === undefined)) return null;
  if (typeof value !== "string") throw new IssuanceError("invalid_input", 400);
  const result = value.normalize("NFC").trim();
  const characters = [...result];
  const hasControl = characters.some((c) => {
    const code = c.codePointAt(0)!;
    return code < 32 || (code >= 127 && code <= 159);
  });
  if (
    hasControl || characters.length > max ||
    encoder.encode(result).length > max * 4
  ) {
    throw new IssuanceError("invalid_input", 400);
  }
  if (!result && !nullable) throw new IssuanceError("invalid_input", 400);
  return result || null;
}
// Avoid Date's millisecond truncation. Parse the calendar separately, preserve
// six fractional digits and apply the timezone only to whole seconds.
export function expiration(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new IssuanceError("invalid_input", 400);
  const m =
    /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$/
      .exec(value);
  if (!m) throw new IssuanceError("invalid_input", 400);
  const date = new Date(`${m[1]}T${m[2]}Z`);
  if (
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 19) !== `${m[1]}T${m[2]}` ||
    m[1].startsWith("0000")
  ) {
    throw new IssuanceError("invalid_input", 400);
  }
  let offset = 0;
  if (m[4] !== "Z") {
    const h = Number(m[4].slice(1, 3)), min = Number(m[4].slice(4));
    if (h > 14 || min > 59 || (h === 14 && min !== 0)) {
      throw new IssuanceError("invalid_input", 400);
    }
    offset = (h * 60 + min) * (m[4][0] === "+" ? 1 : -1);
  }
  const utc = new Date(date.getTime() - offset * 60_000).toISOString();
  if (utc.length !== 24) throw new IssuanceError("invalid_input", 400);
  return `${utc.slice(0, 19)}.${(m[3] ?? "").padEnd(6, "0")}Z`;
}
export interface Input {
  institution_id: string;
  holder_id: string;
  idempotency_key: string;
  title: string;
  description: string | null;
  expires_at: string | null;
}
export function normalize(values: Record<string, unknown>): Input {
  const allowed = [
    "institution_id",
    "holder_id",
    "idempotency_key",
    "title",
    "description",
    "expires_at",
  ];
  if (Object.keys(values).some((key) => !allowed.includes(key))) {
    throw new IssuanceError("invalid_input", 400);
  }
  return {
    institution_id: uuid(values.institution_id),
    holder_id: uuid(values.holder_id),
    idempotency_key: uuid(values.idempotency_key),
    title: text(values.title, 200)!,
    description: text(values.description, 4000, true),
    expires_at: expiration(values.expires_at),
  };
}
export async function sha256(bytes: Uint8Array): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (x) => x.toString(16).padStart(2, "0"),
  ).join("");
}
export function fingerprintBytes(fields: (string | null)[]): Uint8Array {
  const parts = [encoder.encode("certichain-issuance-v1\0")];
  for (const field of fields) {
    const data = field === null ? new Uint8Array() : encoder.encode(field);
    const size = new Uint8Array(4);
    new DataView(size.buffer).setUint32(
      0,
      field === null ? 0xffffffff : data.length,
      false,
    );
    parts.push(size, data);
  }
  const result = new Uint8Array(parts.reduce((n, part) => n + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}
export function fingerprint(
  input: Input,
  actor: string,
  pdfHash: string,
): Promise<string> {
  return sha256(
    fingerprintBytes([
      input.institution_id,
      uuid(actor),
      input.holder_id,
      input.title,
      input.description,
      input.expires_at,
      pdfHash,
    ]),
  );
}
export async function readLimited(
  stream: ReadableStream<Uint8Array> | null,
  limit: number,
): Promise<Uint8Array> {
  if (!stream) throw new IssuanceError("invalid_input", 400);
  const reader = stream.getReader(), parts: Uint8Array[] = [];
  let count = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      count += value.length;
      if (count > limit) {
        await reader.cancel();
        throw new IssuanceError("payload_too_large", 413);
      }
      parts.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(count);
  let offset = 0;
  for (const part of parts) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return bytes;
}
export async function requestInput(
  request: Request,
): Promise<{ input: Input; pdf: Uint8Array }> {
  const type = request.headers.get("content-type") ?? "";
  if (!type.startsWith("multipart/form-data;")) {
    throw new IssuanceError("invalid_input", 400);
  }
  // Includes an explicit metadata/envelope budget; Content-Length is not trusted.
  const body = await readLimited(request.body, MAX_PDF + 32_768);
  let form: FormData;
  try {
    form = await new Response(body, { headers: { "content-type": type } })
      .formData();
  } catch {
    throw new IssuanceError("invalid_input", 400);
  }
  const values: Record<string, unknown> = {};
  let file: File | undefined;
  const seen = new Set<string>();
  for (const [key, value] of form) {
    if (seen.has(key)) throw new IssuanceError("invalid_input", 400);
    seen.add(key);
    if (key === "pdf" && value instanceof File) file = value;
    else if (typeof value === "string") values[key] = value;
    else throw new IssuanceError("invalid_input", 400);
  }
  if (
    !file || !/\.pdf$/i.test(file.name) || file.type !== "application/pdf" ||
    file.size === 0
  ) throw new IssuanceError("invalid_pdf", 422);
  if (file.size > MAX_PDF) throw new IssuanceError("payload_too_large", 413);
  return {
    input: normalize(values),
    pdf: new Uint8Array(await file.arrayBuffer()),
  };
}
