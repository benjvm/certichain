# Phases 4B–4C — Flutter Supabase Authentication and authenticated area

## Configuration and local run

From `mobile/`, supply both compile-time values:

```bash
flutter run --dart-define=SUPABASE_URL=<PROJECT_URL> --dart-define=SUPABASE_PUBLISHABLE_KEY=<PUBLIC_CLIENT_KEY>
```

`AppConfig` rejects missing values, URLs with credentials/query/fragment,
non-HTTPS remote URLs and non-public keys. It accepts publishable keys and legacy
JWT keys with `role=anon`; this is a configuration check, not JWT verification.
Never supply service-role/secret keys, database passwords or blockchain keys.
Dart defines are compiled into the client and must not contain backend secrets.
There is no dotenv dependency, runtime `.env`, hardcoded project URL or real key.
Startup errors never echo supplied values. SDK debug logging is disabled.

Start/inspect Supabase from the repository root:

```bash
npx --yes supabase start
npx --yes supabase status
```

The standalone CLI equivalents are `supabase start` and `supabase status`.
Read the local **publishable/anon** key from status; never commit status output.
Use the URL appropriate to the device, without automatic rewriting:

| Platform | Debug local SUPABASE_URL |
|---|---|
| Windows / web / desktop | `http://127.0.0.1:54321` |
| Android emulator | `http://10.0.2.2:54321` |

```bash
# Desktop/web example; replace the placeholder locally.
flutter run -d chrome --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<LOCAL_PUBLIC_KEY>
# With an Android emulator selected:
flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<LOCAL_PUBLIC_KEY>
```

HTTP is accepted only for loopback/emulator addresses in debug. Staging,
production and non-debug builds require HTTPS. Android's main manifest grants
INTERNET; its debug-only network policy permits HTTP for `127.0.0.1`, `10.0.2.2`
and `localhost`. Release configuration, identifiers, signing and deep links are
unchanged. iOS/macOS local networking has not been configured or verified here.

## Composition and dependency boundary

`main` initializes the Flutter binding, validates `AppConfig`, awaits
`Supabase.initialize`, constructs `SupabaseAuthRepository`, and injects it into
`CertiChainApp`. The official `supabase_flutter` package (resolved to 2.17.2)
provides Auth, refresh and persistence maintained by Supabase. A hand-written
HTTP client would duplicate session management; the Flutter SDK alone has no
Supabase Auth implementation. No other direct runtime dependency was added.

```text
Presentation → AuthRepository (pure Dart) ← SupabaseAuthRepository
                       ↑
              bootstrap injects adapter
```

The domain exposes only a user ID, optional email, expiry, nullable session
stream, signup outcome and stable failure categories. No provider tokens,
User/Session/AuthState types, JSON or role preference cross the domain boundary.
Screens receive the repository by constructor. `AuthController` owns one stream
subscription, an expiry timer, safe error state and logout coordination. It
cancels resources on disposal and ignores late completions. Widgets can be
tested with `FakeAuthRepository` without initializing Supabase.

## Registration contract

Step 1 retains account preference, full name and email. Continue validates and
pushes Step 2, which collects password and confirmation. Back preserves Step 1.
Passwords are required and at least 8 characters; confirmation is required and
must match. No arbitrary character mix is imposed. Both fields have autofill,
Next/Done actions and labelled visibility controls. Supabase remains authoritative.

Submission validates the collected data, trims name/email (never the password),
disables duplicate submission and back navigation, and sends exactly this
application user metadata:

```json
{ "full_name": "Validated user name" }
```

Flutter never inserts into profiles. Phase 4A's trusted trigger validates/trims
the name and inserts exactly one matching profile with `role=holder`. Selecting
Institución remains product intent: no role, institution ID, membership or
authorization claim is sent. The UI explains future institutional onboarding
and approval. No schema, RLS or migrations changed in Phase 4B.

A valid returned session opens the authenticated boundary through the gate.
A user without a session shows neutral confirmation-pending copy and a masked
email with a return to the existing Login route. Passwords are cleared from this
pending form. No synthetic session is created. Local confirmations are disabled
in `supabase/config.toml`; hosted confirmation-required responses are supported.
Automatic deep-link detection is explicitly disabled for this phase.

## Login, session and logout

