import { type AnchoringStore, coordinate, type Job } from "./coordinator.ts";
import {
  type Hex,
  type OperationalRegistry,
  type Receipt,
  RegistryError,
} from "../domain/registry.ts";

const hex = (byte: string, size = 32) => `0x${byte.repeat(size)}` as Hex;
const block = { number: 5n, hash: hex("11") };
const chain = {
  head: { number: 6n, hash: hex("22") },
  finalized: null,
  checkedAt: "2026-10-18T00:00:00Z",
};
function fixture() {
  const actions: string[] = [];
  const job = {
    operation: {
      id: "operation",
      kind: "revoke",
      state: "submitted",
      lease_token: "token",
      generation: "1",
      canonical_attempt_id: null,
    },
    deployment: {
      network: "anvil",
      chain_id: "31337",
      deployment_block: "1",
      contract_address: hex("88", 20),
      runtime_code_hash: hex("aa"),
      genesis_hash: hex("bb"),
      deployment_hash: hex("cc"),
    },
    binding: { issuer_id: hex("33") },
    anchor: { certificate_key: hex("44"), commitment: hex("55") },
    attempts: [{
      id: "attempt",
      transaction_hash: hex("66"),
      nonce: "2",
      signer: hex("77", 20),
      state: "submitted",
    }],
  } as Job;
  const receipt: Receipt = {
    hash: hex("66"),
    status: 1,
    from: hex("77", 20),
    to: hex("88", 20),
    block,
    transactionIndex: 0n,
    logIndex: 1n,
    timestamp: 100n,
    data: "0x",
    nonce: 2n,
    gasUsed: 50000n,
  };
  const store: AnchoringStore = {
    deadline: Infinity,
    pdf: () => {
      throw new Error("Unexpected PDF access for revoke");
    },
    rpc: <T>(name: string, args?: Record<string, unknown>) => {
      if (name === "blockchain_update_job") {
        actions.push(String(args?.p_action));
      } else if (name !== "blockchain_claim") {
        throw new Error("Unexpected signing RPC");
      }
      return Promise.resolve(job as T);
    },
  };
  const registry = {
    deadline: Infinity,
    validateDeployment: () => Promise.resolve(chain),
    canonical: () => Promise.resolve(),
    observe: () => Promise.resolve({ kind: "included", receipt, chain }),
    validateEvidence: () => Promise.resolve(receipt),
    read: () =>
      Promise.resolve({
        K: hex("44"),
        C: hex("55"),
        I: hex("33"),
        registeredAt: 50n,
        revokedAt: 100n,
      }),
  } as unknown as OperationalRegistry;
  return { actions, job, receipt, store, registry };
}
function assert(value: unknown) {
  if (!value) throw new Error("Coordinator invariant failed");
}

for (const mismatch of ["receipt", "head", "nonce"] as const) {
  Deno.test(`revoke ${mismatch} mismatch cannot persist success or release its nonce`, async () => {
    const f = fixture();
    const read = f.registry.read;
    f.registry.read = async (K, at) => {
      const r = await read(K, at);
      return r &&
          (mismatch === "receipt" && at.number === block.number ||
            mismatch === "head" && at.number === chain.head.number)
        ? { ...r, I: hex("ff") }
        : r;
    };
    if (mismatch === "nonce") f.receipt.nonce = 3n;
    assert(
      await coordinate(f.store, "operation", () => f.registry) ===
        "incompatible_evidence",
    );
    assert(
      f.actions.includes("incompatible") && !f.actions.includes("receipt"),
    );
  });
}
Deno.test("temporary receipt lookup failure never promotes a persisted old receipt", async () => {
  const f = fixture();
  f.job.operation.state = "confirmed";
  f.job.operation.canonical_attempt_id = f.job.attempts[0].id;
  f.job.attempts[0].block_number = block.number.toString();
  f.job.attempts[0].block_hash = block.hash;
  f.registry.observe = () => Promise.reject(new RegistryError("rpc_timeout"));
  assert(
    await coordinate(f.store, "operation", () => f.registry) === "rpc_timeout",
  );
  assert(f.actions.join(",") === "error");
});
Deno.test("an earlier winning replacement is reconciled before any new signature", async () => {
  const f = fixture();
  f.job.attempts.push({
    ...f.job.attempts[0],
    id: "replacement",
    transaction_hash: hex("99"),
  });
  await coordinate(f.store, "operation", () => f.registry);
  assert(f.actions.join(",") === "receipt,release");
});
Deno.test("previous consumed revert is observed afresh without replaying failed transition", async () => {
  const f = fixture();
  f.job.operation.state = "requested";
  f.job.attempts[0].state = "reverted";
  f.receipt.status = 0;
  f.registry.read = () => Promise.reject(new RegistryError("rpc_timeout"));
  assert(
    await coordinate(f.store, "operation", () => f.registry) === "rpc_timeout",
  );
  assert(f.actions.join(",") === "reconciled,error");
});
Deno.test("blocked pending bytes stay observable without resend errors or implicit authorization", async () => {
  const f = fixture();
  f.job.operation.state = "blocked";
  f.job.attempts[0].raw_signed_tx = "0x02ff";
  f.job.attempts[0].created_at = new Date().toISOString();
  f.job.attempts[0].state = "pending";
  f.registry.observe = () => Promise.resolve({ kind: "pending" });
  f.registry.latestNonce = () => Promise.resolve(2n);
  f.registry.read = () =>
    Promise.resolve({
      K: hex("44"),
      C: hex("55"),
      I: hex("33"),
      registeredAt: 50n,
      revokedAt: 0n,
    });
  assert(
    await coordinate(f.store, "operation", () => f.registry) === "pending",
  );
  assert(
    f.actions.join(",") === "pending,release" &&
      f.job.operation.state === "blocked",
  );
});
for (const compatible of [true, false]) {
  Deno.test(`late issue after SQL revocation requires compatible C/I (${compatible})`, async () => {
    const f = fixture();
    f.job.operation.kind = "issue";
    f.job.sql_revoked = true;
    f.job.revocation_expected = true;
    const read = f.registry.read;
    f.registry.read = async (K, at) => {
      const record = await read(K, at);
      return record && !compatible ? { ...record, C: hex("ff") } : record;
    };
    const result = await coordinate(f.store, "operation", () => f.registry);
    assert(
      compatible
        ? f.actions.includes("receipt")
        : result === "divergence" && !f.actions.includes("receipt"),
    );
  });
}
