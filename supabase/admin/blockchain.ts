// Explicit trusted operator CLI. Never served by Edge; no cron or HTTP worker.
import { BlockchainBackend } from "../functions/_shared/blockchain/data/backend.ts";
import {
  calldata,
  EvmRegistry,
} from "../functions/_shared/blockchain/data/evm_registry.ts";
import {
  bytes,
  digest,
} from "../functions/_shared/blockchain/application/commitment.ts";
import {
  coordinate,
  deployment,
} from "../functions/_shared/blockchain/application/coordinator.ts";
import {
  type Deployment,
  type Hex,
} from "../functions/_shared/blockchain/domain/registry.ts";
function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing ${name}`);
  return v;
}
export async function main(args: string[]) {
  const backend = new BlockchainBackend(
    env("SUPABASE_URL"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
  );
  const [mode, ...rest] = args;
  if (mode === "register") {
    const manifest = JSON.parse(await Deno.readTextFile(rest[0]));
    if (manifest.synthetic !== false) {
      throw new Error("Synthetic manifest rejected");
    }
    const d: Deployment = {
      ...manifest,
      chainId: BigInt(manifest.chainId),
      deploymentBlock: {
        number: BigInt(manifest.deploymentBlock.number),
        hash: manifest.deploymentBlock.hash,
      },
    };
    await new EvmRegistry(env("EVM_RPC_URL"), d).validateDeployment(d);
    console.log(
      JSON.stringify({
        deployment_id: await backend.rpc("blockchain_register_deployment", {
          p_manifest: manifest,
        }),
      }),
    );
  } else if (mode === "configure") {
    const [actor, dep, institution, I, signer, issue, revoke, key] = rest;
    const cmd = {
      kind: "set_issuer" as const,
      I: I as Hex,
      signer: signer as Hex,
      canIssue: issue === "true",
      canRevoke: revoke === "true",
    };
    console.log(JSON.stringify({
      operation_id: await backend.rpc("blockchain_configure_issuer", {
        p_actor: actor,
        p_deployment: dep,
        p_institution: institution,
        p_i: I,
        p_signer: signer,
        p_issue: cmd.canIssue,
        p_revoke: cmd.canRevoke,
        p_key: key,
        p_payload: await digest(bytes(calldata(cmd))),
      }),
    }));
  } else if (mode === "worker" || mode === "admin-worker") {
    const admin = mode === "admin-worker";
    if (!admin && Deno.env.get("EVM_ADMIN_PRIVATE_KEY")) {
      throw new Error("Ordinary worker must not receive administrator key");
    }
    const key = env(admin ? "EVM_ADMIN_PRIVATE_KEY" : "EVM_SIGNER_PRIVATE_KEY");
    const deadline = Date.now() + 30000;
    backend.deadline = deadline;
    const ids = rest[0]
      ? [rest[0]]
      : await backend.rpc<string[]>("blockchain_queue", { p_limit: 10 });
    for (const id of ids) {
      if (Date.now() >= deadline) break;
      const result = await coordinate(
        backend,
        id,
        (job) =>
          new EvmRegistry(
            env("EVM_RPC_URL"),
            deployment(job),
            key,
            BigInt(env("EVM_MAX_COST_WEI")),
          ),
        { admin, deadline },
      );
      console.log(JSON.stringify({ operation_id: id, result }));
    }
  } else if (mode === "reauthorize") {
    console.log(
      JSON.stringify(
        await backend.rpc("blockchain_reauthorize", {
          p_actor: rest[0],
          p_operation: rest[1],
        }),
      ),
    );
  } else if (mode === "close-local") {
    await backend.rpc("blockchain_close_local", { p_operation: rest[0] });
  } else if (mode === "purge-raw") {
    console.log(
      JSON.stringify({ purged: await backend.rpc("blockchain_purge_raw") }),
    );
  } else {throw new Error(
      "Use register MANIFEST | configure ACTOR DEPLOYMENT INSTITUTION I SIGNER ISSUE REVOKE KEY | worker [OP] | admin-worker [OP] | reauthorize ACTOR OP | close-local OP | purge-raw",
    );}
}
if (import.meta.main) {
  await main(Deno.args).catch(() => {
    console.error(
      "Blockchain command failed; inspect private state with authorized operator tools.",
    );
    Deno.exit(1);
  });
}
