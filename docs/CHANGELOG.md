# Phase notes

## UX/onboarding — implementation checkpoint (2026-10-16)

Pin Design `3c615991b40204b74b66f34605ae9364837fbc35`. Add a short optional introduction, installation-scoped skip/completion and Profile replay, static exact stacked/symbol masters at their minimum sizes, native motion generated from the shared JSON, zero custom motion under Reduce Motion, and one licensed Unbounded accent phrase. Body text remains native system type; include the accent font's SIL license and conversion provenance.

Use one native password text input so visibility retains value, selection, focus and autofill. Give current/new/confirmation fields distinct VoiceOver labels, semantic placeholders, multiline announced errors, 48pt actions and bounded phone/tablet forms. Config failures offer retry without guessed methods. Add sign-out confirmation and account/server-scoped makerspace selection preferences.

Add generated account signup, forgot/reset password and authenticated email confirm/resend. Signup/reset acknowledgements never create a session. Reset rejects every server failure with the same copy, with independent local password validation. Shared server/task deadlines survive form dismissal, email editing and reopen; resend waits at least60s or longer Retry-After. Temporary-password completion re-fetches account authority before opening tabs. Unverified email alone does not invent a restricted native session; Profile offers actual verification actions.

Debug provider previews use official Google/Apple controls with injected local actions; no provider credentials/checkout/push/API calls occur. Phone preview has send/code steps, country selection, resend/cooldown, change number, invalid/expired codes and cancellation. Account creation/recovery preview shares the same native form state with isolated closures.

Parity: Make room. / Borrow with confidence. / One place for your making.; Skip introduction, Next, Get started; Connect to your makerspace / Server address / Connect; Welcome back. / Sign in to your makerspace account.; Create your account / Account created; Reset password / Enter your recovery code / Password updated; Confirm your email; Check your authenticator / Add extra security; all five member destinations. Backend-deferred native providers remain closed in production. Local14 Python checks/lint pass; new native/network/UI tests remain gated on macOS CI before this checkpoint is complete. Landscape evidence uses full-screen capture plus a real landscape frame assertion to avoid cropped app-screenshot orientation artifacts.

## A1 Sign-in — complete (2026-10-16)

Add generated password/attestation, `/auth/me`, configuration, native MFA verify/enroll/confirm and
logout operations. Store the whole token pair in a server-scoped, non-synchronizing, device-only
Keychain item. Refresh persists synchronously before any waiting request can retry. Logout clears
local credentials even if remote revocation cannot be confirmed. Foreground identity refresh clears
revoked sessions; superadmins are refused. Only direct memberships reach the switcher; staff authority
remains closed until backend 1a. Real devices use a fresh App Attest key and SHA-256 challenge;
Debug simulators use the PRD's development proof. Apple provisioning remains an owner dependency.

The native flow includes password visibility, MFA enrollment QR/manual secret, recovery-code
acknowledgement, makerspace selection, profile/sign-out, constrained forms, iPad sidebar and phone
tabs, portrait/landscape and semantic light/dark styling. CI is the compiler; this phase is not
complete until its new auth/network/UI tests pass. Local generation's six tests and source lint pass.

Completion evidence: [`f7f414e` CI38927362309](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/38927362309) passed phone and iPad simulator builds with40 XCTest cases and5 main UI journeys each,10 Python generation/matrix checks, and the unsigned physical-device Release build. The actual Keychain round trip remains enabled and passes. These are contract-fixture/compiler results; real App Attest/provider/APNs/payment and owner-backend verification remain release gates.

Parity: Email or username, Password, Sign in; Verify your sign-in / Set up two-step sign-in;
Authenticator or recovery code, Verify, Back to sign in; I saved my codes. Continue;
Choose a makerspace; You haven’t joined a makerspace yet.; Profile, Sign out, Change server.
Native MFA completion requires access, refresh and a device grant, rejecting browser-only completion.
The original contract lacks native provider/version configuration, OIDC device callback delivery and
staff authority. These remain tracked backend requests, not invented payloads. The owner deferred
the backend and requested isolated Debug demo flows for planned features; see the implementation plan
and local Docker evidence. All documented JSON request variants are mechanically selected for the
build projection; every source path, schema, field and response stays unchanged.

The Debug-only “Explore demo” entry has a persistent “Demo mode · sample data” banner and exit/reset.
Its member Meera Nair and staff Arjun Rao journeys cover password validation, MFA rejection/success,
enrollment QR/manual secret, recovery-code acknowledgement and two-space selection, with no API,
Keychain or server-setting writes. Add default phone/iPad CI jobs and a six-size manual matrix;
UI flows rotate to landscape and exercise the largest Dynamic Type/dark state. The official logo
masters are copied byte-for-byte into adaptive native image assets for the official app name.
Add the mandatory temporary-password gate, native Google SDK/Apple authorization/ephemeral OIDC
adapter seams, and explicit demo provider/phone, expired/offline/throttled/superadmin/update-required
journeys. Live provider buttons stay closed pending native configuration/contracts; no web tokens
are treated as device sessions. Provider setup is recorded in `docs/NATIVE-SDK-SETUP.md`.

