# Documentation

This directory contains the maintained engineering reference for CertiChain. The [project README](../README.md) introduces the project in English. Detailed domain and operational references are mostly in Spanish.

## Start here

| Guide | Purpose |
|---|---|
| [Development](DEVELOPMENT.md) | Install pinned tools, run the app and manage local environments |
| [Local demo](DEMO_BLOCKCHAIN_LOCAL.md) | Reproduce the complete automated certificate lifecycle |
| [Architecture](ARCHITECTURE.md) | Trust boundaries, components and distributed state |
| [Requirements](REQUIREMENTS.md) | Implemented scope, actors and product constraints |
| [Roadmap](ROADMAP.md) | Remaining work and release limitations |
| [Testing](TESTING.md) | Commands, isolation rules and evidence interpretation |
| [Acceptance](PHASE10_ACCEPTANCE.md) | Current Phase 10E status and verified CI references |

## Technical contracts

| Reference | Purpose |
|---|---|
| [Security](SECURITY.md) | Authorization, privacy, public projection and gateway exception |
| [Database](DATABASE.md) | Versioned schema, RLS and technical functions |
| [Authentication](AUTHENTICATION.md) | Session, registration and configuration contracts |
| [Institution administration](INSTITUTION_ADMINISTRATION.md) | Trusted provisioning, roles and owner invariants |
| [Secure issuance](SECURE_ISSUANCE.md) | PDF validation, private storage, idempotency and document access |
| [Wallet](STUDENT_WALLET.md) | Holder queries, certificate details and sharing |
| [Public verification](PUBLIC_VERIFICATION.md) | Public registry contract, QR and candidate PDF comparison |
| [Blockchain verification](BLOCKCHAIN_VERIFICATION.md) | EVM evidence and authenticated document opening |
| [Revocation](REVOCATION.md) | Irreversible SQL decisions and durable EVM synchronization |
| [Blockchain operations](BLOCKCHAIN_OPERATIONS.md) | Deployment identity, signing, recovery and backups |
| [Protocol v1](PHASE9A_BLOCKCHAIN_SPEC.md) | Normative encodings, commitment and registry protocol |
| [Contract tools](../blockchain/README.md) | Bootstrap, Foundry, artifacts and local Anvil smoke |
| [Flutter architecture](FLUTTER_ARCHITECTURE.md) | Feature modules, adapters and resource ownership |
| [UI foundations](FLUTTER_UI_FOUNDATIONS.md) | Theme, components, semantics and design references |
| [ADRs](ADR_README.md) | Accepted decisions and their rationale |

Phase-by-phase work logs and superseded UI instructions are available in Git history rather than maintained as competing sources of current status. Dated observations in the normative protocol and ADRs retain their original context. Operational instructions and current acceptance take precedence over a historical description of work that was not yet implemented at that time.
