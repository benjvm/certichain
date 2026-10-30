# CertiChain Flutter application

The app uses feature-first `presentation → domain ← data` boundaries. Flutter **3.47.4** / Dart **3.13.3** and lockfiles match CI. Start with the [project README](../README.md) and [development setup](../docs/DEVELOPMENT.md).

```powershell
$env:CERTICHAIN_TEST_CAMERA='0'
flutter pub get --enforce-lockfile
npm ci --ignore-scripts --prefix tool
node tool/prepare_decoder.mjs --check
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

Run from this directory with public configuration:

```sh
flutter run -d chrome --web-hostname=localhost --web-port=7357 --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_LOCAL_ANON_KEY --dart-define=PUBLIC_VERIFICATION_BASE_URL=http://localhost:7357
```

Start local Supabase/Functions first. Dart defines must never contain service-role or EVM keys. Non-debug builds require HTTPS; use the [complete local demo](../docs/DEMO_BLOCKCHAIN_LOCAL.md) for release/Anvil acceptance.

The public client uses v3 and keeps registry status, issue/revoke evidence and local document integrity separate. Private capabilities and openings are explicitly requested and discarded on session changes. Camera implementation remains available, but camera tests are SKIP/NOT_RUN by user instruction; static QR decoding, manual codes, links and PDF checks stay covered.

See [Flutter architecture](../docs/FLUTTER_ARCHITECTURE.md), [UI foundations](../docs/FLUTTER_UI_FOUNDATIONS.md), [wallet](../docs/STUDENT_WALLET.md) and [testing](../docs/TESTING.md).
