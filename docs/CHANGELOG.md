# Phase notes

## A1 Sign-in — implementation checkpoint (2026-10-16)

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