Login preserves email/password on failure, dismisses the keyboard and blocks
duplicate requests/navigation while loading. Raw SDK errors never reach UI.
Mappings cover invalid credentials, weak password, invalid email, rejected
signup, provisioning/server failure, network failure, detectable timeout,
rate limiting and unknown fallback. Provisioning and rejected signup share a
safe Spanish message. Developers can inspect the `profileProvisioning` enum in
the debugger; it means signup returned an unexpected/server failure, not proof
that a particular SQL statement failed. Do not log raw exceptions or user data.

The gate distinguishes initializing, unauthenticated, authenticated and error.
It inspects the SDK-restored current session and listens for subsequent events,
including refresh, sign-in and sign-out, with an explicit error handler.
An expired session cannot display authenticated content while refresh completes.
Stream errors show a safe retry state and subsequent valid events recover it.
No session opens Welcome; a valid restored session bypasses Welcome/Login.

Auth transitions replace the navigator, discarding old routes and form values.
Token refresh for the same user keeps the navigator. The SDK handles persistence;
there is no second token store. Its default platform storage is used, and should
be reviewed against production device-security requirements before release.

Logout uses Supabase signOut. SDK 2.17 removes its local session *before* its
remote logout request finishes. During logout the controller defers session
events; if the request fails, the adapter restores the still-valid snapshot
through the SDK's `setInitialSession`, which also drives its existing persistence.
No snapshot is written separately or logged. The gate then reads the actual
session and displays a safe failure without claiming logout succeeded. Expired
sessions are never restored as authenticated. Successful logout returns to a
fresh Welcome and removes displayed user data.

## Authenticated area — Phase 4C

`AuthenticatedArea` replaces `TemporaryAuthenticatedScreen`. All authenticated
accounts enter the personal Home, with their backend profile, exact certificate
total, shortcuts and three recent certificates. The bottom navigation opens
Home, My certificates and a read-only Profile. Registration preference grants
no permission and selects no institutional dashboard.

The composition root also injects `ProfileRepository` and `CertificateRepository`.
Both contracts and their entities are pure Dart. Supabase adapters read only
the current identity's profile and holder wallet. See [STUDENT_WALLET.md](STUDENT_WALLET.md)
for queries, states, limits and verification.

The existing session-keyed navigator remains the security boundary. Identity,
expiry, logout and session errors discard the area and its pending UI state.
FutureBuilder ignores superseded completions; the expiry timer also checks its
request generation and mounted state. Same-user token refresh retains the active
tab. Successful logout returns to Welcome; failed logout retains the existing
safe error and real Auth behavior.

Deferred: institutional dashboards/onboarding/approval, profile editing,
password recovery, confirmation deep links, social login, certificate details,
Storage, verification, blockchain and privileged backend operations.

## Verification

From `mobile/`: `dart format .`, `flutter analyze`, `flutter test`.
Ordinary widget tests use a fake repository. Adapter tests use a loopback HTTP
stub (not a Supabase service) and the real SDK; their implicit Auth flow avoids
requiring plugin-backed PKCE storage inside unit tests. Production uses the
SDK's normal Flutter PKCE storage.

An opt-in SDK test in `mobile/test/local_supabase_integration_test.dart` exercises
the real local Auth API. From `mobile/`, obtain the local public key with
`supabase status`, then run:

```bash
flutter test test/local_supabase_integration_test.dart \
  --dart-define=RUN_LOCAL_SUPABASE=true \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<LOCAL_PUBLIC_KEY>
```

Its VM test harness mocks only the SDK's platform preferences channel; Auth
requests reach the real local stack. It recreates `Supabase.initialize` and
checks restored session state after the SDK's asynchronous recovery settles.
It does not prove a physical process restart or browser storage persistence.
Without `RUN_LOCAL_SUPABASE=true`, the test is skipped and performs no request.

Local real-integration checklist (synthetic data only): register a unique test
email through the app; inspect local auth.users and profiles for one matching
row, `holder` and trimmed name; logout; login; restart the app/browser page;
verify the restored boundary; logout again. Do not apply migrations remotely or
commit credentials. Hosted email delivery/deep links are outside this check.

SDK references: [initialization](https://supabase.com/docs/reference/dart/initializing)
and [Auth state/error handling](https://supabase.com/docs/reference/dart/auth-onauthstatechange).
