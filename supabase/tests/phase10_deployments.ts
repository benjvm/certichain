import { keccak256, Wallet } from "ethers";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { sql } from "../scripts/local_supabase.mjs";
import { until } from "./local_issuance_fixture.mjs";
import {
  abi,
  quantity,
} from "../functions/_shared/blockchain/data/evm_registry.ts";
import type { Hex } from "../functions/_shared/blockchain/domain/registry.ts";
import type { phase9dEnvironment } from "./phase9d_environment.ts";

export async function phase10Deployments(
  env: Awaited<ReturnType<typeof phase9dEnvironment>>,
  check: (v: unknown, label: string) => void,
) {
  const { f, backend, rpc } = env;
  const issued = await f.issue(f.owner, {
    institution_id: f.verified,
    holder_id: f.holder.id,
    idempotency_key: crypto.randomUUID(),
    title: "Synthetic previous deployment obligation",
  });
  if (issued.status !== 201) {
    throw new Error("Deployment race publication failed");
  }
  const certificate = issued.data.certificate_id as string;
  const requested = await f.json(
    "/functions/v1/anchor-certificate",
    f.owner.token,
    { certificate_id: certificate, idempotency_key: crypto.randomUUID() },
  );
  const issue = requested.data.operation_id as string;
  try {
    await env.run(issue, false, {
      barrier: (point) => {
        if (point === "stored") throw new Error("HARNESS_CRASH");
        return Promise.resolve();
      },
    });
  } catch (e) {
    if (!(e instanceof Error) || e.message !== "HARNESS_CRASH") throw e;
  }
  const prior = sql(
    `SELECT deployment_id FROM certichain_private.blockchain_operations WHERE id='${issue}'`,
  );
  // A second real deployment uses its own fresh deployer; never the operational EOA.
  const deployer = Wallet.createRandom();
  await rpc.rpc("anvil_setBalance", [
    deployer.address,
    quantity(100000000000000000000n),
  ]);
  const build = JSON.parse(
    readFileSync(
      resolve(
        Deno.env.get("CERTICHAIN_SOURCE_ROOT") ?? Deno.cwd(),
        "blockchain/out/CertificateRegistry.sol/CertificateRegistry.json",
      ),
      "utf8",
    ),
  );
  const raw = await deployer.signTransaction({
    type: 2,
    chainId: 31337n,
    nonce: 0,
    data: build.bytecode.object + abi.encodeDeploy([deployer.address]).slice(2),
    gasLimit: 2000000n,
    maxFeePerGas: 3000000000n,
    maxPriorityFeePerGas: 1000000000n,
  });
  const hash = await rpc.rpc<Hex>("eth_sendRawTransaction", [raw]);
  await until(
    async () => !!await rpc.rpc("eth_getTransactionReceipt", [hash]),
    "Second owned live deployment",
  );
  const receipt = await rpc.rpc<
    { contractAddress: Hex; blockNumber: Hex; blockHash: Hex; status: Hex }
  >("eth_getTransactionReceipt", [hash]);
  check(
    receipt.status === "0x1",
    "10 second real deployment exists while previous issue is signed",
  );
  sql(
    `UPDATE certichain_private.blockchain_deployments SET enabled=false WHERE id='${prior}'`,
  );
  const current = await backend.rpc<string>("blockchain_register_deployment", {
    p_manifest: {
      synthetic: false,
      environmentId: "local",
      network: "anvil",
      chainId: "31337",
      contractAddress: receipt.contractAddress.toLowerCase(),
      protocolVersion: 1,
      genesisHash: env.deployment.genesisHash,
      runtimeCodeHash: keccak256(
        await rpc.rpc<Hex>("eth_getCode", [receipt.contractAddress, "latest"]),
      ),
      deploymentBlock: {
        number: BigInt(receipt.blockNumber).toString(),
        hash: receipt.blockHash,
      },
    },
  });
  try {
    const revoked = await f.json(
      "/functions/v1/revoke-certificate",
      f.owner.token,
      {
        certificate_id: certificate,
        idempotency_key: crypto.randomUUID(),
        reason: "Private original-deployment audit",
      },
    );
    const operation = revoked.data.synchronization[0]?.operation_id as string;
    check(
      revoked.response.status === 202 && operation &&
        sql(
            `SELECT deployment_id FROM certichain_private.blockchain_operations WHERE id='${operation}'`,
          ) === prior,
      "10 revocation locates previous disabled deployment rather than only current enabled one",
    );
    check(
      sql(
        `SELECT count(*) FROM certichain_private.certificate_anchors WHERE certificate_id='${certificate}'`,
      ) === "1",
      "10 deployment switch creates no new anchor or salt",
    );
    sql(
      `UPDATE certichain_private.blockchain_operations SET lease_until=clock_timestamp()-interval '1 second' WHERE id='${issue}'`,
    );
    await env.run(issue);
    await env.run(issue);
    check(
      await env.run(operation) === "authorization_denied",
      "10 disabled original deployment blocks new revoke signature but reconciles late issue",
    );
    check(
      sql(
        `SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id='${operation}'`,
      ) === "0",
      "10 no write redirected to the new contract",
    );
    sql(
      `UPDATE certichain_private.blockchain_deployments SET enabled=false WHERE id='${current}'; UPDATE certichain_private.blockchain_deployments SET enabled=true WHERE id='${prior}'`,
    );
    check(
      (await f.json("/functions/v1/reauthorize-revocation", f.owner.token, {
        operation_id: operation,
      })).response.status === 200,
      "10 explicit review reauthorizes original deployment obligation",
    );
    await env.run(operation);
    await env.run(operation);
    check(
      sql(
            `SELECT state FROM certichain_private.blockchain_operations WHERE id='${operation}'`,
          ) === "confirmed" &&
        sql(
            `SELECT status FROM public.certificates WHERE id='${certificate}'`,
          ) === "revoked",
      "10 original deployment compensation completes without identity substitution",
    );
  } finally {
    sql(
      `UPDATE certichain_private.blockchain_deployments SET enabled=false WHERE id='${current}'; UPDATE certichain_private.blockchain_deployments SET enabled=true WHERE id='${prior}'`,
    );
  }
}
