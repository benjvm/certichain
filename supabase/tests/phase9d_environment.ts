// Trusted test infrastructure, never imported by Flutter or an Edge endpoint.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { keccak256, Wallet } from "ethers";
import { fixture, until } from "./local_issuance_fixture.mjs";
import { assertDisposableStack, sql } from "../scripts/local_supabase.mjs";
import { BlockchainBackend } from "../functions/_shared/blockchain/data/backend.ts";
import {
  abi,
  calldata,
  EvmRegistry,
  quantity,
} from "../functions/_shared/blockchain/data/evm_registry.ts";
import {
  bytes,
  digest,
  hex,
} from "../functions/_shared/blockchain/application/commitment.ts";
import {
  coordinate,
  type CoordinatorOptions,
  deployment,
} from "../functions/_shared/blockchain/application/coordinator.ts";
import type {
  Deployment,
  Hex,
} from "../functions/_shared/blockchain/domain/registry.ts";

export async function phase9dEnvironment() {
  assertDisposableStack();
  if (Deno.env.get("CERTICHAIN_TEST_CAMERA") !== "0") {
    throw new Error("Camera must be disabled");
  }
  const listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
  const port = listener.addr.port;
  listener.close();
  const project = /^project_id\s*=\s*"([^"]+)"/m.exec(
    readFileSync("supabase/config.toml", "utf8"),
  )![1];
  const edge = `supabase_edge_runtime_${project}`;
  const name = `certichain-9d-anvil-${crypto.randomUUID()}`,
    network = `${name}-network`;
  const docker = (args: string[]) => {
    const r = spawnSync("docker", args, {
      encoding: "utf8",
      timeout: 30000,
      windowsHide: true,
    });
    if (r.status !== 0) throw new Error("Owned Docker action failed");
    return r.stdout.trim();
  };
  const image = docker(["inspect", edge, "--format", "{{.Image}}"]);
  const executable = Deno.env.get("CERTICHAIN_ANVIL_BIN") ??
    resolve("blockchain/.tools/bin/anvil");
  let connected = false, started = false, created = false;
  let f: Awaited<ReturnType<typeof fixture>> | null = null;
  const close = () => {
    if (connected) {
      docker(["network", "disconnect", network, edge]);
      connected = false;
    }
    if (started) {
      docker(["rm", "-f", name]);
      started = false;
    }
    if (created) {
      docker(["network", "rm", network]);
      created = false;
    }
    f?.stopRuntime();
  };
  try {
    docker(["network", "create", network]);
    created = true;
    docker([
      "run",
      "-d",
      "--name",
      name,
      "--network",
      network,
      "--network-alias",
      "anvil",
      "--publish",
      `127.0.0.1:${port}:8545`,
      "--mount",
      `type=bind,source=${
        resolve(executable, "..")
      },target=/opt/phase9d,readonly`,
      "--entrypoint",
      "/opt/phase9d/anvil",
      image,
      "--host",
      "0.0.0.0",
      "--port",
      "8545",
      "--chain-id",
      "31337",
      "--hardfork",
      "cancun",
      "--timestamp",
      String(Math.floor(Date.now() / 1000)),
    ]);
    started = true;
    const rpcUrl = `http://127.0.0.1:${port}`;
    const rpc = new EvmRegistry(rpcUrl, { network: "anvil" } as Deployment);
    await until(
      async () => {
        try {
          return await rpc.rpc("eth_chainId") === "0x7a69";
        } catch {
          return false;
        }
      },
      "Owned Anvil ready",
      15000,
    );
    const admin = Wallet.createRandom(),
      signer = Wallet.createRandom(),
      deployer = Wallet.createRandom();
    for (const wallet of [admin, signer, deployer]) {
      await rpc.rpc("anvil_setBalance", [
        wallet.address,
        quantity(100000000000000000000n),
      ]);
    }
    const root = Deno.env.get("CERTICHAIN_SOURCE_ROOT") ?? Deno.cwd();
    const build = JSON.parse(
      readFileSync(
        resolve(
          root,
          "blockchain/out/CertificateRegistry.sol/CertificateRegistry.json",
        ),
        "utf8",
      ),
    );
    const raw = await deployer.signTransaction({
      type: 2,
      chainId: 31337n,
      nonce: 0,
      data: build.bytecode.object + abi.encodeDeploy([admin.address]).slice(2),
      gasLimit: 2000000n,
      maxFeePerGas: 3000000000n,
      maxPriorityFeePerGas: 1000000000n,
    });
    const hash = await rpc.rpc<Hex>("eth_sendRawTransaction", [raw]);
    type DeploymentReceipt = {
      contractAddress: Hex;
      blockNumber: Hex;
      blockHash: Hex;
      status: Hex;
    };
    await until(async () => {
      return !!await rpc.rpc("eth_getTransactionReceipt", [hash]);
    }, "Owned live deployment");
    const receipt = await rpc.rpc<DeploymentReceipt | null>(
      "eth_getTransactionReceipt",
      [hash],
    );
    if (!receipt || receipt.status !== "0x1") {
      throw new Error("Live deployment failed");
    }
    const manifest = {
      synthetic: false,
      environmentId: "local",
      network: "anvil" as const,
      chainId: "31337",
      contractAddress: receipt.contractAddress.toLowerCase() as Hex,
      protocolVersion: 1 as const,
      genesisHash: (await rpc.block("0x0")).hash,
      runtimeCodeHash: keccak256(
        await rpc.rpc<Hex>("eth_getCode", [receipt.contractAddress, "latest"]),
      ) as Hex,
      deploymentBlock: {
        number: BigInt(receipt.blockNumber).toString(),
        hash: receipt.blockHash,
      },
    };
    const d: Deployment = {
      ...manifest,
      chainId: 31337n,
      deploymentBlock: {
        number: BigInt(manifest.deploymentBlock.number),
        hash: manifest.deploymentBlock.hash,
      },
    };
    f = await fixture("http://anvil:8545");
    docker(["network", "connect", network, edge]);
    connected = true;
    const backend = new BlockchainBackend(
      f.local.API_URL,
      f.local.SERVICE_ROLE_KEY,
    );
    sql(
      "UPDATE certichain_private.blockchain_deployments SET enabled=false WHERE enabled;",
    );
    const dep = await backend.rpc<string>("blockchain_register_deployment", {
      p_manifest: manifest,
    });
    const I = hex(crypto.getRandomValues(new Uint8Array(32)));
    const command = {
      kind: "set_issuer" as const,
      I,
      signer: signer.address.toLowerCase() as Hex,
      canIssue: true,
      canRevoke: true,
    };
    const administrative = await backend.rpc<string>(
      "blockchain_configure_issuer",
      {
        p_actor: f.platform.id,
        p_deployment: dep,
        p_institution: f.verified,
        p_i: I,
        p_signer: command.signer,
        p_issue: true,
        p_revoke: true,
        p_payload: await digest(bytes(calldata(command))),
        p_key: crypto.randomUUID(),
      },
    );
    const run = async (
      id: string,
      adminMode = false,
      options: CoordinatorOptions = {},
    ) => {
      if (!/^[0-9a-f-]{36}$/.test(id)) {
        throw new Error("Invalid owned operation");
      }
      sql(
        `UPDATE certichain_private.blockchain_operations SET next_attempt_at=clock_timestamp()-interval '1 second' WHERE id='${id}';`,
      );
      return await coordinate(
        backend,
        id,
        (j) =>
          new EvmRegistry(
            rpcUrl,
            deployment(j),
            adminMode ? admin.privateKey : signer.privateKey,
          ),
        { ...options, admin: adminMode },
      );
    };
    await run(administrative, true);
    await run(administrative, true);
    await new EvmRegistry(rpcUrl, d).validateDeployment(d);
    if (
      sql(
        `SELECT sync_state FROM certichain_private.blockchain_issuers WHERE deployment_id='${dep}'`,
      ) !== "synced"
    ) throw new Error("Issuer configuration not reconciled");
    return {
      f,
      backend,
      rpc,
      registry: new EvmRegistry(rpcUrl, d, signer.privateKey),
      deployment: d,
      run,
      restartWorker: (id: string) => {
        if (!/^[0-9a-f-]{36}$/.test(id)) {
          throw new Error("Invalid owned operation");
        }
        sql(
          `UPDATE certichain_private.blockchain_operations SET next_attempt_at=clock_timestamp()-interval '1 second' WHERE id='${id}';`,
        );
        const worker = spawnSync(Deno.execPath(), [
          "run",
          "--allow-env",
          "--allow-net",
          "--frozen",
          "--config",
          "supabase/functions/deno.json",
          "supabase/admin/blockchain.ts",
          "worker",
          id,
        ], {
          encoding: "utf8",
          windowsHide: true,
          timeout: 40000,
          maxBuffer: 65536,
          env: {
            ...Deno.env.toObject(),
            SUPABASE_URL: backend.url,
            SUPABASE_SERVICE_ROLE_KEY: f!.local.SERVICE_ROLE_KEY,
            EVM_RPC_URL: rpcUrl,
            EVM_SIGNER_PRIVATE_KEY: signer.privateKey,
            EVM_ADMIN_PRIVATE_KEY: "",
            EVM_MAX_COST_WEI: "10000000000000000",
          },
        });
        if (worker.status !== 0) {
          throw new Error("Owned restarted CLI worker failed");
        }
        const result = JSON.parse(worker.stdout.trim());
        if (result.operation_id !== id || typeof result.result !== "string") {
          throw new Error("Invalid restarted worker result");
        }
        return result.result as string;
      },
      close,
      pause: () => docker(["pause", name]),
      unpause: () => docker(["unpause", name]),
    };
  } catch (e) {
    close();
    throw e;
  }
}
