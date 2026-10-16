# Phase notes

## A3 Member actions — implementation checkpoint (2026-10-16)

Add thirteen generated operations for tenant bootstrap, reviewed hardware requests, loan renewal,
space availability/booking/cancellation, event registration/cancellation/ticket QR, account contact
profile and communication preferences. Hardware retries keep an idempotency key for the reviewed
content; editing creates a new attempt. Booking and event receipts preserve server status only,
then refetch Activity for actual booking references and registration IDs. Native QR rendering accepts
only bounded monochrome geometry, never browser content; refusal, cancellation and account scope
invalidation clear ticket content.

Profile edits retain drafts on refusal, require explicit save/discard and survive adaptive layout
reconstruction. Actual bootstrap modules/features gate self-service, preferences and digest controls;
mandatory safety messages remain on while optional feature/channel updates can be disabled. Phone
tabs and tablet sidebar use shared per-destination paths. Product, profile, booking and event drafts
belong to one account/makerspace and are invalidated before changing context. Read and action
Retry-After deadlines survive retries, filters, form reopening and foreground refresh.
Authenticated requests retain an atomic credential/installation epoch: delayed 401s and queued
makerspace operations cannot replay an old account's mutation under a newly installed session,
even when both accounts select the same makerspace. Rotation within one session still coalesces.

Debug actions mutate a separate in-memory store shared with the read repository. The UI can preview
success/refusal/conflict/rate-limit, booking approval and event waitlist outcomes, and never creates
real loans, bookings, tickets or SDK charges. Activate the official pinned Stripe/Razorpay SDK
adapters now for early native compilation; payment list/intent/polling UI is still the A5 checkpoint.
The immutable API contract remains unchanged. The mechanical build projection selects documented
JSON formats and omits malformed optional request-body media declarations for empty POSTs only;
all paths, response schemas and generated model fields stay intact.

The owner's mobile-repository directive moves the mobile UX spec and motion contract to
`docs/mobile-auth-ux-spec.md` and `tokens/mobile-motion.json`. Restore Design to its original
`fd28f825086a2cac7fa297881f1860b9d332db69` brand baseline; new mobile UX work stays in this repo.
Historical UX evidence below still identifies the exact earlier validated commit.

Parity: Review your request / Submit request / Request received; Renew this loan? / Confirm renewal /
Loan renewed; Find a space / Check availability / Submit booking request; Booking request received /
Space booked; Register for this event / Confirm registration; Registration confirmed / Awaiting
approval / You're on the waitlist; View bookings / View registrations; Cancel booking / Keep booking;
Cancel registration / Keep registration; Edit profile / Profile saved.; Communication preferences.
Local generation, immutable contract comparison and source checks pass. Native compiler, URLProtocol,
state, SDK callback and phone/tablet action journey results are pending the A3 CI checkpoint.

## A2 Member read flows — complete (2026-10-16)

Add generated inventory/category/detail, activity, typed bookings, events/spaces, membership card and
inbox operations. Scope every repository request to its selected makerspace before transport and
again before a refresh retry; invalidate protected screen state before changing scope. Pagination
validates origin and API namespace, follows the returned page number and deduplicates results.

Home has loan/due/overdue summaries, bookings, events, notices and currency-preserving dues. Missing
dues remain unavailable, never a fabricated zero. Inventory has search, category filters, pagination,
borrowing terms and a regular-width list/detail layout. Phone tabs and iPad sidebar share the same
destinations; readable dashboard cards adapt to width and accessibility text size. Inbox read actions
refetch confirmed server state and unread badges. Cards clear QR content before loading and on any
refusal; invalidation and request generations prevent late responses from restoring a revoked QR.

