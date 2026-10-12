// Pure protocol types. No runtime, database or EVM library imports.
export type Hex = `0x${string}`;
export interface BlockRef {
  number: bigint;
  hash: Hex;
}
export interface Deployment {
  environmentId: string;
  network: "anvil" | "sepolia";
  chainId: bigint;
  contractAddress: Hex;
  protocolVersion: 1;
  runtimeCodeHash: Hex;
  deploymentBlock: BlockRef;
  genesisHash: Hex;
}
export interface ChainObservation {
  head: BlockRef;
  finalized: BlockRef | null;
  checkedAt: string;
}
export type RegistryCommand =
  | { kind: "issue"; K: Hex; C: Hex; I: Hex }
  | { kind: "revoke"; K: Hex }
  | {
    kind: "set_issuer";
    I: Hex;
    signer: Hex;
    canIssue: boolean;
    canRevoke: boolean;
  };
export interface Fees {
  gasLimit: bigint;
  maxFeePerGas: bigint;
  maxPriorityFeePerGas: bigint;
}
export interface PreparedTx extends Fees {
  hash: Hex;
  rawSignedTx: Hex;
  chainId: bigint;
  to: Hex;
  signer: Hex;
  nonce: bigint;
  calldataDigest: Hex;
  data: Hex;
}
export interface RegistryRecord {
  K: Hex;
  C: Hex;
  I: Hex;
  registeredAt: bigint;
  revokedAt: bigint;
}
export interface IssuerConfiguration {
  signer: Hex;
  canIssue: boolean;
  canRevoke: boolean;
}
export interface Receipt {
  hash: Hex;
  status: 0 | 1;
  from: Hex;
  to: Hex;
  block: BlockRef;
  transactionIndex: bigint;
  logIndex: bigint | null;
  timestamp: bigint;
  data: Hex;
  nonce: bigint;
  gasUsed: bigint;
}
export type TransactionObservation =
  | { kind: "unknown" | "pending" }
  | { kind: "included"; receipt: Receipt; chain: ChainObservation };
export type ErrorCode =
  | "invalid_input"
  | "authorization_denied"
  | "duplicate_key"
  | "already_revoked"
  | "key_conflict"
  | "rpc_unavailable"
  | "rpc_timeout"
  | "insufficient_funds"
  | "nonce_conflict"
  | "transaction_reverted"
  | "deployment_mismatch"
  | "incompatible_evidence"
  | "reorg"
  | "divergence"
  | "opening_unavailable"
  | "busy";
export class RegistryError extends Error {
  constructor(readonly code: ErrorCode) {
    super(code);
  }
}
export interface BlockchainRegistry {
  validateDeployment(expected: Deployment): Promise<ChainObservation>;
  prepare(
    command: RegistryCommand,
    nonce: bigint,
    fees: Fees,
  ): Promise<PreparedTx>;
  broadcast(prepared: PreparedTx): Promise<{ transactionHash: Hex }>;
  observe(hash: Hex): Promise<TransactionObservation>;
  read(K: Hex, block: BlockRef): Promise<RegistryRecord | null>;
  issuer(I: Hex, block: BlockRef): Promise<IssuerConfiguration>;
}
// Concrete coordinator needs these operational queries; all values remain pure.
export interface OperationalRegistry extends BlockchainRegistry {
  deadline: number;
  readonly signer: Hex;
  canonical(block: BlockRef): Promise<void>;
  nonce(): Promise<{ latest: bigint; pending: bigint }>;
  latestNonce(signer: Hex): Promise<bigint>;
  owner(block: BlockRef): Promise<Hex>;
  fees(command: RegistryCommand, previous?: Fees): Promise<Fees>;
  validateEvidence(
    command: RegistryCommand,
    receipt: Receipt,
    signer: Hex,
  ): Promise<Receipt>;
  findIssue(
    K: Hex,
    from: bigint,
    head: bigint,
  ): Promise<{ hash: Hex | null; cursor: bigint }>;
  recoverPrepared(hash: Hex): Promise<PreparedTx>;
}
