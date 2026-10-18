import {
  gatewayObservation,
  gatewayPolicy,
  privateRoutes,
} from "./phase10_gateway_policy.ts";

function equal(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error("Policy assertion failed");
  }
}
const route = privateRoutes[0];
const code = "UNAUTHORIZED_NO_AUTH_HEADER";
const generic = {
  code,
  message: "Missing authorization header",
  msg: "Missing authorization header",
};
const reply = (
  body: unknown,
  status = 401,
  cache?: string,
  gatewayCode: string | null = code,
) => {
  const headers = new Headers();
  if (cache !== undefined) headers.set("cache-control", cache);
  if (gatewayCode !== null) headers.set("sb-error-code", gatewayCode);
  return Response.json(body, { status, headers });
};
Deno.test("known generic JWT rejection: acceptance exception is visible, strict diagnostic stays FAIL", async () => {
  const r = await gatewayObservation(route, "no_token", reply(generic));
  equal([r.result, r.authentication_result, r.privacy_result], [
    "PASS",
    "PASS",
    "PASS",
  ]);
  equal([
    r.strict_no_store_result,
    r.cache_control,
    r.external_exception_applied,
  ], ["FAIL", null, true]);
});
Deno.test("upstream no-store satisfies strict policy without unnecessary exception", async () => {
  const r = await gatewayObservation(
    route,
    "no_token",
    reply(generic, 401, "no-store"),
  );
  equal([r.result, r.strict_no_store_result, r.external_exception_applied], [
    "PASS",
    "PASS",
    false,
  ]);
});
for (
  const [scenario, gatewayCode, message] of [
    ["invalid_token", "UNAUTHORIZED_INVALID_JWT_FORMAT", "Invalid JWT format"],
    ["expired_token", "UNAUTHORIZED_ASYMMETRIC_JWT", "Invalid JWT"],
    ["expired_token", "UNAUTHORIZED_LEGACY_JWT", "Invalid JWT"],
  ]
) {
  Deno.test(`closed generic ${gatewayCode} recognized only in matching scenario`, async () => {
    const body = { code: gatewayCode, message };
    equal(
      (await gatewayObservation(
        route,
        scenario,
        reply(body, 401, undefined, gatewayCode),
      )).result,
      "PASS",
    );
    equal(
      (await gatewayObservation(
        route,
        "no_token",
        reply(body, 401, undefined, gatewayCode),
      )).result,
      "FAIL",
    );
  });
}
for (
  const body of [
    { ...generic, certificate_id: "private-id" },
    { ...generic, reason: "private-reason" },
    { ...generic, identity: "private-user" },
    { ...generic, token: "private-token" },
    { ...generic, message: "private-reason private-token" },
    { ...generic, msg: "private-user" },
    { ...generic, code: "private-token" },
    { error: "unauthenticated" },
    {},
    null,
  ]
) {
  Deno.test("gateway body must be closed and generic; private values never enter report", async () => {
    const r = await gatewayObservation(route, "no_token", reply(body));
    equal(r.result, "FAIL");
    equal(r.external_exception_applied, false);
    equal(JSON.stringify(r).includes("private-"), false);
  });
}
Deno.test("unexpected status, code, route, cache policy or malformed JSON never qualifies", async () => {
  for (
    const response of [
      reply(generic, 403),
      reply(generic, 503),
      reply(generic, 401, "public"),
      reply(generic, 401, undefined, "UNKNOWN"),
      reply(generic, 401, undefined, null),
      new Response(
        '{"code":"UNAUTHORIZED_NO_AUTH_HEADER","code":"UNAUTHORIZED_NO_AUTH_HEADER","message":"Missing authorization header"}',
        {
          status: 401,
          headers: {
            "content-type": "application/json",
            "sb-error-code": code,
          },
        },
      ),
      new Response(new Uint8Array([255]), {
        status: 401,
        headers: { "content-type": "application/json", "sb-error-code": code },
      }),
      new Response("not JSON", {
        status: 401,
        headers: { "sb-error-code": code },
      }),
    ]
  ) {
    equal(
      (await gatewayObservation(route, "no_token", response)).result,
      "FAIL",
    );
  }
  equal(
    (await gatewayObservation("other", "no_token", reply(generic))).result,
    "FAIL",
  );
});
Deno.test("handler 401 and every other handler status require no-store; spoofed gateway header cannot exempt them", async () => {
  for (const status of [200, 202, 400, 401, 404, 409, 413, 503]) {
    for (const gatewayCode of [null, code]) {
      const r = await gatewayObservation(
        route,
        "anonymous_api_jwt",
        reply({ error: "unauthenticated" }, status, undefined, gatewayCode),
      );
      equal([
        r.result,
        r.application_no_store_result,
        r.external_exception_applied,
      ], ["FAIL", "FAIL", false]);
    }
  }
  const r = await gatewayObservation(
    route,
    "anonymous_api_jwt",
    reply({ error: "unauthenticated" }, 401, "no-store", null),
  );
  equal([r.result, r.application_no_store_result], ["PASS", "PASS"]);
});
Deno.test("network/oversize failure and incomplete/repeated matrix cannot become acceptance PASS", async () => {
  let failed = false;
  try {
    await gatewayObservation(route, "no_token", reply("a".repeat(8193)));
  } catch {
    failed = true;
  }
  equal(failed, true);
  failed = false;
  try {
    await gatewayObservation(
      route,
      "no_token",
      new Response(
        new ReadableStream({
          start(controller) {
            controller.error(new Error("private transport failure"));
          },
        }),
        { status: 401 },
      ),
    );
  } catch {
    failed = true;
  }
  equal(failed, true);
  const r = await gatewayObservation(route, "no_token", reply(generic));
  equal(gatewayPolicy([]).result, "FAIL");
  equal(gatewayPolicy(Array(17).fill(r)).result, "FAIL");
});

