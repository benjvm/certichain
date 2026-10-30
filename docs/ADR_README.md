# Architecture Decision Records

Accepted ADRs preserve the rationale behind decisions that are expensive to reverse. Keep their historical context; a new structural decision should supersede and link an earlier ADR rather than erase its reasoning. Implementation status is maintained in [acceptance](PHASE10_ACCEPTANCE.md) and [roadmap](ROADMAP.md).

| ADR | Decision |
|---|---|
| [0007](adr/0007-managed-institution-administration.md) | Managed institutional onboarding and controlled SQL mutations |
| [0008](adr/0008-private-issuance-reservations.md) | Persistent issuance reservation and private PDF storage |
| [0009](adr/0009-leased-private-issuance.md) | Leases, publication and terminal cleanup |
| [0010](adr/0010-institutional-client-and-document-capabilities.md) | Institutional client and short-lived document capabilities |
| [0011](adr/0011-public-registry-verification.md) | Restricted public registry projection and shared budget |
| [0012](adr/0012-public-web-navigation-and-credential-sharing.md) | Public Web navigation and authorized sharing |
| [0013](adr/0013-public-candidate-hash-and-qr-scanning.md) | Local candidate hashing and QR scanning |
| [0014](adr/0014-evm-network-toolchain-and-authority.md) | EVM network, reproducible tools and registry authority |
| [0015](adr/0015-private-commitments-and-durable-anchoring.md) | Private commitments and durable anchoring |
| [0016](adr/0016-durable-evm-adapter-and-reverted-nonce.md) | Durable EVM adapter and consumed/reverted nonces |
| [0017](adr/0017-public-blockchain-evidence-and-private-opening.md) | Public EVM evidence and authenticated opening |
| [0018](adr/0018-irreversible-revocation-and-public-v3.md) | Irreversible revocation, v3 evidence and the limited JWT gateway exception |

The early proposed numbers 0001–0006 were never created; do not add empty records just to fill numbering gaps. The normative commitment/registry protocol remains [Protocol v1](PHASE9A_BLOCKCHAIN_SPEC.md).

## Convention

Use `NNNN-short-title.md`. States: `proposed`, `accepted`, `superseded`, `rejected`. Include status, date, context, decision, alternatives, consequences and validation. Reserve an ADR for a real structural choice; routine fixes and documentation cleanup do not require a new decision record.
