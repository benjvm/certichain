import { setTimeout as delay } from "node:timers/promises";

// Exact public endpoint allowlist, shared by the proxy and CDP observer.
export function publicEndpoint(pathname) {
  switch (pathname) {
    case "/functions/v1/verify-certificate":
      return "v1";
    case "/functions/v1/verify-certificate-v2":
      return "v2";
    case "/functions/v1/verify-certificate-v3":
      return "v3";
    case "/functions/v1/compare-certificate-hash":
      return "comparison";
    default:
      return null;
  }
}

export function countPublicPost(counts, request) {
  const endpoint = publicEndpoint(new URL(request.url).pathname);
  if (!endpoint || request.method !== "POST") return null;
  counts[endpoint] = (counts[endpoint] ?? 0) + 1;
  return endpoint;
}

export function publicHeadersAreAnonymous(headers) {
  return !Object.keys(headers).some((name) =>
    ["authorization", "apikey", "cookie"].includes(name.toLowerCase())
  );
}

// Counts belong to one CDP page. Never include another tab's activity.
export function expectSingleV2Post(counts, before, scenario, until) {
  return expectSinglePublicPost(counts, before, scenario, until, "v2");
}
export async function expectSinglePublicPost(
  counts,
  before,
  scenario,
  until,
  version = "v3",
) {
  function delta() {
    const v1 = counts.v1 - before.v1, v2 = counts.v2 - before.v2;
    const comparison = counts.comparison - before.comparison;
    const v3 = (counts.v3 ?? 0) - (before.v3 ?? 0);
    return { v1, v2, v3, comparison, verification: v1 + v2 + v3 };
  }
  function diagnostic() {
    const d = delta();
    return `${scenario}: expected=1 observed=${d.verification} ` +
      `endpoint=/functions/v1/verify-certificate-${version} method=POST ` +
      `v1=${d.v1} v2=${d.v2} comparison=${d.comparison} v3=${d.v3}`;
  }
  function assertSingle() {
    const d = delta();
    if (d.verification !== 1 || d[version] !== 1) {
      throw new Error(diagnostic());
    }
  }
  try {
    await until(
      () => {
        const d = delta();
        if (d.verification > 1) throw new Error(diagnostic());
        return d.verification === 1;
      },
      scenario,
      5000,
    );
  } catch (_) {
    throw new Error(diagnostic());
  }
  assertSingle();
  // Reaching one is not stability: observe another bounded half second after
  // the rendered result, catching delayed duplicates without replaying a POST.
  const deadline = Date.now() + 500;
  while (Date.now() < deadline) {
    await delay(50);
    assertSingle();
  }
  assertSingle();
}