Deno.test("complete matrix separates acceptance, app headers and strict diagnosis; private DTO stays in memory", async () => {
  const certificate = "00112233-4455-6677-8899-aabbccddeeff";
  for (const cache of [undefined, "no-store"]) {
    const observations = [];
    for (const endpoint of privateRoutes) {
      for (
        const [scenario, gatewayCode, message] of [
          ["no_token", code, "Missing authorization header"],
          [
            "invalid_token",
            "UNAUTHORIZED_INVALID_JWT_FORMAT",
            "Invalid JWT format",
          ],
          ["expired_token", "UNAUTHORIZED_ASYMMETRIC_JWT", "Invalid JWT"],
        ]
      ) {
        observations.push(
          await gatewayObservation(
            endpoint,
            scenario,
            reply({ code: gatewayCode, message }, 401, cache, gatewayCode),
          ),
        );
      }
      observations.push(
        await gatewayObservation(
          endpoint,
          "valid_session_invalid_input",
          reply({ error: "invalid_input" }, 400, "no-store", null),
        ),
      );
      observations.push(
        await gatewayObservation(
          endpoint,
          "anonymous_api_jwt",
          reply({ error: "unauthenticated" }, 401, "no-store", null),
        ),
      );
    }
    const dto = {
      certificate_id: certificate,
      request_id: certificate,
      status: "revoked",
      revoked_at: "2026-10-18T12:00:00.123456Z",
      reason: "private-reason",
      synchronization: [],
    };
    observations.push(
      await gatewayObservation(
        "revocation-progress",
        "valid_owner_authorized",
        reply(dto, 200, "no-store", null),
        certificate,
      ),
    );
    observations.push(
      await gatewayObservation(
        "revocation-progress",
        "valid_foreign_denied",
        reply({ error: "revocation_unavailable" }, 404, "no-store", null),
      ),
    );
    const report = gatewayPolicy(observations);
    equal([
      report.result,
      report.authentication_result,
      report.privacy_result,
      report.application_no_store_result,
    ], ["PASS", "PASS", "PASS", "PASS"]);
    equal(report.cache_control_result, cache ? "PASS" : "FAIL");
    equal(report.external_exception_count, cache ? 0 : 9);
    equal(JSON.stringify(report).includes("private-reason"), false);
    const leaked = await gatewayObservation(
      "revocation-progress",
      "valid_owner_authorized",
      reply({ ...dto, token: "private-token" }, 200, "no-store", null),
      certificate,
    );
    equal(leaked.result, "FAIL");
    equal(JSON.stringify(leaked).includes("private-token"), false);
  }
});
