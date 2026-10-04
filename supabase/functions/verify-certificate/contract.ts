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
  const date = (v: unknown) =>
    typeof v === "string" &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
      .test(v);
  const issuer = value.issuer as Record<string, unknown> | null;
  return Object.keys(value).sort().join(",") === keys.sort().join(",") &&
    ["valid", "revoked", "expired", "issuer_unavailable"].includes(
      String(value.result),
    ) &&
    value.credential_code === code && typeof value.title === "string" &&
    !!issuer && typeof issuer === "object" && !Array.isArray(issuer) &&
    Object.keys(issuer).join(",") === "name" &&
    typeof issuer.name === "string" &&
    date(value.issued_at) && date(value.checked_at) &&
    (value.expires_at === null || date(value.expires_at)) &&
    value.verification_source === "certichain_registry";
}
