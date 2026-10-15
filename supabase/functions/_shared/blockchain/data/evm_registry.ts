import { Interface, keccak256, Transaction, Wallet } from "ethers";
import {
  type BlockchainRegistry,
  type BlockRef,
  type ChainObservation,
  type Deployment,
  type Fees,
  type Hex,
  type PreparedTx,
  type Receipt,
  type RegistryCommand,
  RegistryError,
  type TransactionObservation,
} from "../domain/registry.ts";
import { bytes, digest } from "../application/commitment.ts";
import { registryAbi, registryRuntimeHash } from "./registry_abi.ts";

interface RpcBlock {
  number: Hex;
  hash: Hex;
  timestamp: Hex;
}
interface RpcLog {
  blockHash: Hex;
  blockNumber: Hex;
  removed: boolean;
  address: string;
  topics: string[];
  data: string;
  logIndex: Hex;
  transactionHash: Hex;
}
interface RpcTransaction {
  hash: Hex;
  from: Hex;
  to: Hex;
  input: Hex;
  nonce: Hex;
  chainId: Hex;
  value: Hex;
  type: Hex;
  gas: Hex;
  maxFeePerGas: Hex;
  maxPriorityFeePerGas: Hex;
  r: Hex;
  s: Hex;
  v: Hex;
}
interface RpcReceipt {
  transactionHash: Hex;
  status: Hex;
  from: Hex;
  to: Hex;
  blockNumber: Hex;
  blockHash: Hex;
  transactionIndex: Hex;
  logs: RpcLog[];
  gasUsed: Hex;
}
export const abi = new Interface(registryAbi);
const lower = (v: string) => v.toLowerCase() as Hex;
export const quantity = (v: bigint) => `0x${v.toString(16)}`;
export function calldata(command: RegistryCommand): Hex {
  const name = command.kind === "set_issuer" ? "setIssuer" : command.kind;
  return lower(
    abi.encodeFunctionData(
      name,
      command.kind === "issue"
        ? [command.K, command.C, command.I]
        : command.kind === "revoke"
        ? [command.K]
        : [command.I, command.signer, command.canIssue, command.canRevoke],
    ),
  );
}
export class EvmRegistry implements BlockchainRegistry {
  deadline = Infinity;
  private wallet: Wallet | null;
  constructor(
    private url: string,
    readonly deployment: Deployment,
    privateKey?: string,
    readonly budget = 10000000000000000n,
  ) {
    this.wallet = privateKey ? new Wallet(privateKey) : null;
    const parsed = new URL(url);
    if (deployment.network === "sepolia" && parsed.protocol !== "https:") {
      throw new RegistryError("deployment_mismatch");
    }
  }
  get signer(): Hex {
    if (!this.wallet) throw new RegistryError("authorization_denied");
    return lower(this.wallet.address);
  }
  async rpc<T>(method: string, params: unknown[] = []): Promise<T> {
    let response: Response;
    try {
      response = await fetch(this.url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(
          Math.max(1, Math.min(10000, this.deadline - Date.now())),
        ),
      });
    } catch (e) {
      throw new RegistryError(
        e instanceof DOMException && e.name === "TimeoutError"
          ? "rpc_timeout"
          : "rpc_unavailable",
      );
    }
    if (!response.ok) throw new RegistryError("rpc_unavailable");
    const result = await response.json();
    if (result.error) {
      const message = String(result.error.message ?? "").toLowerCase();
      if (message.includes("insufficient funds")) {
        throw new RegistryError("insufficient_funds");
      }
      if (
        message.includes("nonce too low") || message.includes("underpriced")
      ) throw new RegistryError("nonce_conflict");
      if (result.error.data) {
        try {
          const decoded = abi.parseError(
            typeof result.error.data === "string"
              ? result.error.data
              : result.error.data.data,
          );
          const codes: Record<string, string> = {
            IssuerUnauthorized: "authorization_denied",
            CertificateAlreadyExists: "duplicate_key",
            CertificateAlreadyRevoked: "already_revoked",
            CertificateNotFound: "key_conflict",
            InvalidInput: "invalid_input",
          };
          if (decoded && codes[decoded.name]) {
            throw new RegistryError(
              codes[decoded.name] as RegistryError["code"],
            );
          }
        } catch (e) {
          if (e instanceof RegistryError) throw e;
        }
      }
      throw new RegistryError(
        message.includes("revert") ? "transaction_reverted" : "rpc_unavailable",
      );
    }
    if (!("result" in result)) throw new RegistryError("rpc_unavailable");
    return result.result as T;
  }
  async block(tag: string): Promise<RpcBlock> {
    const block = await this.rpc<RpcBlock | null>("eth_getBlockByNumber", [
      tag,
      false,
    ]);
    if (!block) throw new RegistryError("rpc_unavailable");
    return block;
  }
  ref(block: RpcBlock): BlockRef {
    return { number: BigInt(block.number), hash: lower(block.hash) };
  }
  async canonical(ref: BlockRef) {
    const current = await this.rpc<RpcBlock | null>("eth_getBlockByNumber", [
      quantity(ref.number),
      false,
    ]);
    if (!current) {
      // A null alone proves nothing. A successful, stable canonical head below
      // the formerly validated inclusion does prove that block is now orphaned.
      const head = await this.block("latest");
      if (
        BigInt(head.number) >= ref.number ||
        lower((await this.block(quantity(BigInt(head.number)))).hash) !==
          lower(head.hash)
      ) throw new RegistryError("rpc_unavailable");
      throw new RegistryError("reorg");
    }
    if (lower(current.hash) !== ref.hash) {
      throw new RegistryError("reorg");
    }
  }
  async call(name: string, args: unknown[], block: BlockRef) {
    await this.canonical(block);
    const result = await this.rpc<Hex>("eth_call", [{
      to: this.deployment.contractAddress,
      data: abi.encodeFunctionData(name, args),
    }, quantity(block.number)]);
    const decoded = abi.decodeFunctionResult(name, result);
    await this.canonical(block);
    return decoded;
  }
  async validateDeployment(expected: Deployment): Promise<ChainObservation> {
    if (
      expected.runtimeCodeHash !== registryRuntimeHash ||
      expected.deploymentBlock.number < 1n || !expected.environmentId
    ) throw new RegistryError("deployment_mismatch");
    if (
      expected.environmentId !== this.deployment.environmentId ||
      expected.protocolVersion !== 1 ||
      (expected.network === "anvil"
        ? expected.chainId !== 31337n
        : expected.chainId !== 11155111n)
    ) throw new RegistryError("deployment_mismatch");
    const chain = await this.rpc<Hex>("eth_chainId");
    const genesis = await this.block("0x0");
    const deployed = await this.rpc<RpcBlock | null>("eth_getBlockByNumber", [
      quantity(expected.deploymentBlock.number),
      false,
    ]);
    if (!deployed) throw new RegistryError("deployment_mismatch");
    const head = this.ref(await this.block("latest"));
    const code = await this.rpc<Hex>("eth_getCode", [
      expected.contractAddress,
      quantity(head.number),
    ]);
    if (
      BigInt(chain) !== expected.chainId ||
      lower(genesis.hash) !== expected.genesisHash ||
      lower(deployed.hash) !== expected.deploymentBlock.hash ||
      lower(keccak256(code)) !== expected.runtimeCodeHash ||
      (await this.call("protocolVersion", [], head))[0] !== 1n
    ) throw new RegistryError("deployment_mismatch");
    let finalized: BlockRef | null = null;
    if (expected.network === "sepolia") {
      try {
        finalized = this.ref(await this.block("finalized"));
      } catch (e) {
        if (!(e instanceof RegistryError && e.code === "rpc_unavailable")) {
          throw e;
        }
      }
    }
    await this.canonical(head);
    return { head, finalized, checkedAt: new Date().toISOString() };
  }
  async read(K: Hex, block: BlockRef) {
    if (!(await this.call("exists", [K], block))[0]) return null;
    const r = await this.call("getCertificate", [K], block);
    return {
      K,
      C: lower(r[0]),
      I: lower(r[1]),
      registeredAt: r[2] as bigint,
      revokedAt: r[3] as bigint,
    };
  }
  async issuer(I: Hex, block: BlockRef) {
    const r = await this.call("getIssuer", [I], block);
    return {
      signer: lower(r[0]),
      canIssue: r[1] as boolean,
      canRevoke: r[2] as boolean,
    };
  }
  async nonce() {
    const latest = BigInt(
      await this.rpc<Hex>("eth_getTransactionCount", [this.signer, "latest"]),
    );
    const pending = BigInt(
      await this.rpc<Hex>("eth_getTransactionCount", [this.signer, "pending"]),
    );
    return { latest, pending };
  }
  async latestNonce(signer: Hex) {
    return BigInt(
      await this.rpc<Hex>("eth_getTransactionCount", [signer, "latest"]),
    );
  }
  async owner(block: BlockRef) {
    return lower((await this.call("owner", [], block))[0]);
  }
  async fees(command: RegistryCommand, previous?: Fees): Promise<Fees> {
    const data = calldata(command);
    await this.rpc("eth_call", [{
      from: this.signer,
      to: this.deployment.contractAddress,
      data,
      value: "0x0",
    }, "latest"]);
    const estimate = BigInt(
      await this.rpc<Hex>("eth_estimateGas", [{
        from: this.signer,
        to: this.deployment.contractAddress,
        data,
        value: "0x0",
      }, "latest"]),
    );
    const price = BigInt(await this.rpc<Hex>("eth_gasPrice"));
    let tip = 1000000000n, fee = price * 2n + tip;
    if (previous) {
      tip = (previous.maxPriorityFeePerGas * 120n + 99n) / 100n;
      const raised = (previous.maxFeePerGas * 120n + 99n) / 100n;
      if (fee < raised) fee = raised;
    }
    const gasLimit = (estimate * 120n + 99n) / 100n;
    if (gasLimit > 1000000n || gasLimit * fee > this.budget) {
      throw new RegistryError("insufficient_funds");
    }
    if (
      BigInt(await this.rpc<Hex>("eth_getBalance", [this.signer, "latest"])) <
        gasLimit * fee
    ) throw new RegistryError("insufficient_funds");
    return { gasLimit, maxFeePerGas: fee, maxPriorityFeePerGas: tip };
  }
  async prepare(
    command: RegistryCommand,
    nonce: bigint,
    fees: Fees,
  ): Promise<PreparedTx> {
    await this.validateDeployment(this.deployment);
    if (!this.wallet || nonce < 0n || nonce > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new RegistryError("nonce_conflict");
    }
    if (fees.gasLimit * fees.maxFeePerGas > this.budget) {
      throw new RegistryError("insufficient_funds");
    }
    const data = calldata(command);
    const raw = lower(
      await this.wallet.signTransaction({
        type: 2,
        chainId: this.deployment.chainId,
        nonce: Number(nonce),
        to: this.deployment.contractAddress,
        data,
        value: 0n,
        ...fees,
      }),
    );
    const tx = Transaction.from(raw);
    if (
      lower(tx.from!) !== this.signer ||
      tx.chainId !== this.deployment.chainId ||
      lower(tx.to!) !== this.deployment.contractAddress || tx.data !== data ||
      tx.value !== 0n
    ) throw new RegistryError("incompatible_evidence");
    return {
      ...fees,
      hash: lower(keccak256(raw)),
      rawSignedTx: raw,
      chainId: tx.chainId,
      to: this.deployment.contractAddress,
      signer: this.signer,
      nonce,
      data,
      calldataDigest: await digest(bytes(data)),
    };
  }
  async broadcast(prepared: PreparedTx) {
    if (lower(keccak256(prepared.rawSignedTx)) !== prepared.hash) {
      throw new RegistryError("incompatible_evidence");
    }
    const transactionHash = lower(
      await this.rpc<Hex>("eth_sendRawTransaction", [prepared.rawSignedTx]),
    );
    if (transactionHash !== prepared.hash) {
      throw new RegistryError("incompatible_evidence");
    }
    return { transactionHash };
  }
  async observe(hash: Hex): Promise<TransactionObservation> {
    const receipt = await this.rpc<RpcReceipt | null>(
      "eth_getTransactionReceipt",
      [hash],
    );
    const tx = await this.rpc<RpcTransaction | null>(
      "eth_getTransactionByHash",
      [hash],
    );
    if (!receipt) return { kind: tx ? "pending" : "unknown" };
    if (
      !tx || lower(receipt.transactionHash) !== hash || lower(tx.hash) !== hash
    ) throw new RegistryError("incompatible_evidence");
    const block = {
      number: BigInt(receipt.blockNumber),
      hash: lower(receipt.blockHash),
    };
    await this.canonical(block);
    const chain = await this.validateDeployment(this.deployment);
    const timestamp = BigInt(
      (await this.block(quantity(block.number))).timestamp,
    );
    if (
      BigInt(tx.chainId) !== this.deployment.chainId ||
      BigInt(tx.type) !== 2n || BigInt(tx.value) !== 0n ||
      lower(receipt.from) !== lower(tx.from) ||
      lower(receipt.to) !== this.deployment.contractAddress ||
      lower(tx.to) !== this.deployment.contractAddress
    ) throw new RegistryError("incompatible_evidence");
    const status = BigInt(receipt.status);
    if (status !== 0n && status !== 1n) {
      throw new RegistryError("incompatible_evidence");
    }
    return {
      kind: "included",
      chain,
      receipt: {
        hash,
        status: Number(status) as 0 | 1,
        from: lower(tx.from),
        to: lower(tx.to),
        block,
        transactionIndex: BigInt(receipt.transactionIndex),
        logIndex: null,
        timestamp,
        data: lower(tx.input),
        nonce: BigInt(tx.nonce),
        gasUsed: BigInt(receipt.gasUsed),
      },
    };
  }
  async validateEvidence(
    command: RegistryCommand,
    receipt: Receipt,
    expectedSigner: Hex,
  ): Promise<Receipt> {
    if (receipt.from !== expectedSigner || receipt.data !== calldata(command)) {
      throw new RegistryError("incompatible_evidence");
    }
    if (receipt.status === 0) return receipt;
    const raw = await this.rpc<RpcReceipt>("eth_getTransactionReceipt", [
      receipt.hash,
    ]);
    const matching = raw.logs.filter((log) =>
      lower(log.address) === this.deployment.contractAddress &&
      lower(log.transactionHash) === receipt.hash &&
      lower(log.blockHash) === receipt.block.hash &&
      BigInt(log.blockNumber) === receipt.block.number && !log.removed
    ).filter((log) => {
      try {
        const event = abi.parseLog(log);
        if (!event) return false;
        const a = event.args;
        if (command.kind === "issue") {
          return event.name === "CertificateIssued" &&
            lower(a.certificateKey) === command.K &&
            lower(a.issuerId) === command.I &&
            lower(a.commitment) === command.C &&
            lower(a.signer) === receipt.from &&
            a.registeredAt === receipt.timestamp;
        }
        if (command.kind === "set_issuer") {
          return event.name === "IssuerConfigured" &&
            lower(a.issuerId) === command.I &&
            lower(a.signer) === command.signer &&
            a.canIssue === command.canIssue &&
            a.canRevoke === command.canRevoke;
        }
        return event.name === "CertificateRevoked" &&
          lower(a.certificateKey) === command.K &&
          lower(a.signer) === receipt.from && a.revokedAt === receipt.timestamp;
      } catch {
        return false;
      }
    });
    if (matching.length !== 1) throw new RegistryError("incompatible_evidence");
    if (command.kind === "issue") {
      const record = await this.read(command.K, receipt.block);
      if (
        !record || record.C !== command.C || record.I !== command.I ||
        record.registeredAt !== receipt.timestamp
      ) throw new RegistryError("divergence");
    } else if (command.kind === "revoke") {
      const record = await this.read(command.K, receipt.block);
      if (
        !record || record.revokedAt !== receipt.timestamp ||
        record.registeredAt <= 0n || record.registeredAt > record.revokedAt
      ) throw new RegistryError("incompatible_evidence");
      const event = abi.parseLog(matching[0]);
      if (!event || lower(event.args.issuerId) !== record.I) {
        throw new RegistryError("incompatible_evidence");
      }
    } else if (command.kind === "set_issuer") {
      const issuer = await this.issuer(command.I, receipt.block);
      if (
        issuer.signer !== command.signer ||
        issuer.canIssue !== command.canIssue ||
        issuer.canRevoke !== command.canRevoke
      ) throw new RegistryError("incompatible_evidence");
    }
    await this.canonical(receipt.block);
    return { ...receipt, logIndex: BigInt(matching[0].logIndex) };
  }
  async findIssue(K: Hex, from: bigint, head: bigint) {
    return await this.findEvent("CertificateIssued", K, from, head);
  }
  async findRevoke(K: Hex, from: bigint, head: bigint) {
    return await this.findEvent("CertificateRevoked", K, from, head);
  }
  private async findEvent(
    event: "CertificateIssued" | "CertificateRevoked",
    K: Hex,
    from: bigint,
    head: bigint,
  ) {
    const to = from + 1999n < head ? from + 1999n : head;
    const logs = await this.rpc<RpcLog[]>("eth_getLogs", [{
      address: this.deployment.contractAddress,
      fromBlock: quantity(from),
      toBlock: quantity(to),
      topics: [abi.getEvent(event)!.topicHash, K],
    }]);
    if (logs.length > 1) throw new RegistryError("divergence");
    return { hash: logs[0]?.transactionHash ?? null, cursor: to + 1n };
  }
  async recoverPrepared(hash: Hex): Promise<PreparedTx> {
    const r = await this.rpc<RpcTransaction>("eth_getTransactionByHash", [
      hash,
    ]);
    if (BigInt(r.nonce) > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new RegistryError("nonce_conflict");
    }
    const tx = Transaction.from({
      type: 2,
      chainId: BigInt(r.chainId),
      nonce: Number(BigInt(r.nonce)),
      to: r.to,
      data: r.input,
      value: BigInt(r.value),
      gasLimit: BigInt(r.gas),
      maxFeePerGas: BigInt(r.maxFeePerGas),
      maxPriorityFeePerGas: BigInt(r.maxPriorityFeePerGas),
      signature: { r: r.r, s: r.s, yParity: Number(BigInt(r.v)) as 0 | 1 },
    });
    if (lower(tx.hash!) !== hash || !tx.from) {
      throw new RegistryError("incompatible_evidence");
    }
    return {
      hash,
      rawSignedTx: lower(tx.serialized),
      chainId: tx.chainId,
      to: lower(tx.to!),
      signer: lower(tx.from),
      nonce: BigInt(tx.nonce),
      data: lower(tx.data),
      calldataDigest: await digest(bytes(lower(tx.data))),
      gasLimit: tx.gasLimit,
      maxFeePerGas: tx.maxFeePerGas!,
      maxPriorityFeePerGas: tx.maxPriorityFeePerGas!,
    };
  }
}
