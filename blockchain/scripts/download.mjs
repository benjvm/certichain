// @ts-check
// Standard-library transport. Integrity remains the responsibility of bootstrap.
import { Buffer } from "node:buffer";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";

const apiOrigin = "https://api.github.com";
const transientStatus = new Set([408, 429, 500, 502, 503, 504]);
const transientNetwork = new Set([
  "ECONNRESET",
  "ETIMEDOUT",
  "EAI_AGAIN",
  "ECONNREFUSED",
  "UND_ERR_CONNECT_TIMEOUT",
  "UND_ERR_SOCKET",
]);
class DownloadError extends Error {}
/** @param {string | null} value */
function seconds(value) {
  return value !== null && /^\d+$/.test(value) ? Number(value) : null;
}
/** @param {string | null} value @param {number} now */
function retryAfter(value, now) {
  if (value === null) return null;
  if (/^\d+$/.test(value)) return Number(value) * 1000;
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.max(0, date - now) : null;
}
/** @param {Response} response @param {number} now */
function details(response, now) {
  const remaining = seconds(response.headers.get("x-ratelimit-remaining"));
  const reset = seconds(response.headers.get("x-ratelimit-reset"));
  const after = retryAfter(response.headers.get("retry-after"), now);
  const rateLimited = response.status === 429 || response.status === 403 &&
      (after !== null || remaining === 0 && reset !== null);
  const requestId = response.headers.get("x-github-request-id");
  return {
    status: response.status,
    classification: rateLimited
      ? "rate_limit"
      : transientStatus.has(response.status)
      ? "transient_http"
      : "permanent_http",
    rate_remaining: remaining,
    rate_reset: reset,
    retry_after_ms: after,
    request_id: requestId !== null &&
        /^[0-9a-fA-F]{4}:[0-9a-fA-F:]{1,64}$/.test(requestId)
      ? requestId
      : null,
  };
}

/**
 * @typedef {{classification: string, status?: number, rate_remaining?: number | null,
 * rate_reset?: number | null, retry_after_ms?: number | null, request_id?: string | null}} Diagnostic
 * @param {string} input
 * @param {{token?: string, fetchImpl?: (url: string, options: RequestInit) => Promise<Response> | Response,
 * now?: () => number, sleep?: (ms: number) => Promise<unknown> | void,
 * log?: (record: Record<string, unknown>) => void, budgetMs?: number, maxAttempts?: number}} options
 */
export async function fetchChecked(input, {
  token = process.env.CERTICHAIN_GITHUB_API_TOKEN,
  fetchImpl = globalThis.fetch,
  now = Date.now,
  sleep = delay,
  log = (record) => console.warn(JSON.stringify(record)),
  budgetMs = 120_000,
  maxAttempts = 3,
} = {}) {
  const start = now();
  let original;
  try {
    original = new URL(input);
  } catch {
    throw new DownloadError("Download failed: invalid_url");
  }
  // Do not expose query strings, userinfo, bodies or upstream exception messages.
  const target = original.origin + original.pathname;
  /** @param {Diagnostic & {attempt?: number, retry_exhausted?: boolean}} diagnostic */
  const failure = (diagnostic) =>
    new DownloadError(
      `Download failed: ${JSON.stringify({ target, ...diagnostic })}`,
    );
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    let url = original;
    /** @type {Diagnostic} */
    let diagnostic;
    try {
      for (let hop = 0;; hop++) {
        if (
          !["http:", "https:"].includes(url.protocol) || url.username ||
          url.password ||
          original.protocol === "https:" && url.protocol !== "https:"
        ) {
          throw failure({ classification: "unsafe_redirect" });
        }
        const left = budgetMs - (now() - start);
        if (left <= 0) throw failure({ classification: "budget_exhausted" });
        // New headers on every hop. Never let fetch forward API credentials.
        const headers = new Headers({
          "user-agent": "CertiChain-frozen-toolchain",
        });
        if (url.origin === apiOrigin) {
          headers.set("accept", "application/vnd.github+json");
          headers.set("x-github-api-version", "2022-11-28");
          if (token) headers.set("authorization", `Bearer ${token}`);
        }
        const response = await fetchImpl(url.href, {
          headers,
          redirect: "manual",
          signal: AbortSignal.timeout(Math.max(1, Math.min(left, 30_000))),
        });
        if ([301, 302, 303, 307, 308].includes(response.status)) {
          const location = response.headers.get("location");
          await response.body?.cancel();
          if (hop >= 5 || location === null) {
            throw failure({ classification: "invalid_redirect" });
          }
          try {
            url = new URL(location, url);
          } catch {
            throw failure({ classification: "invalid_redirect" });
          }
          continue;
        }
        if (response.ok) return Buffer.from(await response.arrayBuffer());
        diagnostic = details(response, now());
        await response.body?.cancel();
        break;
      }
    } catch (error) {
      if (
        error instanceof Error && (error.name === "TimeoutError" ||
          typeof error.cause === "object" && error.cause !== null &&
            "code" in error.cause && typeof error.cause.code === "string" &&
            transientNetwork.has(error.cause.code))
      ) {
        diagnostic = { classification: "transient_network" };
      } else {
        // A fetch error may itself contain credentials or arbitrary upstream text.
        if (error instanceof DownloadError) throw error;
        throw failure({ classification: "permanent_transport" });
      }
    }
    const retryable = ["rate_limit", "transient_http", "transient_network"]
      .includes(diagnostic.classification);
    const wait = Math.max(
      1000 * 2 ** (attempt - 1),
      diagnostic.retry_after_ms ?? 0,
      diagnostic.classification === "rate_limit" &&
        diagnostic.rate_remaining === 0 && diagnostic.rate_reset != null
        ? Math.max(0, diagnostic.rate_reset * 1000 - now())
        : 0,
    );
    if (
      !retryable || attempt === maxAttempts || now() - start + wait >= budgetMs
    ) {
      throw failure({ ...diagnostic, attempt, retry_exhausted: retryable });
    }
    log({
      event: "toolchain_download_retry",
      target,
      ...diagnostic,
      attempt,
      wait_ms: wait,
    });
    await sleep(wait);
  }
  throw failure({ classification: "attempts_exhausted" });
}
