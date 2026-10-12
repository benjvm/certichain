import { test } from "node:test";
import assert from "node:assert/strict";
import {
  cdpFailure,
  evaluate,
  navigateDocument,
  sourceRevision,
} from "./browser_harness.mjs";

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
