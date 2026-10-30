import { setTimeout as delay } from "node:timers/promises";

function readinessFailure(reason, diagnostic) {
  // The acceptance runner intentionally discards arbitrary exception messages.
  // Emit this closed diagnostic before throwing so Actions retains the cause.
  console.log(JSON.stringify({
    stage: "browser-auth-readiness",
    result: "FAIL",
    reason,
    ...diagnostic,
  }));
  return new Error(
    `Browser Auth readiness: ${reason}${
      diagnostic ? ` HTTP ${diagnostic.status} ${diagnostic.code}` : ""
    }`,
  );
}

export function restFailureDiagnostic(status, data) {
  const reasons = {
    "JWT issued at future": "jwt-issued-at-future",
    "JWT not yet valid": "jwt-not-yet-valid",
    "JWT expired": "jwt-expired",
    "JWT not in audience": "jwt-audience",
    "Parsing claims failed": "jwt-claims-parsing",
  };
  return {
    status,
    code: /^[A-Z0-9_]{1,20}$/.test(data?.code ?? "") ? data.code : "OTHER",
    reason: data?.code === "PGRST303" && Object.hasOwn(reasons, data?.message)
      ? reasons[data.message]
      : "other",
  };
}

// Host-only readiness after the synchronous release build. PostgREST versions
// with a stale idle clock can reject a newly issued JWT before the UI starts.
// Never retry login, mutations, or an arbitrary JWT/permission failure.
export async function localBrowserAuthReady(local, user) {
  const url = new URL(local.API_URL);
  if (
    url.protocol !== "http:" ||
    !["127.0.0.1", "localhost"].includes(url.hostname) ||
    url.username || url.password || url.pathname !== "/" || url.search ||
    url.hash
  ) throw readinessFailure("requires a local API");
  const headers = {
    apikey: local.ANON_KEY,
    "content-type": "application/json",
    connection: "close",
  };
  const login = await fetch(
    new URL("/auth/v1/token?grant_type=password", url),
    {
      method: "POST",
      redirect: "error",
      headers,
      body: JSON.stringify({ email: user.email, password: user.password }),
      signal: AbortSignal.timeout(5000),
    },
  ).catch(() => {
    throw readinessFailure("transport failed");
  });
  const session = await login.json().catch(() => null);
  if (
    !login.ok || session?.user?.id !== user.id ||
    typeof session?.access_token !== "string" || !session.access_token
  ) throw readinessFailure("login failed");
  const profile = new URL("/rest/v1/profiles", url);
  profile.searchParams.set("id", `eq.${user.id}`);
  profile.searchParams.set("select", "id");
  for (let attempt = 1; attempt <= 3; attempt++) {
    const response = await fetch(profile, {
      redirect: "error",
      headers: { ...headers, Authorization: `Bearer ${session.access_token}` },
      signal: AbortSignal.timeout(5000),
    }).catch(() => {
      throw readinessFailure("transport failed");
    });
    const data = await response.json().catch(() => null);
    if (response.ok) {
      if (
        !Array.isArray(data) || data.length !== 1 || data[0]?.id !== user.id
      ) throw readinessFailure("profile identity failed");
      return {
        stage: "browser-auth-readiness",
        result: "PASS",
        attempts: attempt,
      };
    }
    const future = response.status === 401 && data?.code === "PGRST303" &&
      data.message === "JWT issued at future";
    if (!future || attempt === 3) {
      const diagnostic = restFailureDiagnostic(response.status, data);
      throw readinessFailure(diagnostic.reason, {
        status: diagnostic.status,
        code: diagnostic.code,
      });
    }
    await delay(attempt * 500);
  }
}