The isolated Debug member repository uses synthetic generated DTO fixtures, with populated, empty,
error and revoked-card scenarios. It has no network, token or server-setting writes. Contextual Home
tips can be dismissed and replayed; live preference scope includes server, account and makerspace.
Rendered tablet review also found a UIKit single-line password field stretching into spare vertical
space. Give it an intrinsic fitting height that follows Dynamic Type, and assert its normal-size
height in the existing focus/visibility journey.
Runtime tablet validation passes all 71 native tests and exposed a portrait sidebar overlay covering
selected destinations. Close that overlay after selection while keeping the wide sidebar visible;
assert real detail-control hit testing in the member journeys. Add a synchronous opaque scene
privacy window above presented sheets before app-switcher snapshots, preserving drafts and focus
on return, with lifecycle tests.
The member portrait journeys now pass; keep sidebar visibility tied to the current content width
so rotation restores the wide sidebar. The shared main journey waits for layout hit testing before
using the system sidebar toggle. The focused adaptive regression passes on both phone and tablet, including all snapshot privacy cases.
The owner requested mobile UX work stay in this repository. Copy the auth UX spec and motion
contract into `docs/mobile-auth-ux-spec.md` and `tokens/mobile-motion.json`; update generation and
restore Design's existing `fd28f825086a2cac7fa297881f1860b9d332db69` brand baseline.
Add native file/photo/scanner support for later phases with bounded transfers, credential-free signed
storage requests, QR camera fallback and metadata-stripping JPEG preparation. These helpers do not
claim that later staff or payment flows are wired or live verified.

Parity: Welcome back, {name}.; Active loans / Upcoming bookings / Events / Membership card / Notices;
Search inventory / All categories / Borrowing terms; Requests / Loans / Bookings / Events;
All / Unread / Mark all as read; Nothing here yet.; No items match these filters / Clear filters;
No dues outstanding.; Dues are unavailable. Try again later. Local generation and source checks pass.
Validation: [CI 38945606385](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/38945606385)
passes 73 native tests and 12 UI journeys on each phone and tablet, 14 Python checks, and unsigned
physical-device Release compilation at `0405b95b84f6773832415553867acfafd1694f41`. Rendered iPad portrait,
landscape, Home, inventory/detail and accessibility sign-in screenshots were reviewed. Production
backend and physical camera/file flows remain deferred integration checks.

## UX/onboarding — complete (2026-10-16)

Pin Design `3c615991b40204b74b66f34605ae9364837fbc35`. Add a short optional introduction, installation-scoped skip/completion and Profile replay, static exact stacked/symbol masters at their minimum sizes, native motion generated from the shared JSON, zero custom motion under Reduce Motion, and one licensed Unbounded accent phrase. Body text remains native system type; include the accent font's SIL license and conversion provenance.

Use one native password text input so visibility retains value, selection, focus and autofill. Give current/new/confirmation fields distinct VoiceOver labels, semantic placeholders, multiline announced errors, 48pt actions and bounded phone/tablet forms. Config failures offer retry without guessed methods. Add sign-out confirmation and account/server-scoped makerspace selection preferences.

Add generated account signup, forgot/reset password and authenticated email confirm/resend. Signup/reset acknowledgements never create a session. Reset rejects every server failure with the same copy, with independent local password validation. Shared server/task deadlines survive form dismissal, email editing and reopen; resend waits at least60s or longer Retry-After. Temporary-password completion re-fetches account authority before opening tabs. Unverified email alone does not invent a restricted native session; Profile offers actual verification actions.

Debug provider previews use official Google/Apple controls with injected local actions; no provider credentials/checkout/push/API calls occur. Phone preview has send/code steps, country selection, resend/cooldown, change number, invalid/expired codes and cancellation. Account creation/recovery preview shares the same native form state with isolated closures.

Parity: Make room. / Borrow with confidence. / One place for your making.; Skip introduction, Next, Get started; Connect to your makerspace / Server address / Connect; Welcome back. / Sign in to your makerspace account.; Create your account / Account created; Reset password / Enter your recovery code / Password updated; Confirm your email; Check your authenticator / Add extra security; all five member destinations. Backend-deferred native providers remain closed in production.

Completion evidence: [`4b5dbff` CI38933144741](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/38933144741) passes50 native XCTest cases and8 UI journeys on both phone and iPad,14 Python checks/lint, and the unsigned physical-device Release build. Tablet introduction, recovery, normal sign-in and largest-text dark landscape screenshots were rendered and reviewed. Landscape evidence uses full-screen capture plus a real landscape frame assertion to avoid cropped app-screenshot orientation artifacts. Review found the single-line password-height correction recorded in A2 above; its new regression assertion runs in that checkpoint.

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
tabs, portrait/landscape and semantic light/dark styling. CI supplies the native compiler and
runtime evidence below.

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
