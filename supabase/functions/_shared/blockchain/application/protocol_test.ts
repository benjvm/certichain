import { commitment, digest } from "./commitment.ts";
import { calldata, EvmRegistry } from "../data/evm_registry.ts";
import {
  type Deployment,
  type Hex,
  RegistryError,
} from "../domain/registry.ts";
import { keccak256, Transaction } from "ethers";
function equal(a: unknown, b: unknown) {
  if (a !== b) throw new Error(`Mismatch ${String(a)} != ${String(b)}`);
}
import rawFixture from "../../../../../blockchain/fixtures/protocol-v1.json" with {
  type: "json",
};
import { pdfFixture } from "../../../../tests/pdf_fixture.mjs";
const fixture = rawFixture as typeof rawFixture & {
  issuer_id: Hex;
  document_sha256: Hex;
  salt: Hex;
  certificate_key: Hex;
  commitment: Hex;
};
Deno.test("shared 9B vector: exact binary UUID and SHA256 domains", async () => {
  const pdf = pdfFixture();
  equal(await digest(pdf), fixture.document_sha256);
  const actual = await commitment(
    fixture.credential_code,
    fixture.issuer_id,
    fixture.document_sha256,
    fixture.salt,
  );
  equal(actual.K, fixture.certificate_key);
  equal(actual.C, fixture.commitment);
});
Deno.test("canonical RPC absence requires a successful exists=false", async () => {
  const d = { contractAddress: `0x${"11".repeat(20)}` } as Deployment;
  const registry = new EvmRegistry("http://127.0.0.1:1", d);
  registry.rpc = () => Promise.reject(new RegistryError("rpc_timeout"));
  let code = "";
  try {
    await registry.read(`0x${"22".repeat(32)}`, {
      number: 1n,
      hash: `0x${"33".repeat(32)}`,
    });
  } catch (e) {
    if (e instanceof RegistryError) code = e.code;
  }
  equal(code, "rpc_timeout");
});
Deno.test("standard ethers EIP1559 signing roundtrip preserves ABI/payload and hash", async () => {
  const command = {
    kind: "issue" as const,
    K: fixture.certificate_key,
    C: fixture.commitment,
    I: fixture.issuer_id,
  };
  const tx = Transaction.from({
    type: 2,
    chainId: 31337n,
    nonce: 0,
    to: `0x${"11".repeat(20)}`,
    data: calldata(command),
    value: 0n,
    gasLimit: 150000n,
    maxFeePerGas: 2000000000n,
    maxPriorityFeePerGas: 1000000000n,
  });
  const { Wallet } = await import("ethers");
  const wallet = Wallet.createRandom();
  const signed = await wallet.signTransaction(tx);
  const parsed = Transaction.from(signed);
  equal(parsed.hash, keccak256(signed));
  equal(parsed.from, wallet.address);
  equal(parsed.data, calldata(command));
  equal(parsed.type, 2);
  equal(parsed.chainId, 31337n);
});
