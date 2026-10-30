# Development setup

Run commands from the repository root unless a different directory is shown. The Flutter application, Supabase project and Solidity registry already exist; do not recreate them with `flutter create`, `supabase init` or `forge init`.

## Pinned prerequisites

| Tool | Pin / requirement |
|---|---|
| Flutter | 3.47.4, commit `9584c6713b324636289d067944a46fd6b49df14b` |
| Dart | 3.13.3, bundled with Flutter |
| Node.js | 24.14.0, as in `../.node-version` |
| Supabase CLI | 2.117.0 |
| Deno | 2.2.12, invoked through pinned `npx` commands |
| Contract tools | Foundry 1.8.5, Solidity 0.8.37; installed by `blockchain/scripts/bootstrap.mjs` |
| Runtime | Docker with Linux containers, PowerShell 7+, Chrome/Chromium |
| Utilities | Git, `tar`, OpenSSL; Git for Windows includes the default Windows OpenSSL executable |

Install Node 24.14.0 using your version manager or [its versioned distribution](https://nodejs.org/download/release/v24.14.0/). Obtain the [standalone Supabase CLI 2.117.0 release](https://github.com/supabase/cli/releases/tag/v2.117.0) for your OS, extract it outside the checkout and add its directory to `PATH`. The runner expects that exact CLI version. Global npm installation of Supabase is not the setup used here.

One way to install the Flutter SDK outside the project is:

```sh
git clone --depth 1 --branch 3.47.4 https://github.com/flutter/flutter.git ../flutter-sdk
git -C ../flutter-sdk rev-parse HEAD
```

Verify the revision against the table and add `../flutter-sdk/bin` to your shell's `PATH`. Install [PowerShell 7](https://github.com/PowerShell/PowerShell#get-powershell) separately on Linux. On Windows, use a PowerShell 7 terminal and Docker Desktop's Linux engine. The contract bootstrap supports Windows x64 and Linux x64; macOS reproduction is not validated.

```sh
node --version
npm --version
supabase --version
flutter --version
docker version
pwsh --version
```

On Windows, an older `npm`/`npx` launcher can use its adjacent Node executable even when `node` on `PATH` is correct. Select one coherent Node installation for all three commands. Do not disable engine or version checks to bypass a mismatch. `SUPABASE_CLI` can point to the exact standalone executable if multiple installations exist.

## Resolve dependencies

```sh
cd mobile
flutter pub get --enforce-lockfile
npm ci --ignore-scripts --prefix tool
node tool/prepare_decoder.mjs --check
cd ..
node blockchain/scripts/bootstrap.mjs
```

The committed offline decoder must match its generator and npm lock. When deliberately updating it, run `node mobile/tool/prepare_decoder.mjs` and review the generated diff. Do not edit generated decoder, ABI or build-reference files manually.

## Interactive app

1. Start Docker, then `supabase start` from the root. This starts the local project defined in `supabase/config.toml`, applies migrations to a new database and uses API port 54321.
2. Run `supabase functions serve` in that terminal.
3. In another terminal, read the local public client key with `supabase status`. Do not save or publish the full status output, which also includes backend credentials.
4. From `mobile/`, launch:

```sh
flutter run -d chrome --web-hostname=localhost --web-port=7357 --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_LOCAL_ANON_KEY --dart-define=PUBLIC_VERIFICATION_BASE_URL=http://localhost:7357
```

Replace the public-key placeholder locally. `SUPABASE_URL` points to the API; `PUBLIC_VERIFICATION_BASE_URL` points to the Web app, not an Edge Function. Public URLs use `/#/verify/<credential_code>`. The Android emulator API address is `http://10.0.2.2:54321`. HTTP loopback/emulator access is a debug-only allowance; release builds require HTTPS.

Register real local Auth identities through the app. Fresh seeds contain no shared credentials or administrators. Provision platform and institutional roles using the reviewed procedure in [institution administration](INSTITUTION_ADMINISTRATION.md). A registration preference never grants institutional access. Password recovery, social login and self-service institutional approval are not implemented.

To exercise EVM features interactively, use a live deployment and issuer binding, set the backend's read RPC, and run the trusted worker according to [blockchain operations](BLOCKCHAIN_OPERATIONS.md). A manifest from a discarded Anvil instance cannot configure a new session. The [automated demo](DEMO_BLOCKCHAIN_LOCAL.md) provisions all of this for a temporary environment.

Stop your interactive project with `supabase stop` when finished. `supabase db reset --local` deletes local data: use it only for a project whose data you intend to discard.

## Automated isolated environments

```sh
pwsh -NoProfile -File ./supabase/tests/run_phase10.ps1 -VisibleBrowser
```

This resolves dependencies and runs the complete acceptance suite. The preparer creates a new project outside the checkout, using API/database ports 55321/55322. Chrome uses HTTPS port 7360. Anvil has its own network and loopback port. Keep those ports available without stopping unrelated services. Run mutable suites sequentially.

`-BackendOnly` omits Flutter requirements and Web evidence. `CHROME_EXECUTABLE` and `OPENSSL_EXECUTABLE` can override executable discovery. Interrupted disposable stacks can be stopped with:

```powershell
./supabase/tests/stop_disposable_local.ps1 -Root EXACT_DIRECTORY_RETURNED_BY_PREPARER
```

Only remove resources belonging to that execution. Do not clear global temporary directories or reset the ordinary development stack to fix a test.

## Changes and environments

- Use a short branch, focused commits and a reviewable PR.
- Add a new migration for schema, function or RLS changes; never edit a shared migration.
- Run the affected checks in [TESTING](TESTING.md), and update the relevant contract and ADR when a structural decision changes.
- Keep secrets in backend/CI environment configuration. Flutter receives only public configuration.
- Local demo acceptance does not authorize a hosted deployment. Staging and production require separate projects, keys, backups and operational review.
