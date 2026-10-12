import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { cast, forge, lock, root, sha256, verifyVersions } from "./common.mjs";

export function generateArtifacts(check = false) {
  verifyVersions();
  // Coverage disables optimization/instruments builds: always rebuild normally before exporting.
  forge("build", "--force");
  const config = JSON.parse(forge("config", "--json"));
  assert.equal(config.evm_version, "cancun");
  assert.equal(config.optimizer, true);
  assert.equal(config.optimizer_runs, 200);
  assert.equal(config.via_ir, false);
  assert.equal(config.dynamic_test_linking, false);
  const build = JSON.parse(
    readFileSync(
      resolve(root, "out/CertificateRegistry.sol/CertificateRegistry.json"),
    ),
  );
  const metadata = JSON.parse(build.rawMetadata);
  assert.equal(metadata.compiler.version, "0.8.37+commit.f401782d");
  assert.deepEqual(metadata.settings.optimizer, { enabled: true, runs: 200 });
  assert.equal(metadata.settings.evmVersion, "cancun");
  assert.equal(metadata.settings.viaIR ?? false, false);
  const expected = {
    protocolVersion: [[], ["uint16"], "pure"],
    setIssuer: [["bytes32", "address", "bool", "bool"], [], "nonpayable"],
    getIssuer: [["bytes32"], ["address", "bool", "bool"], "view"],
    issue: [["bytes32", "bytes32", "bytes32"], [], "nonpayable"],
    exists: [["bytes32"], ["bool"], "view"],
    getCertificate: [
      ["bytes32"],
      ["bytes32", "bytes32", "uint64", "uint64"],
      "view",
    ],
    revoke: [["bytes32"], [], "nonpayable"],
  };
  for (const [name, signature] of Object.entries(expected)) {
    const item = build.abi.find((e) =>
      e.type === "function" && e.name === name
    );
    assert.deepEqual([
      item.inputs.map((p) => p.type),
      (item.outputs ?? []).map((p) => p.type),
      item.stateMutability,
    ], signature);
  }
  for (
    const [name, types] of Object.entries({
      InvalidInput: [],
      IssuerUnauthorized: ["bytes32", "address"],
      CertificateAlreadyExists: ["bytes32"],
      CertificateNotFound: ["bytes32"],
      CertificateAlreadyRevoked: ["bytes32"],
      RenounceDisabled: [],
      OwnableUnauthorizedAccount: ["address"],
      OwnableInvalidOwner: ["address"],
    })
  ) {
    const item = build.abi.find((e) => e.type === "error" && e.name === name);
    assert.deepEqual(
      item?.inputs.map((p) => p.type),
      types,
      `Wrong error ABI: ${name}`,
    );
  }
  for (
    const [name, fields] of Object.entries({
      IssuerConfigured: [
        ["bytes32", true],
        ["address", true],
        ["bool", false],
        ["bool", false],
      ],
      CertificateIssued: [
        ["bytes32", true],
        ["bytes32", true],
        ["bytes32", false],
        ["address", false],
        ["uint64", false],
      ],
      CertificateRevoked: [["bytes32", true], ["bytes32", true], [
        "address",
        false,
      ], ["uint64", false]],
    })
  ) {
    const item = build.abi.find((e) => e.type === "event" && e.name === name);
    assert.equal(item?.anonymous, false);
    assert.deepEqual(
      item.inputs.map((p) => [p.type, p.indexed]),
      fields,
      `Wrong event ABI: ${name}`,
    );
  }
  assert(
    !build.abi.some((e) =>
      ["fallback", "receive"].includes(e.type) ||
      e.stateMutability === "payable"
    ),
  );
  const abiJson = JSON.stringify(build.abi, null, 2) + "\n";
  const reference = {
    schemaVersion: 1,
    protocolVersion: 1,
    normativeBase: "b6051bc1c0489d84204ee1aae14e3feb7edf30e2",
    compiler: metadata.compiler.version,
    foundry: { version: lock.foundry.version, commit: lock.foundry.commit },
    dependencies: lock.dependencies.map((
      { name, version, commit, sha256 },
    ) => ({ name, version, commit, archiveSha256: sha256 })),
    settings: metadata.settings,
    sources: Object.fromEntries(
      Object.entries(metadata.sources).map((
        [name, entry],
      ) => [name, { keccak256: entry.keccak256 }]),
    ),
    toolchainLockSha256: sha256(
      readFileSync(resolve(root, "toolchain.lock.json")),
    ),
    foundryConfigSha256: sha256(readFileSync(resolve(root, "foundry.toml"))),
    testDynamicLinking: false,
    abiSha256: sha256(Buffer.from(abiJson)),
    creationCodeHash: cast("keccak", build.bytecode.object),
    runtimeCodeHash: cast("keccak", build.deployedBytecode.object),
    runtimeBytes: (build.deployedBytecode.object.length - 2) / 2,
    instrumented: false,
  };
  const directory = resolve(root, "artifacts");
  mkdirSync(directory, { recursive: true });
  for (
    const [name, contents] of [
      ["CertificateRegistry.v1.abi.json", abiJson],
      ["build-reference.json", JSON.stringify(reference, null, 2) + "\n"],
      [
        "manifest.synthetic.example.json",
        JSON.stringify(
          {
            schemaVersion: 1,
            kind: "synthetic-example",
            deployable: false,
            network: "anvil",
            chainId: "31337",
            contractAddress: "0x" + "00".repeat(20),
            protocolVersion: 1,
            runtimeCodeHash: reference.runtimeCodeHash,
            deploymentTransactionHash: "0x" + "00".repeat(32),
            deploymentBlock: { number: "0", hash: "0x" + "00".repeat(32) },
            genesisHash: "0x" + "00".repeat(32),
            environmentId: "SYNTHETIC-NOT-A-DEPLOYMENT",
            versions: {
              foundry: reference.foundry,
              compiler: reference.compiler,
              dependencies: reference.dependencies,
            },
            buildReference: "artifacts/build-reference.json",
            reusableAfterReset: false,
          },
          null,
          2,
        ) + "\n",
      ],
    ]
  ) {
    const path = resolve(directory, name);
    if (check) {
      assert.equal(
        readFileSync(path, "utf8"),
        contents,
        `Generated artifact differs: ${name}`,
      );
    } else writeFileSync(path, contents);
  }
  return { build, reference };
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === resolve(root, "scripts/artifacts.mjs")
) {
  generateArtifacts(process.argv.includes("--check"));
  console.log("Normal-build ABI and source/settings reference verified");
}
