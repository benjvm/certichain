import { test } from "node:test";
import process from "node:process";
import assert from "node:assert/strict";
import {
  cameraTestMode,
  cdpFailure,
  evaluate,
  navigateDocument,
  sourceRevision,
} from "./browser_harness.mjs";
import {
  countPublicPost,
  expectSingleV2Post,
  publicEndpoint,
  publicHeadersAreAnonymous,
} from "./public_verification_requests.mjs";
import { until } from "../../supabase/tests/local_issuance_fixture.mjs";
import { setTimeout as delay } from "node:timers/promises";

test("public proxy/CDP headers reject credentials regardless of case or value", () => {
  assert.equal(
    publicHeadersAreAnonymous({ "Content-Type": "application/json" }),
    true,
  );
  for (
    const name of [
      "authorization",
      "Authorization",
      "apikey",
      "ApiKey",
      "cookie",
      "Cookie",
    ]
  ) {
    for (const value of ["", "synthetic-private-value"]) {
      assert.equal(publicHeadersAreAnonymous({ [name]: value }), false);
    }
  }
});

test("public endpoints use exact pathname; v1/v2 count separately from comparison", () => {
  const counts = { v1: 0, v2: 0, comparison: 0 };
  for (
    const [path, version] of [
      ["verify-certificate", "v1"],
      ["verify-certificate-v2", "v2"],
      ["compare-certificate-hash", "comparison"],
    ]
  ) {
    const pathname = `/functions/v1/${path}`;
    assert.equal(publicEndpoint(pathname), version);
    for (const suffix of ["", "?probe=1", "#fragment"]) {
      const url = `http://127.0.0.1:7357${pathname}${suffix}`;
      for (const method of ["OPTIONS", "GET", "HEAD"]) {
        assert.equal(countPublicPost(counts, { url, method }), null);
      }
      assert.equal(countPublicPost(counts, { url, method: "POST" }), version);
    }
  }
  for (
    const path of [
      "/main.dart.js",
      "/assets/verify-certificate-v2",
      "/other/functions/v1/verify-certificate",
      "/functions/v1/verify-certificate-v2/",
      "/functions/v1/verify-certificate-v20",
      "/functions/v1/certificate-opening",
    ]
  ) {
    assert.equal(publicEndpoint(path), null);
    assert.equal(
      countPublicPost(counts, {
        url: `http://127.0.0.1:7357${path}`,
        method: "POST",
      }),
      null,
    );
  }
  assert.deepEqual(counts, { v1: 3, v2: 3, comparison: 3 });
});

test("startup/reload accept exactly one v2 POST per page, including delayed CDP", async () => {
  const counts = { v1: 0, v2: 0, comparison: 0 };
  const otherPage = { v1: 0, v2: 0, comparison: 0 };
  for (const scenario of ["main startup", "main reload"]) {
    const before = { ...counts };
    const events = delay(100).then(() => {
      const request = {
        url: "http://127.0.0.1:55321/functions/v1/verify-certificate-v2",
        method: "POST",
      };
      countPublicPost(counts, request);
      countPublicPost(otherPage, request);
      countPublicPost(otherPage, request);
    });
    await expectSingleV2Post(counts, before, scenario, until);
    await events;
    assert.equal(counts.v2 - before.v2, 1);
  }
  assert.equal(otherPage.v2, 4);
});

test("single-query check rejects two POSTs, including a delayed duplicate", async () => {
  for (const duplicate of ["immediate", "delayed", "mixed-v1-v2"]) {
    const before = { v1: 0, v2: 0, comparison: 0 };
    const counts = { ...before };
    const request = {
      url: "http://127.0.0.1:55321/functions/v1/verify-certificate-v2",
      method: "POST",
    };
    countPublicPost(counts, request);
    if (duplicate === "immediate") countPublicPost(counts, request);
    const events = delay(150).then(() => {
      if (duplicate === "delayed") countPublicPost(counts, request);
      if (duplicate === "mixed-v1-v2") {
        countPublicPost(counts, {
          ...request,
          url: request.url.replace(
            "verify-certificate-v2",
            "verify-certificate",
          ),
        });
      }
    });
    await assert.rejects(
      expectSingleV2Post(counts, before, `main ${duplicate}`, until),
      (error) => {
        assert.match(error.message, /main .*expected=1 observed=2/);
        assert.match(
          error.message,
          /endpoint=\/functions\/v1\/verify-certificate-v2 method=POST/,
        );
        assert.match(error.message, /v1=\d v2=\d comparison=0/);
        return true;
      },
    );
    await events;
  }
});

test("v1 or comparison cannot stand in for the expected v2 query; zero is diagnosed", async () => {
  const before = { v1: 0, v2: 0, comparison: 0 };
  for (
    const counts of [
      { ...before, v1: 1 },
      { ...before, comparison: 1 },
      { ...before },
    ]
  ) {
    let timeout;
    // A zero-count timeout uses the same sanitized diagnostic. The real until
    // is exercised above; avoid a five-second unit test for an absent event.
    const absent = async (predicate, _label, milliseconds) => {
      timeout = milliseconds;
      if (!await predicate()) throw new Error("Timed out");
    };
    await assert.rejects(
      expectSingleV2Post(counts, before, "main absent-v2", absent),
      /main absent-v2: expected=1 observed=[01].*method=POST v1=[01] v2=0 comparison=[01]/,
    );
    assert.equal(timeout, 5000);
  }
});

