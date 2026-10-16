# Phase notes

## A0 Base — implementation under validation (2026-10-16)

Scaffold iOS 17+ SwiftUI app from XcodeGen and a local SPM API package. Pin the public design submodule to `fd28f825086a2cac7fa297881f1860b9d332db69`. Generate all light/dark semantic color assets, Swift color accessors, branding config and opaque icon from `branding/brand.json`. Keep the owner-supplied contract unchanged and generate only A0 health/refresh operations and dependent types at build time.

Networking uses Apple's generated client and URLSession transport, cookie/credential storage disabled, browser headers removed, validated deployment origin, bearer/makerspace headers, detail/code mapping, Retry-After deadline, same-origin pagination validation and an actor-isolated single-flight refresh skeleton. Refresh uses the generated operation, atomically publishes the pair inside the shared task and fails closed on rotation failure. All redirects are refused. A1 will add real Keychain-backed credentials, attestation and sign-in; the A0 shell has no signed-in state or staff tools.

Compiler integration: Apple's generator 1.10 treats a schema referenced as multipart content as a multipart enum, even when the same schema is also used for JSON. The build projection selects only the refresh endpoint's documented JSON request representation; a test proves every remaining operation, model and field equals the immutable contract. No API fields are invented or edited. URLSession transport 1.1 uses buffered mode so our redirect delegate governs every request. Standard framework detail-only and 400 field errors use defensive dynamic JSON parsing, as specified in the latest owner PRD.

Validation: Python generator/provenance/contrast tests run locally; macOS CI compiles, runs XCTest networking/state/theme tests using URLProtocol fakes, and runs XCUITest main flow, failure, dark mode and Dynamic Type checks. CI status must be green before A0 is called done. UI screenshots are retained in the xcresult artifact. No Mac is available in the authoring environment.

Parity checklist:
- [x] First launch: “Connect to your Space Works server”, “Server URL”, “Connect”, shared helper text; validates generated `/api/v1/health/` before saving.
- [x] Invalid URL, loading, API detail, retryable failure; fixed brand origin cannot be edited; saved/fixed deployment revalidates on launch.
- [x] Home shows “Sign in” / “Sign-in will be available in the next phase.”; no credentials or authentication bypass.
- [x] Home, Inventory, Activity, Inbox, Profile; each has “Nothing here yet.” Staff hidden by default.
- [x] Explicit “Dark mode” / “Light mode” switch; semantic light/dark assets, platform fonts and Dynamic Type, named controls and ≥44 pt buttons.
- [x] Profile offers “Change server” only for an unlocked deployment.
- [x] Shared fallback and special error copy; 24 simultaneous unauthorized calls require exactly one refresh in the URLProtocol fake-server test.

Scope decisions: no A1 work begins before this phase merges. Build-time Python/librsvg/XcodeGen tools do not add app SDKs. No additional analytics or app SDKs. Full schema contains 635 paths and the API prefix; the runtime always supplies a validated origin instead of schema localhost examples. Gilroy app embedding remains an owner licensing decision; use system fonts until cleared. Staging server/accounts are not required for A0's deterministic contract tests and are still owner-supplied for later integration.
