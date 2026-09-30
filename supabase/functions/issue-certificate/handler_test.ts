import { handler } from "./handler.ts";
import { pdfFixture } from "../../tests/pdf_fixture.mjs";

const actor = "71000000-0000-4000-8000-000000000001",
  institution = "71000000-0000-4000-8000-000000000002";
const config = {
  url: "http://localhost",
  anonKey: "public-test",
  serviceKey: "technical-test",
};
function request(): Request {
  const form = new FormData();
  for (
    const [key, value] of Object.entries({
      institution_id: institution,
      holder_id: actor,
      idempotency_key: actor,
      title: "Test",
    })
  ) form.append(key, value);
  form.append(
    "pdf",
    new Blob([pdfFixture()], { type: "application/pdf" }),
    "fixture.pdf",
  );
  return new Request("http://localhost/issue", {
    method: "POST",
    headers: { Authorization: "Bearer caller-test" },
    body: form,
  });
}
function check(condition: boolean, label: string) {
  if (!condition) throw new Error(label);
}

for (
  const mode of [
    "auth_unavailable",
    "reservation_failed",
    "upload_reply_lost",
    "read_failed",
    "publication_failed",
    "commit_reply_lost",
    "unexpected_failure",
  ]
) {
  Deno.test(`safe HTTP response and client separation: ${mode}`, async () => {
    const original = globalThis.fetch;
    let published = false, stored = false, reservedActor: unknown;
    globalThis.fetch =
      (async (url: string | URL | Request, init?: RequestInit) => {
        await Promise.resolve(); // Preserve the asynchronous fetch boundary.
        const target = String(url), headers = new Headers(init?.headers);
        if (target.endsWith("/auth/v1/user")) {
          check(
            headers.get("Authorization") === "Bearer caller-test" &&
              headers.get("apikey") === config.anonKey,
            "Auth uses caller client",
          );
          if (mode === "auth_unavailable") {
            return new Response("{}", { status: 503 });
          }
          if (mode === "unexpected_failure") {
            return new Response("broken", { status: 200 });
          }
          return Response.json({
            id: actor,
            user_metadata: { role: "platform_admin", actor_id: "attacker" },
          });
        }
        check(
          headers.get("Authorization") === `Bearer ${config.serviceKey}`,
          "Only backend uses technical key",
        );
        if (target.endsWith("/rpc/reserve_certificate_issuance")) {
          const args = JSON.parse(String(init?.body));
          reservedActor = args.p_actor;
          if (mode === "reservation_failed") {
            return Response.json({ code: "XX000", message: "private data" }, {
              status: 500,
            });
          }
          return Response.json({
            status: "uploading",
            operation_id: actor,
            lease_token: institution,
            target_certificate_id: actor,
          });
        }
        if (target.includes("/object/certificates/")) {
          check(headers.get("x-upsert") === "false", "Upload never replaces");
          stored = true;
          if (mode === "upload_reply_lost") throw new Error("lost response");
          return Response.json({});
        }
        if (target.includes("/object/authenticated/")) {
          if (mode === "read_failed") return Response.json({}, { status: 503 });
          check(stored, "Read follows upload");
          return new Response(pdfFixture(), {
            headers: { "Content-Type": "application/pdf" },
          });
        }
        if (target.endsWith("/rpc/advance_certificate_issuance")) {
          const args = JSON.parse(String(init?.body));
          if (args.p_action === "validate") {
            return Response.json({ status: "finalizing" });
          }
          if (mode === "publication_failed") {
            return Response.json({
              code: "XX000",
              message: "private path and document",
            }, { status: 500 });
          }
          published = true;
          if (mode === "commit_reply_lost") {
            throw new Error("lost response after commit");
          }
          return Response.json({ status: "completed", certificate_id: actor });
        }
        throw new Error("Unexpected call");
      }) as typeof fetch;
    try {
      const response = await handler(config)(request()),
        body = await response.json();
      if (mode === "upload_reply_lost") {
        check(
          response.status === 201 && published,
          "Lost upload response resolves by verified read",
        );
      } else {check(
          response.status === (mode === "unexpected_failure" ? 500 : 503),
          "Failures never announce success",
        );}
      if (!["auth_unavailable", "unexpected_failure"].includes(mode)) {
        check(reservedActor === actor, "Verified Auth ID wins over metadata");
      }
      if (mode === "commit_reply_lost") {
        check(
          published && response.status === 503,
          "Unknown commit returns retry error",
        );
      }
      check(
        !JSON.stringify(body).includes("private") &&
          !JSON.stringify(body).includes(config.serviceKey),
        "Safe error body",
      );
    } finally {
      globalThis.fetch = original;
    }
  });
}