test("camera capture defaults to SKIP and never runs media callbacks or flags", async () => {
  for (const env of [{}, { CERTICHAIN_TEST_CAMERA: "0" }]) {
    const logs = [], camera = cameraTestMode(env, (line) => logs.push(line));
    assert.equal(camera.enabled, false);
    assert.deepEqual(camera.chromeArgs("unused.y4m"), []);
    await camera.run("capture", () => {
      throw new Error(
        "Disabled camera requested permissions or generated video",
      );
    });
    assert.deepEqual(camera.scenarios, [{
      stage: "capture",
      result: "SKIP",
      reason:
        "Omitidas por instrucción del usuario; no hay cámara física disponible",
    }]);
    assert.deepEqual(logs.map(JSON.parse), camera.scenarios);
  }
});

test("camera opt-in executes capture and records PASS only after success", {
  skip: process.env.CERTICHAIN_TEST_CAMERA === "1"
    ? false
    : "Omitidas por instrucción del usuario; no hay cámara física disponible",
}, async () => {
  const camera = cameraTestMode({ CERTICHAIN_TEST_CAMERA: "1" });
  assert.deepEqual(camera.chromeArgs("real-qr.y4m"), [
    "--use-fake-device-for-media-stream",
    "--use-file-for-fake-video-capture=real-qr.y4m",
  ]);
  let calls = 0;
  await camera.run("capture", async () => {
    assert.deepEqual(camera.scenarios, []);
    await Promise.resolve();
    calls++;
  });
  assert.equal(calls, 1);
  assert.deepEqual(camera.scenarios, [{ stage: "capture", result: "PASS" }]);
  const failure = new Error("Timed out: Código identificado");
  await assert.rejects(
    camera.run("capture-failure", () => {
      throw failure;
    }),
    (error) => error === failure,
  );
  assert.equal(camera.scenarios.length, 1);
});

test("camera configuration rejects ambiguous values", () => {
  for (const value of ["", "true", "2", "yes"]) {
    assert.throws(() => cameraTestMode({ CERTICHAIN_TEST_CAMERA: value }), {
      message: "CERTICHAIN_TEST_CAMERA must be 0 or 1",
    });
  }
});

test("release evidence identifies the actual clean or edited checkout without paths", () => {
  const sha = "62354866e1c127e445c369bedee58742581ec2cd";
  for (const dirty of [false, true]) {
    const calls = [];
    const revision = sourceRevision(
      "own-checkout",
      (command, args, options) => {
        calls.push(args);
        assert.equal(command, "git");
        assert.equal(options.cwd, "own-checkout");
        assert.equal(options.timeout, 5000);
        assert.equal(options.stdio[2], "ignore");
        return {
          status: 0,
          stdout: args[0] === "rev-parse"
            ? sha + "\n"
            : dirty
            ? " M private-config.json\n"
            : "",
        };
      },
    );
    assert.deepEqual(revision, {
      source_commit: sha,
      working_tree_dirty: dirty,
    });
    assert.doesNotMatch(JSON.stringify(revision), /private-config|d31a273/);
    assert.deepEqual(calls, [["rev-parse", "HEAD"], ["status", "--porcelain"]]);
  }
});

test("release evidence fails safely when Git cannot identify the revision", () => {
  for (
    const reply of [{ status: 1, stdout: "credential" }, {
      status: 0,
      stdout: "unexpected",
    }]
  ) {
    assert.throws(() => sourceRevision("own-checkout", () => reply), {
      message: "Cannot identify release source revision",
    });
  }
});

test("CDP diagnostics retain location/type, never remote messages or values", () => {
  const error = cdpFailure("Runtime.evaluate", {
    lineNumber: 8,
    columnNumber: 4,
    executionContextId: 42,
    exception: {
      className: "TypeError",
      description: "secret",
      value: "credential",
    },
  });
  assert.match(error.message, /TypeError.*line=8.*column=4.*context=42/);
  assert.doesNotMatch(error.message, /secret|credential/);
  assert.equal(error.transientNavigation, false);
  assert.doesNotMatch(
    cdpFailure("Runtime.evaluate", {
      exception: { className: "PrivateCredentialError" },
    }).message,
    /PrivateCredential/,
  );
  assert.equal(
    cdpFailure("Runtime.evaluate", {
      code: -32000,
      message: "Execution context was destroyed.",
    }).transientNavigation,
    true,
  );
  assert.equal(
    cdpFailure("Runtime.evaluate", { code: -32000, message: "Internal error" })
      .transientNavigation,
    false,
  );
});
test("reload never uses the old ready document; waits new loader/world/DOM", async () => {
  let loader = "old", frames = 0, dom = false, reloaded = false;
  const calls = [];
  const cdp = async (method, params) => {
    calls.push({ method, params });
    if (method === "Page.getFrameTree") {
      if (reloaded && ++frames > 1) loader = "new";
      return { frameTree: { frame: { id: "frame", loaderId: loader } } };
    }
    if (method === "Page.reload") {
      reloaded = true;
      return {};
    }
    if (method === "Page.createIsolatedWorld") {
      assert.equal(loader, "new");
      return { executionContextId: 77 };
    }
    if (method === "Runtime.evaluate") {
      assert.equal(params.contextId, 77);
      const value = dom;
      dom = true;
      return { result: { value } };
    }
    throw new Error("Unexpected call");
  };
  cdp.documentContext = 1;
  await navigateDocument(cdp, "Page.reload");
  assert.equal(cdp.documentContext, 77);
  assert.equal(calls.filter((c) => c.method === "Runtime.evaluate").length, 2);
});
test("real application exceptions fail evaluation without retry", async () => {
  let calls = 0;
  const cdp = () => {
    calls++;
    return {
      exceptionDetails: {
        exception: { className: "TypeError" },
        lineNumber: 3,
      },
    };
  };
  await assert.rejects(evaluate(cdp, "applicationProbe()"), /TypeError/);
  assert.equal(calls, 1);
});
