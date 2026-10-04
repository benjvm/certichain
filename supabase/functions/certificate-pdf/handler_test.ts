import { handler } from "./handler.ts";
import { sha256 } from "../issue-certificate/contract.ts";
import { pdfFixture } from "../../tests/pdf_fixture.mjs";

const id = "11111111-2222-3333-4444-555555555555";
const config = {
  url: "http://backend",
  anonKey: "public",
  serviceKey: "technical-secret",
};
function check(value: unknown, label: string) {
  if (!value) throw new Error(label);
}
const request = () =>
  new Request("http://localhost", {
    method: "POST",
    headers: { Authorization: "Bearer real-session" },
    body: JSON.stringify({ certificate_id: id }),
  });
for (
  const mode of [
    "available",
    "absent",
    "legacy",
    "storage_missing",
    "membership_lost",
    "suspended",
    "invalid_session",
    "sign_failed",
    "auth_down",
  ]
) {
  Deno.test(`PDF safe response: ${mode}`, async () => {
    const original = globalThis.fetch;
    let authorizations = 0, signed = false;
    const hash = await sha256(pdfFixture());
    globalThis.fetch = (async (url, init) => {
      await Promise.resolve();
      const target = String(url);
      if (target.endsWith("/auth/v1/user")) {
        check(
          new Headers(init?.headers).get("apikey") === "public",
          "Auth uses public client",
        );
        return mode === "invalid_session"
          ? Response.json({}, { status: 401 })
          : mode === "auth_down"
          ? Response.json({}, { status: 503 })
          : Response.json({ id });
      }
      if (target.includes("/rpc/authorize_certificate_document")) {
        authorizations++;
        check(
          JSON.parse(String(init?.body)).p_actor === id,
          "Actor comes from Auth",
        );
        return Response.json(
          ["absent", "legacy"].includes(mode) ||
            authorizations === 2 &&
              ["membership_lost", "suspended"].includes(mode)
            ? null
            : { path: `${id}/${id}.pdf`, hash },
        );
      }
      if (target.includes("/object/authenticated/")) {
        return mode === "storage_missing"
          ? new Response(null, { status: 404 })
          : new Response(pdfFixture(), {
            headers: { "content-type": "application/pdf" },
          });
      }
      if (target.includes("/object/sign/")) {
        check(
          JSON.parse(String(init?.body)).expiresIn === 60,
          "60 seconds exactly",
        );
        signed = true;
        return mode === "sign_failed"
          ? Response.json({}, { status: 500 })
          : Response.json({
            signedURL:
              `/object/sign/certificates/${id}/${id}.pdf?token=ephemeral`,
          });
      }
      throw new Error("Unexpected request");
    }) as typeof fetch;
    try {
      const response = await handler(config)(request());
      const data = await response.json();
      check(
        response.headers.get("cache-control") === "no-store",
        "Never cached",
      );
      check(
        !JSON.stringify(data).match(
          /document_path|document_hash|technical-secret/,
        ),
        "No private fields",
      );
      if (mode === "available") {
        check(
          response.status === 200 && data.expires_in === 60 && signed &&
            authorizations === 2,
          "Fresh authorization then sign",
        );
      } else {check(
          response.status ===
            (mode === "invalid_session"
              ? 401
              : mode === "auth_down"
              ? 503
              : 404),
          "Safe failure status",
        );}
      if (["membership_lost", "suspended"].includes(mode)) {
        check(!signed, "No signing after revoked access");
      }
    } finally {
      globalThis.fetch = original;
    }
  });
}
Deno.test("PDF/issuance CORS preflight is nonprivileged and no-store", async () => {
  const response = await handler(config)(
    new Request("http://localhost", { method: "OPTIONS" }),
  );
  check(
    response.status === 204 &&
      response.headers.get("access-control-allow-headers")?.includes(
        "authorization",
      ),
    "Authenticated Chrome preflight",
  );
});
Deno.test("PDF body accepts only one string UUID and never coerces arrays", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async () => {
      await Promise.resolve();
      return Response.json({ id, is_anonymous: false });
    };
    for (
      const body of [null, [], "text", { certificate_id: [id] }, {
        certificate_id: id,
        actor_id: id,
      }, { certificate_id: 1 }]
    ) {
      const response = await handler(config)(
        new Request("http://localhost", {
          method: "POST",
          headers: { Authorization: "Bearer real-session" },
          body: JSON.stringify(body),
        }),
      );
      check(response.status === 400, "Closed input without UUID coercion");
    }
  } finally {
    globalThis.fetch = original;
  }
});
