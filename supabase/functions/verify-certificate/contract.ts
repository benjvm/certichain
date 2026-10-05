export const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function credentialCode(input: unknown): string | null {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null;
  const fields = Object.keys(input);
  const code = (input as Record<string, unknown>).credential_code;
  return fields.length === 1 && fields[0] === "credential_code" &&
      typeof code === "string" && code.length === 36 && UUID.test(code)
    ? code.toLowerCase()
    : null;
}

// Validate components without normalizing PostgreSQL microseconds.
export function publicTimestamp(value: unknown): boolean {
  if (typeof value !== "string") return false;
  const parts =
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(?:Z|([+-])(\d{2}):(\d{2}))$/
      .exec(value);
  if (!parts || parts[0].length !== value.length) return false;
  const [year, month, day, hour, minute, second] = parts.slice(1, 7).map(
    Number,
  );
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return year >= 1 && month >= 1 && month <= 12 && day >= 1 &&
    day <= days[month - 1] && hour <= 23 && minute <= 59 && second <= 59 &&
    (!parts[8] || (Number(parts[9]) <= 23 && Number(parts[10]) <= 59));
}

// Validate the closed projection before returning backend JSON. Dates remain
// strings: converting through JS Date would discard PostgreSQL microseconds.
export function publicProjection(data: unknown, code: string): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return false;
  const value = data as Record<string, unknown>;
  if (value.schema_version !== "1") return false;
  if (value.result === "not_found") {
    return Object.keys(value).sort().join(",") === "result,schema_version";
  }
  const keys = [
    "schema_version",
    "result",
    "credential_code",
    "title",
    "issuer",
    "issued_at",
    "expires_at",
    "checked_at",
    "verification_source",
  ];
  const issuer = value.issuer as Record<string, unknown> | null;
  return Object.keys(value).sort().join(",") === keys.sort().join(",") &&
    typeof value.result === "string" &&
    ["valid", "revoked", "expired", "issuer_unavailable"].includes(
      value.result,
    ) &&
    value.credential_code === code && typeof value.title === "string" &&
    !!issuer && typeof issuer === "object" && !Array.isArray(issuer) &&
    Object.keys(issuer).join(",") === "name" &&
    typeof issuer.name === "string" &&
    publicTimestamp(value.issued_at) && publicTimestamp(value.checked_at) &&
    (value.expires_at === null || publicTimestamp(value.expires_at)) &&
    value.verification_source === "certichain_registry";
}