CI integration: the unsigned simulator app could not access Keychain. Give simulator builds an
ad-hoc signed, local-only application/access-group identity; physical-device entitlements continue
to come from owner provisioning. Keep the actual Keychain round-trip test and add a generation test
that proves the simulator identity cannot enter a device archive. Keyboard Next/Done focus is
explicit in both live and demo forms so tablet keyboards never cover the password action.

## A0 Base (2026-10-16)

Scaffold iOS 17+ SwiftUI app from XcodeGen and a local SPM API package. Pin the public design submodule to `fd28f825086a2cac7fa297881f1860b9d332db69`. Generate all light/dark semantic color assets, Swift color accessors, branding config and opaque icon from `branding/brand.json`. Keep the owner-supplied contract unchanged and generate only A0 health/refresh operations and dependent types at build time.

Networking uses Apple's generated client and URLSession transport, cookie/credential storage disabled, browser headers removed, validated deployment origin, bearer/makerspace headers, detail/code mapping, Retry-After deadline, same-origin pagination validation and an actor-isolated single-flight refresh skeleton. Refresh uses the generated operation, atomically publishes the pair inside the shared task and fails closed on rotation failure. All redirects are refused. A1 will add real Keychain-backed credentials, attestation and sign-in; the A0 shell has no signed-in state or staff tools.

Compiler integration: Apple's generator 1.10 treats a schema referenced as multipart content as a multipart enum, even when the same schema is also used for JSON. The build projection selects only the refresh endpoint's documented JSON request representation; a test proves every remaining operation, model and field equals the immutable contract. No API fields are invented or edited. URLSession transport 1.1 uses buffered mode so our redirect delegate governs every request. Standard framework detail-only and 400 field errors use defensive dynamic JSON parsing, as specified in the latest owner PRD.

Validation: six Python generator/provenance/contrast/Release-ATS tests and repository lint run locally and in CI. macOS CI compiles and runs 19 XCTest networking/state/theme tests using URLProtocol fakes plus three XCUITest flows covering connect, every member tab, server failure, dark mode and Dynamic Type. The native navigation and tab bar appearances bind adaptive semantic colors, with contrast assertions for normal/selected labels and icons in every tab layout and both color schemes. The [development CI checks](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions?query=branch%3Adev) are the completion gate: A0 is complete only when all checks pass without skipped tests. The workflow exports UI PNGs and retains the xcresult artifact. No Mac is available in the authoring environment.

Parity checklist:
- [x] First launch: “Connect to your Space Works server”, “Server URL”, “Connect”, shared helper text; validates generated `/api/v1/health/` before saving.
- [x] Invalid URL, loading, API detail, retryable failure; fixed brand origin cannot be edited; saved/fixed deployment revalidates on launch.
- [x] Home shows “Sign in” / “Sign-in will be available in the next phase.”; no credentials or authentication bypass.
- [x] Home, Inventory, Activity, Inbox, Profile; each has “Nothing here yet.” Staff hidden by default.
- [x] Explicit “Dark mode” / “Light mode” switch; semantic light/dark assets, platform fonts and Dynamic Type, named controls and ≥44 pt buttons.
- [x] Profile offers “Change server” only for an unlocked deployment.
- [x] Shared fallback and special error copy; 24 simultaneous unauthorized calls require exactly one refresh in the URLProtocol fake-server test.

Scope decisions: no A1 work begins before this phase merges. Build-time Python/librsvg/XcodeGen tools do not add app SDKs. No additional analytics or app SDKs. Full schema contains 635 paths and the API prefix; the runtime always supplies a validated origin instead of schema localhost examples. Gilroy app embedding remains an owner licensing decision; use system fonts until cleared. Staging server/accounts are not required for A0's deterministic contract tests and are still owner-supplied for later integration.

## Development branch workflow (2026-10-16)

The owner made the repository public and merged A0 through PR #1, including the native appearance fixes. `dev` starts from the merged `main` commit `cb9154134e527ee1c5abf15d853a4c3ccac187c5`. Ongoing work is committed and pushed on `dev`; its final pull request targets `main` after validation. The workflow is recorded in `AGENTS.md` and the README.

The final source suite contains six Python tests, repository lint, 19 XCTest cases and three UI flows. [Development CI](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions?query=branch%3Adev) validates this branch before the final pull request. This documentation update preserves the merged application source.
