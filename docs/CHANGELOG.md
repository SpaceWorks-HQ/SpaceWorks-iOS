# Phase notes

## B4 Native interaction feedback and bounded onboarding motion — implementation checkpoint (2026-10-18)

Explicit onboarding Back/Next actions now request native selection feedback; completion/Skip requests completion feedback. Only its existing page content uses the finite 200ms motion token, with a small eight-point fade/offset transition. The logo stays static. Real Reduce Motion (and the clearly scoped Debug test preference) removes that custom transition. Navigation stacks, tabs, sheets, native bars and system activities keep their native animation and stable ownership; no navigation-host identity or repeating effects are added.

Feedback follows explicit owned operation outcomes: sign-in/MFA challenges and required-security steps are progression; success requires an accepted current credential installation and identity. Restoring/refreshing identity is quiet. Fresh request receipts, recorded handovers and confirmed attendance can request success; QR resolution is selection, not attendance. Current form validation/refusals request error; recovery-code delivery remains generic progression. Payment SDK submission, polling, uploads, background restoration and ordinary navigation never announce success. Form feedback is delivered only while its owning view remains present, with no guaranteed haptic after a verification callback dismisses that view. The platform controls whether supported hardware actually provides feedback.

Each event is tied to the native activation epoch, retired synchronously on willResignActive and replaced on didBecomeActive. A callback deferred until foreground cannot replay an earlier/background event; newly mounted views do not emit an initial event. Existing operation generations/credential checks suppress retired results, and form dismissal retires its feedback revision. Three authored native cases cover native notification lifecycle/deferred delivery, an in-flight closed form, cancellation and local validation. Existing authentication, email-owner, request and staff regressions now also assert current feedback, quiet refresh and invalidated/replacement suppression. These validate event ownership, not a physical device sensation.

A separate regular-text dark landscape sign-in journey reuses the unchanged strict action visibility checks and retains a full-OS capture for the wide tablet logo ground; the original largest-text journey is unchanged. Intended final totals are 302 native/37 UI/42 Python. Local source validation is recorded separately; exact Apple compilation, all six native profiles, unsigned Release/font bundle audit and actual new-source captures remain mandatory before acceptance. Parity: platform-native feedback accompanies explicit progression/results, typography remains the supplied family, all auth/member/staff actions and backend authority stay unchanged.

## B3 Brand conformance and supported checkout typography — implementation checkpoint (2026-10-18)

The owner rule in the pinned brand specification requires IDs and secrets to use the UI family with tabular digits. Five remaining rows now use the actual Gilroy Medium face with digit-only tabular spacing; values, selection and privacy handling are unchanged. This corrects B1's retained monospace exception. The wide auth panel now uses the paired semantic surface/ink ground, so its adaptive supplied full-color/reversed master remains legible in both appearances; the former fixed citron ground selected a reversed cream logo in dark mode. No logo is recolored, redrawn or distorted.

Stripe's pinned 26.14.0 public Appearance API now receives an unscaled registered Gilroy base. Its own font-size, weight-resolution and Dynamic Type behavior remain in control, with the existing colors, shapes and checkout authority/callback semantics preserved. The supplied app font tables are unchanged; no promise is made that the SDK resolves all four separately named app faces. Razorpay's existing supported theme color remains unchanged; no unsupported font key is invented. One authored native test inspects the actual Stripe appearance under default and accessibility traits to guard against double scaling. Intended totals are 299 native/36 UI/42 Python; exact Apple compilation/runtime, native SDK configuration and full current-source visual/Release proof remain pending. The Debug metadata writer now explicitly uses UTF-8.

## B2 Native orientation evidence and compact action framing — diagnostic checkpoint (2026-10-18)

The exact 3d3 compact recording showed slow short reveal gestures leave the two actions at alternating positions or with the primary control's upper edge behind the fixed header. The test now targets the center of their combined frame within the actual visible viewport, using its available interior slack. The existing 24-attempt limit, full-control bounds, enabled/hittable foreground checks, clear gutter, capped slow gesture/end hold, far native swipes and all outcomes remain unchanged. No app reachability or UIKit threshold cause is claimed.

A DEBUG-only, explicitly UI-test-enabled zero-size background view records bounded existing controller masks, device/scene orientation and window geometry. It never creates a controller/window, changes policy, forces geometry, generates device notifications or schedules timers. Weak mount guards remove observers on teardown. The test retains its original 10-second actual geometry assertion and logs pre-request/cached post-predicate frames. The canonical workflow reads the actual built Debug Info.plist, records exact checked-out source/profile/fonts/scene/orientations, and refuses invalid family/orientation/single-scene metadata. It archives only the diagnostic logger's exact subsystem/category over the bounded job window; no broad app content log is exported. This observes the still-unexplained rotation failures rather than treating a passing repeat as a causal fix. No test case or timeout is removed or enlarged. Native compilation and exact current-source execution remain required.

## B1 Full brand typography and native iOS navigation — implementation checkpoint (2026-10-18)

The owner requested full Space Works branding with platform-native iOS navigation. App content now uses the supplied Gilroy Regular/Medium/Semibold/Bold faces, converted from the pinned Design WOFF containers without changing glyph, name or metric tables. Recorded hashes and table comparisons preserve provenance. The upstream weight metadata is 400 for every supplied face, so the shared type system selects each actual PostScript face explicitly. Semantic iOS type styles scale through Dynamic Type; Bold Text chooses a heavier real face. The UIKit password field refreshes with type-size and legibility changes. Monospaced security/reference text, provider identity controls, symbol glyphs, system activities and native navigation geometry retain their platform behavior. Unbounded remains a single short accent phrase. The accessibility Start here heading/action stack avoids the observed narrow Dismiss word break.

On iOS 26 and newer, native navigation/tab appearances keep the system's Liquid Glass and scroll-edge material, with semantic action tint. The earlier semantic opaque appearance remains for iOS 17–25. This follows Apple's TN3106 and Adopting Liquid Glass guidance; no custom glass cards, navigation replacements, API changes, logo edits or palette changes are introduced.

Validation at this checkpoint: generation and 42 Python checks pass, including original/native table equality and both configuration font registration; source lint and diff hygiene pass. Four new authored native cases exercise actual font loading/glyphs, UIKit accessibility scaling, native legibility traits, and a hosted password-field font refresh. Intended totals are 298 native/36 UI; Apple compilation, all six runtime profiles, unsigned Release/font bundle audit and actual current-source full-OS review remain required. The legibility test uses explicit native traits and does not claim to change the OS Bold Text setting. Parity: supplied Gilroy weights, primary/secondary roles, semantic brand palette and static masters match Android; navigation remains native to each platform.

## A8 Usage guide and release handoff — implementation checkpoint (2026-10-17)

The exact `5205d18` compact-auth diagnostic passed portrait capture but correctly failed the strict landscape guard after 24 reveal attempts. Actual native event logs and the recording showed a 45.5-point adjustment use the default 500-pixel-per-second drag and release into a much larger scroll, alternating between the header-obscured action and a position beyond the second action. The same small gutter adjustment now uses the existing native slow-drag/0.3-second end-hold pattern already used by shared journey helpers, preventing that default release fling. The visible-region, noninteractive gutter, full-control/readiness requirements, 24-attempt budget and all app source remain unchanged. Corrected exact-source native execution and both actual full-OS captures remain required; this is not an accepted result from the failed diagnostic.

The exact `601a8fe` compact-auth diagnostic passed its one native UI case and showed complete Create account labels with normal word boundaries in both orientations. Actual landscape review nevertheless found Sign in partly behind the fixed appearance header: the accessibility ScrollView frame included that painted header region. The existing test now subtracts the actual header control extent from its visible-content region and makes a small bounded adjustment in an asserted noninteractive scroll gutter when a full native swipe overshoots. Complete Sign in/Create account frames, enabled/hittable controls, foreground app state and the 24-attempt budget remain mandatory. No app layout, action, system-UI dismissal or outcome assertion changed. This is an additional capture-readiness correction after a passing diagnostic, and both corrected full-OS images still require native review.

The old `64f5e75` large-phone log showed an opened Data export destination disappear after rotation, leaving the backing Account screen; another request rotation lost its local review presentation. Source review found both live and demo shells switched their entire TabView/NavigationSplitView branch on horizontal size class. Typed route models survived, while inline child navigation and sheet state belonged to the replaced branch. Both shells now keep a device-stable host: phones retain TabView and tablets retain native NavigationSplitView, with an explicit preferred detail column for collapsed windows and tab changes. Existing typed paths, account/makerspace cleanup, capabilities, width-based sidebar visibility and compact inventory selection conversion are unchanged. This removes the demonstrated structural state-lifetime risk; existing export/request rotation outcomes remain strict, and focused native execution plus resized-tablet/phone full-OS review are still required.

The old `64f5e75` compact profile passed all 294 native tests and 36 UI journeys, but actual full-OS review found Create account split inside a word beside New here? at the largest accessibility text size. That row now stacks vertically at accessibility sizes with a full-width native Create account action; normal-size layout, full type scale and the existing sign-up handler remain unchanged. The named landscape sign-in capture showed an OS clock/blur overlay instead of the app, so it is not accepted as app visual proof. The existing dark/largest-text journey now reveals both complete native actions within the identified sign-in ScrollView using bounded native swipes, checks real app/control readiness before each capture, and preserves orientation, username and sign-in assertions. This removes whole-app gestures from that capture path without dismissing system UI or assuming its cause. Corrected-source native execution and actual full-OS review remain required.

The old `64f5e75` phone profile completed all 294 native tests, 36 UI journeys and the unsigned physical-device Release build, then failed the strict packaged-resource audit because its scene manifest did not explicitly disable multiple scenes. The generator already writes that false flag for both configurations, but the project enabled Xcode automatic scene-manifest generation; Apple documents that setting as producing a multi-window manifest. The project now disables that override so the explicit generated manifest remains authoritative. Existing generation checks verify both false flags and the disabled override; the unchanged strict bundle audit also records the actual packaged scene manifest for diagnosis. Corrected-source Debug/Release build and actual-bundle audit proof remain required.

The current `64f5e75` large-tablet profile passed all native and UI cases, but its actual largest-text membership alert screenshot showed the cancel-role Keep membership label internally clipped to Keep/member-. Complete action frames did not prove complete native label rendering. The two existing decisions now use the concise native actions Leave or Stop renewal and Cancel, preserving captured decision, destructive/cancel roles and server mutation logic. The existing membership journey now exercises cancellation of both decisions, verifies the retained reason and active membership, confirms renewal cancellation while membership remains active, and finally confirms leaving with the unchanged remaining-membership outcome. Both native controls receive complete positive alert/app bounds and hittability checks before every dialog capture. This is a real visual correction after passing tests; complete corrected-source native and full-OS visual validation remain required.

The normal `4e72fb2` tablet gate passed all 294 native tests and 35 of 36 UI journeys. Its phone-account journey tapped Account and security, then queried a transient zero-frame ScrollView for hittability while navigation was still settling; XCTest rejected that container's activation point. The actual recording and final accessibility snapshot show the correct Account destination and phone entry. Account setup now waits for the retained outgoing entry to disappear and the actual destination navigation bar before continuing. Both identical scroll-container selectors reject nonfinite, zero-size or offscreen geometry before asking for hittability. Selector priority, fallback behavior, the 24-attempt budget and every native activation/outcome assertion are preserved. This is transition-safe test readiness, not an app-account defect claim or proof that separate accessibility snapshots are atomic. Complete corrected exact-head native/UI/Release and visual gates remain required.

The `547282b` focused large-phone diagnostic passed seven of eight selected UI cases, including both rotation cases, MFA, deletion, recovery, guide and event coverage. Its payment recording showed a second held reveal gesture pressing the confirmed choice and dismissing the sheet before the intended canceled action was reached; the final accessibility snapshot correctly showed that accidentally selected confirmed result. The payment helper now uses native swipes on the same identified sheet ScrollView instead of synthesized held coordinate drags. The 24-attempt direction loop, complete intended-action bounds, final direct native tap and all canceled/pending/retry/PDF assertions remain unchanged. This test-only correction needs the focused payment diagnostic before the complete exact-head matrix; it changes no app payment state or provider behavior.

A bounded test-source followthrough replaces the same untyped navigation query and generic sidebar match in the remaining Main, guide, member, payment and staff setup helpers. Live and demo navigation attach these identifiers to actual native Buttons; each helper now waits for that enabled, hittable button and may open only a verified Show Sidebar or Toggle Sidebar action. Existing tab-bar paths, native final taps and all journey outcomes are retained. This follows the demonstrated Notifications helper failure and matching source structure; it does not claim every helper independently failed. No app behavior, cases or gesture budgets change; focused native and complete exact-head validation remain required.

The later `6505723` large-phone checkpoint passed all 294 native cases but failed 14 of 36 UI journeys. Actual logs and full-OS media show several distinct interaction problems: fixed half-budget scroll reversal moved known Account, guide and event targets away before they became reachable; a partially exposed recovery Toggle stayed unacknowledged; an MFA tap landed on the phone's bottom edge; and a demo-payment reveal gesture activated a different outcome. Test helpers now follow finite target geometry, fully reveal and verify recovery acknowledgment, focus the visible MFA field, and drag inside the payment sheet's padding. The native activation, gesture budgets and downstream outcomes remain intact. Notifications now queries the actual native sidebar button and never closes an already-open sidebar through a generic Hide Sidebar match.

The landscape email-verification recording showed its numeric keyboard covering the action without a usable dismissal control. Account access now provides a focus-only native Done action above its scroll content; its existing journey verifies the filled code, the complete real Done frame and keyboard dismissal before the unchanged confirmation. No account operation or submission behavior changes. Post-launch rotation checks now await actual app geometry with the existing launch-policy bound (Notifications retains its five-second bound); the old Notifications rotation wait also timed out, so readiness alone is not claimed to resolve the orientation mechanism. A focused native diagnostic and the complete corrected matrix remain required. A7 at actual `3193b08` has separately passed its 285 native/34 UI and Release gate; this A8 checkpoint is not acceptance. Counts remain 294 native/36 UI/40 Python with 781 English keys.

The `6505723` checkpoint exposed three further concrete readiness/presentation issues. Phone booking reached the correct destination, but helper enumeration still held an outgoing discovery ScrollView; the journey now waits for that selected link to disappear and the actual booking title before reading destination geometry. A successful large-tablet screenshot showed the membership destructive label clipped inside a confirmation popover; that existing two-choice decision now uses a native alert with captured presenting data and strict whole-action alert bounds in its test. Normal-tablet Profile setup now waits for the actual enabled native button and only a verified Show/Toggle Sidebar action before continuing. These preserve every outcome and use no sleeps or retries.

The tablet renewal recording showed a native center tap and pressed feedback without a result or error. Renewal now mirrors the existing request form: its action is stable when no cooldown exists, and a periodic view exists only for a real retry deadline. Busy/deadline disabling, the operation and result are unchanged. This removes unnecessary periodic redraw; a causal link to the lost press is not established. The existing native tap and Loan renewed assertion remain, with a pre-activation screenshot for direct evidence. Full corrected native/UI/Release and visual acceptance remain required.

The `0cab1e6` large-tablet checkpoint passed all 294 native cases and 35/36 UI journeys. Its actual largest-text recording showed the native demo payment popover compressing labels and hiding the fourth outcome below its action viewport. Only the Debug outcome picker now uses a large, scrollable native sheet with the same four outcomes and no-money/no-SDK disclaimer; choosing an outcome dismisses the sheet before the unchanged asynchronous simulation. Release/provider/payment-state behavior is unchanged. The existing UI helper reveals the actual identified sheet content with a bounded gesture budget, then retains positive, fully visible, hittable native action checks and the unchanged pending/PDF assertions. Two title keys are now seeded in the English catalog, bringing it to 781 keys. The complete corrected native/UI/Release matrix is still required.

Existing inventory, staff and account-keyboard journeys now retain named full-OS screenshots immediately before their already-required native activations. These observation-only captures permit final-source row and Done-button review without relying on success recordings; they add no test methods, actions or sensitive recovery/password captures.

The same canceled large-tablet log showed the MemberActions test tab fallback tapping Hide Sidebar and then looking for a missing Activity control while scrolling Home. Its test-only tab query now targets the actual native Button supplied by the app and, after the unchanged three-second readiness check, may activate only a verified Show Sidebar or Toggle Sidebar control. The initial missing-control cause is not inferred from the log. Native activation, the existing gesture budget and all booking/cancellation assertions remain unchanged.

Canceled `bdc4add` native logs reached the typed Bookings destination, then exposed an incorrect guide fixture assertion: the unchanged confirmed sample row is Electronics workbench; Workshop bench exists only after a booking mutation, which this draft-preservation journey deliberately never performs. The guide now waits for that exact existing fixture row after the unchanged Bookings-title assertion. This correction follows source and native log evidence; canceled bundles did not export failure media, so it makes no screenshot claim. No new booking, fixture rename or reduced outcome is introduced.

This candidate normally merges reviewed actual dev `3193b08`, replacing a custom keyboard accessory that recordings showed visually but native accessibility could not expose, with focus-bound native navigation-bar Done actions. Its exact per-screen native queries preserve strict hittable/full-window activation and keyboard-dismissal checks. The prior `bdc4add` matrix was canceled after this concrete shared correction; partial results are diagnostic, not acceptance. All A8 guide, row, countdown, branding and split-CI changes remain included; complete exact-head native/UI/Release validation remains required.

A follow-up source audit found the same decorative-glyph width pressure in the staff menu and inventory rows as the recorded Account row defect. At accessibility Dynamic Type sizes these two rows now give their unchanged title/detail content the full width; ordinary-size layouts, fonts, scaling, server text, semantics and navigation are retained. This is a source-audit correction, not a claim that a staff or inventory screenshot failed. The prior `ba22d5f` matrix is diagnostic once superseded; the corrected exact-head full matrix and actual row visuals remain required.

The `988b8ad` compact checkpoint passed all 294 native tests and executed all 36 UI journeys. Five UI failures identified three shared account navigation/layout issues plus two A8 paragraph queries exceeding XCTest's 128-character identifier limit. This candidate normally merges actual dev `a1ad7b2` for the reviewed account corrections. The two guide checks now use exact full-label predicates, preserving their complete paragraph assertions without identifier-length lookup. The old matrix was canceled for diagnosis and is not acceptance; introduction replay and typed bookings actions after those checks still require the new complete run. All cases, six profiles, gesture budgets and timeout settings remain unchanged.

The `32c69d9` phone native checkpoint compiled and executed all 294 native cases. One A8 boundary-copy expectation failed because native localized integer interpolation correctly inserted digit-grouping separators. The test now checks the exact representable decimal value independently of grouping (including non-ASCII decimal digits), while retaining the expected English retry prefix/suffix and every invalid/nonfinite/overflow case. Production formatting and deadlines are unchanged. All shared A7 account/auth/email ownership cases passed in this checkpoint; complete A7 and corrected A8 native/UI/Release acceptance remain pending.

The first merged A8 [`7455146` matrix](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39018807936) stopped during compilation before tests because SwiftUI exposes Reduce Motion as a read-only environment value. The introduction now reads the OS value and combines it locally with the Debug-only UI-test launch flag; Release continues to use the OS setting. The global environment is unchanged, including introduction replay. This compiler checkpoint provides no native test or screenshot acceptance; the corrected exact-head matrix remains required.

The diagnostic `96c25e6` matrix was canceled after its started profiles all stopped in the same account retry test before UI testing. It includes no native acceptance. The candidate now normally merges actual corrected dev `e94a5c8`, including complete successful-refresh fixtures and bounded test synchronization; A7 and A8 native acceptance remain pending.

CI now compiles the entire scheme, runs every native state/API test, then runs every UI journey as distinct steps. Native tests have a ten-minute step bound so an unreachable fixture wait is visible promptly; both result bundles and the shared build log are archived. Scheme, destinations, signing flags, all tests, six profiles and the 120-minute job limit are retained.

This isolated A8 candidate started from A7 `d05dcfc477dae19bd2acd78201f783c9d27cfd61` and now includes the `8ff47bc` staff-title compiler correction through a normal merge. The prior [A7 workflow 39018648885](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39018648885) was canceled for diagnostic logs; native acceptance at corrected dev remains pending; the initial 39017485631 checkpoint stopped before tests, as recorded below. This preparation does not claim native acceptance or bypass that gate. The A8 target is 294 native cases and 36 UI journeys, pending actual compiler discovery and the full matrix. Local checks passed 40 Python cases and the 779-key English catalog check.

Add a replayable App guide covering navigation, requests, renewal, bookings, event tickets,
notifications, payments, security and membership. Staff instructions appear only with available
staff tools. Keep introduction replay and account/makerspace-scoped helpful tips, and use an enabled
Profile alternative when the booking module is unavailable. Show the actual app version/build,
validated selected server where available, and only configured support/privacy destinations.
Unrepresentably long server cooldowns now have safe localized display copy without changing the
retained deadline or permitting an early request; three boundary tests cover that conversion.

White-label builds can supply paired native logo PNGs, a custom SVG icon and a semantic palette.
Validate selected files and optional HTTPS links before generated writes, preserve supplied artwork
bytes and the pinned Design masters, and select custom artwork even with a changed app name. The
regressions exercise actual custom configuration rather than requiring default-brand output.

The final workflow supplies real app appearance/orientation policies to every UI journey, includes
compact/normal/large iPhone and three iPad profiles, and preserves all native tests. The unsigned
physical-device build is audited for effective identity, device families/orientations, camera copy,
branding/fonts/icons, English resources, privacy manifest and disabled multiple scenes. Profile
attachments record actual window/theme; reduced-motion app-environment coverage is distinguished
from a physical system-setting or third-party SDK test.

Provide concrete store text, phone/tablet screenshot and reviewer-account plans, white-label setup,
privacy/account controls and the release procedure. Native test evidence and accepted SHA belong to
the final dev-to-main pull request's exact workflow links. Signing, real-device attestation/providers,
APNs/link deployment, payment confirmation, whole-account deletion and TestFlight/store submission
remain owner/backend release gates; Debug previews and unsigned builds do not establish those results.

Source adds two guide UI journeys, three demo guidance scope/reset cases and three countdown boundary cases. Local composed checks pass
40 Python cases, English catalog consistency and source lint; the native compiler/full device matrix
is the acceptance gate. Parity: App guide / Replay introduction / Reset helpful tips / Start here.


The View bookings shortcut opens a typed current-makerspace booking list above retained Activity history, preserving cached booking/profile drafts. Two state regressions cover history/draft retention and invalidation; the existing guide journey also exercises the real shortcut.

Staff retry timers retain even very large finite server deadlines while sleeping in cancellable
chunks of at most 3600 seconds. This avoids an overflowing UInt64 nanosecond conversion and keeps
canceled or superseded timers from reopening requests. One state regression exercises extreme
server deadlines, replacement and private-scope invalidation; native execution is still required.

## A7 accessible native keyboard dismissal

- Both corrected devices passed all 285 native tests and 32/34 UI journeys, including the largest-text export menu and native share. The two remaining phone/membership journeys confirm a real accessibility issue: the floating custom keyboard Done is visibly drawn, but the complete accessibility tree exposes an empty toolbar and no Done element.
- Replace those two custom keyboard toolbar groups with a localized native navigation-bar Done action while the corresponding field is focused. The action clears the existing FocusState. Use a stable per-screen accessibility ID and retain all three strict native activation/keyboard-absence checks and every downstream phone/session/membership assertion.
- Full 285 native /34 UI /21 Python and unsigned Release validation must pass at this corrected source. Prior failed runs remain diagnostic evidence only.

## A7 accessible account rows and keyboard journeys

- The corrected phone and tablet runs passed all 285 native tests; tablet passed 33/34 UI journeys and phone passed 32/34. Recordings show a real largest-text layout defect: decorative row glyphs squeeze account titles into fragmented words. Give the unchanged title and detail the full row width at accessibility sizes, preserving font scaling.
- The phone-linking test missed a visible floating Done accessory by restricting its lookup to Toolbar descendants; the compact membership journey also skipped that accessory. Require the actual visible/hittable full-window Done button, tap it natively and verify keyboard dismissal before continuing all three original steps. Keep the shared scroll helper, gesture budget and every phone/session/membership assertion unchanged.
- Correct only the export-menu test navigation's proven blind reversal: follow the real row geometry with full visible-content pans and the same 24-attempt bound, positive/visible/hittable activation and native tap. Capture the revealed accessible row in the existing largest-text journey. The shared helper and every subsequent export/share assertion remain unchanged.
- Counts remain 285 native /34 UI /21 Python. Full phone/tablet validation and unsigned Release are still required at the corrected head; these failed runs are not phase acceptance.

## A7 native test fixture correction

- Canceled the previous A7 validation after native diagnostics showed an incomplete successful-refresh fixture prevented the held management retry from being reached. No UI tests had started; that run is not acceptance evidence.
- Share a schema-complete refresh response across account, email and required-password tests, and decode it through the generated `DeviceRefreshResponse` in the existing operation test. The stale-management test now waits at most five seconds for retry arrival or early completion, always releases its held response, and awaits the operation so early decoding errors surface.
- Intended native/UI/Python counts remain 285/34/21. Full phone/tablet tests and unsigned Release must pass at the corrected head before A7 acceptance.

## A7 Account and localization — implementation checkpoint (2026-10-17)

The initial [`d05dcfc` native checkpoint](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39017485631) stopped during compilation before tests: the localized staff menu wrapper accepted only a localization key, while a booking row supplied its server-provided space name. The wrapper now accepts a Text presentation: app-owned literal titles stay localized and the remote name is explicitly verbatim. The complete native gate remains pending; this compiler checkpoint is not acceptance.

Provide global Account and security before joining a makerspace: authenticator status, phone linking,
linked providers, password change and native Devices. Separately gate member Sessions, membership
cancellation/leave and data exports with the actual selected membership and bootstrap capabilities.
Never invent a makerspace0 or infer a current device from list order. A confirmed leave removes local
private scope before refetch, and failed notification cleanup blocks leaving until recoverable.

Account repositories retain the accepted credential installation across requests, retries and
wrong-password identity probes. A retired account cannot issue a request or sign out its replacement.
Manual password changes validate identity after the server acknowledgement; the required temporary
password gate wipes local protected state and returns to fresh sign-in. Security changes that end
sessions clear native credentials before showing transient recovery-code acknowledgement. Existing
live management routes are used where supported; native MFA setup/provider linking that the current
server refuses remains explicitly unavailable, with full isolated Debug journeys.

The Debug-only whole-account deletion journey explains all-makerspace scope, lists every blocker with
fix destinations, requires fresh sample password/OTP proof and exact DELETE confirmation, and handles
expired proof/conflicting new obligations. It only resets preview memory. The immutable schema has no
account-deletion route, so production deletion remains an explicit backend/release dependency.

Prepare an English app catalog and processed API fallback catalog, localize app-owned labels/errors
at their producers, retain raw server/user text and wire values, and bundle English camera purpose
copy. Existing privacy shielding protects credentials, authenticator secrets and recovery codes
across background snapshots. Additional languages and translation layout are not claimed validated.

Source adds57 native state/API cases and8 account/security UI journeys, pending Mac execution at
this checkpoint. Parity: Account and security / Devices / Sessions / Change password / Password changed.
/ Password updated. Sign in again. / Leave makerspace / Cancel renewal / Export your data / Delete account.


The Debug username unverified opens an isolated email-confirmation preview with sample code 123456, rejected-code handling, shared resend cooldown and safe reset; no message is sent or server authority inferred. Export archive controls scroll at accessibility sizes, with a separate largest-text landscape native Share journey. These add two state cases and two UI journeys; execution remains pending.

Bind authenticated email verification and resend forms to the accepted installation, account and
identity generation. Retired forms cannot first-send under a replacement login or refresh its
identity after a delayed acknowledgement. Email cooldowns belong to the account; an old resend
cannot mutate a replacement form's deadline. Six URLProtocol regressions cover first-send,
delayed confirm/resend, valid same-installation token rotation, current-owner refused refresh and
validation/throttle/offline errors with a valid session;
native execution is pending. Refused refresh wipes protected identity through the central owner;
400/429 and offline errors with valid credentials keep the session. State checks ownership again
before committing acknowledgement, cooldown or error copy.

Native session, recovery-code and membership confirmations use guarded dialog-specific button
activation in their UI journeys: assert the visible fixed title, action presence, native hittability
and full window frame before tapping. This carries forward the proven A5 popover test correction;
shared app scrolling and all post-action assertions remain unchanged. Native A7 execution is pending.

A superseded account cooldown cannot clear the newer server deadline, even when its sleep finishes
normally during cancellation. The injected timer dependency keeps the real production sleep and
3600-second chunk cap; one controlled two-request URLProtocol regression holds both security/provider
reads before429, replaces the timer and checks that late completion cannot reopen requests. Native
execution remains pending.

The existing largest-text landscape archive journey waits for the native share sheet’s Save to Files
action before capture, rather than treating a tap as proof of system presentation. It does not save
externally, add a case or extend existing readiness limits. Native proof remains pending.

## A6 Staff — implementation checkpoint (2026-10-17)

Completion evidence: [`53843cb` CI39014792272](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39014792272) passed 219 native state/API tests and 24 native UI journeys on both phone and tablet, 19 Python generation/fixture checks, and the unsigned physical-device Release build. These are contract-fixture/compiler results; real device/provider/backend validation remains a release gate.

Independent full-OS review accepted phone and tablet handover evidence/kit count, the native Record handover confirmation and the recorded request #602, plus attendance person/status confirmation and the recorded notice. The complete large-text Submit request control and receipt were visible on both sizes. On the phone the bounded native scroll alternate actually ran after an unchanged offscreen frame and moved the target from y1727.29 to y1150.96; the later activation required the full button at y716.62–842. The individual coordinate-pan no-op mechanism remains unproven; no production gesture or framework cause is claimed. All earlier member/payment journeys, including actual receipt-page OCR, remain enabled and passed.

Initial native evidence: [`eaa400d` CI39006807733](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39006807733) passed all 215 native state/API cases and the 22 earlier UI journeys on both phone and tablet. The two new staff journeys hung while opening their destinations, so this phase was not accepted and the unsigned physical-device Release step was skipped. Destination construction registered weak child-cleanup callbacks on an observable array. That bookkeeping now avoids view observation; a focused actual-child construction regression checks that registration does not invalidate the parent view while scope invalidation still clears both children. The corrected 219-native/24-UI complete gate remains pending.

The next checkpoint, [`0c5c38b` CI39009445400](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39009445400), passed all 219 native cases and the 22 earlier UI journeys on both devices. Both staff destinations now opened without the previous observation hang. The new journeys found later accessibility/test issues: a parent card identifier replaced the attendance button identifier, and the handover test selected no kit components because it queried a shortened label. Remove the unused parent identifier; explicitly select the one sample component and verify its stepper value and disabled-to-enabled confirmation. Wait for departing Profile/scanner content before querying the next screen. Shared scrolling, native confirmations and all post-mutation assertions remain intact. The complete 219-native/24-UI/Release gate remains pending; neither failing checkpoint is phase acceptance.

The following [`36fd853` checkpoint](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39012325754) again passed all 219 native cases on both devices. Event attendance passed and its resolved-person and recorded screens were reviewed. The guided issue test reached an enabled confirmation but queried the stepper with an exact label; SwiftUI combines its visible count title and semantic label. Match the unique semantic suffix and retain the explicit component count, value and confirmation checks. A previous large-text request journey also failed: on tablet the whole primary button was visible, but the test confused its 8pt gesture margin with actual clipping. Whole-button activation now uses the actual native-bar-adjusted viewport with a 2pt margin; gesture margins stay unchanged. On phone repeated coordinate pans made no progress while the target remained offscreen. That one helper can use a native scroll gesture after an unchanged offscreen frame, within the same 24-attempt bound, retaining full visibility, native hittability and receipt assertions. This is a test gesture correction, not a claimed application cause. The complete gate remains pending; no cases are skipped.

Add the generated request queues, request decisions, QR resolution, container/kit preview, issue,
return, direct handout, booking decisions, event attendance and evidence operations. Staff tools
remain closed in production until a fresh native staff authority and the required makerspace actions
are documented by the server. A role name alone never unlocks them. The clearly labeled Debug staff
preview supplies independent per-makerspace fixtures and actual native flow UI.

Handover progresses through code resolution, borrower/items, contextual camera permission, a bounded
JPEG evidence photo, review and explicit confirmation. Returns require their remark and resolutions;
attendance resolves the person and shows server status before confirmation. Native VisionKit uses an
AVFoundation fallback and manual entry when unavailable. Camera photos are normalized/downsampled,
re-encoded without location metadata, capped and reviewed before upload. Generated evidence grants
use exact POST fields with file last or raw PUT headers, with no app credentials on storage requests.

Conflict, upload refusal, stale scope, duplicate item selection and invalid metadata remain recoverable
without issuing equipment locally. Receipts come from confirmed server results; pending callbacks
cannot mutate an invalidated workspace. This phase adds31 state/API cases plus2 native staff
journeys; the corrected native gate and staff phone/tablet captures remain pending. Physical cameras,
owner provisioning and real staff authority remain deployment validation gates.

Parity: Staff tools / Pending requests / Accept request / Reject request / Issue equipment / Return
equipment / Direct handout / Take evidence photo / Confirm handout / Confirm return / Record handover / Confirm check-in.


Staff repositories also retain their accepted installation. A new replacement-account regression
requires zero queue, container-assignment or booking-approval requests and zero replacement
authentication callbacks after the old owner is retired. Native proof remains pending.

The A5 receipt visual follow-up passed on both device sizes in the initial A6 native checkpoint.
Native Vision recognized both unique sample PDF phrases in actual full-OS pixels within the unchanged
20-second bound; independent review confirmed the rendered receipt and usable Done/share controls.
The prior blank images were premature captures. Retain this actual-page gate in every later run,
explicitly include small text in OCR coverage and attach Vision errors on refusal. No app marker,
viewer replacement, fixed sleep or test removal is involved.

The Debug staff repository now retains generated request and direct-loan records after each
confirmed mutation. Acceptance quantities survive issue and queue refresh; partial returned,
damaged or missing counts remain outstanding until every issued item is resolved. Separate direct
loans retain their actual selected/scanned quantities, distinct local item IDs, evidence and return
notes. Invalid, duplicate or overremaining resolutions are rejected before committing any record.
Sample QR codes also carry the currently selected makerspace, including the second demo space.

Three new refetch regressions cover partial acceptance/issue, cumulative request returns and
independent direct-loan quantities/returns. The existing makerspace test checks both QR codes.
This increases the intended complete A6 native total to 219, with 24 UI journeys and 19 Python cases;
new native execution remains pending. The change does not alter the live API or contract.

## A5 Payments — implementation checkpoint (2026-10-17)

Native build evidence (rendered-PDF follow-up pending): [`072275f` CI39004152168](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39004152168) passed 188 native state/API cases and 22 native UI journeys on both phone and tablet, 18 Python generation/fixture checks, and the unsigned physical-device Release build, with no failed or skipped tests. The native outcome popover, awaiting confirmation, canceled/pending state and complete request-submit action were visually reviewed. Both PDF captures showed an early blank preview canvas; opening chrome does not prove rendered document content. The actual-page follow-up in [`eaa400d` CI39006807733](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39006807733) recognized both page phrases and independently demonstrated the complete rendered receipt on both sizes; A6 staff navigation still needs its corrected full gate. These are fixture/compiler results; real backend/provider/device setup remains a release gate.

Rerun every existing A4 journey with a stronger request-review check: a fitting button must be
fully inside the visible content before tapping and before the screenshot. Cap review-only drag
travel to the remaining exposed edge, accounting for the pan activation slop observed in native
traces; the 24-attempt bound, native gesture and generic controls remain unchanged. The previous
A4 native/Release run passed, but its clipped before-submit phone capture was not visually accepted.
This combined gate must demonstrate the entire primary label before further phase acceptance.

Add the generated payment array, native Stripe intent, document list, download grant and authenticated
PDF operations. Payments are available from Home, Activity and Profile. A checkout callback never
marks a payment paid: a fresh scoped server list is the authority. A failed post-sheet status read
keeps every SDK outcome nonpayable until an explicit successful refresh. Bounded reconciliation and
all document/intent actions honor retained Retry-After deadlines, including a concurrent receipt
request that becomes throttled. Account, server and makerspace changes cancel presentation and
invalidate cached records before late callbacks can act.

Bind member reads/actions and payments to the accepted device-session installation before their
first executor hop. A retained repository cannot borrow a replacement account's credentials, and
failure callbacks recheck their captured identity on MainActor before changing authentication.
Expose the actor's epoch-only installation comparison used by the bound repositories. It remains
available after a refused refresh clears credentials. The first A5 native checkpoint stopped at the
missing declaration before executing tests; the corrected complete native gate remains pending.

Same-installation token rotation remains valid. Five regressions cover retained reads/mutations,
receipts/intents, rotation and delayed failure callbacks; native execution remains pending.

Retain the 120-minute native job allowance established during the A4 validation, with all tests,
the same device profiles and parallelism. This avoids truncating the expanding simulator journeys
and physical-device Release compilation; it does not treat a timeout or cached build as a pass.

Use the official pinned Stripe PaymentSheet and per-attempt SDK state; Razorpay's native adapter
is compiled but remains unavailable until the server supplies its documented vendor configuration.
The current contract supports Stripe only. Receipts and credit notes open in native QuickLook/share;
PDF download stays on the generated authenticated same-server route, with bounded validated bytes,
no arbitrary URL fetch and no credentials forwarded to storage hosts.

The explicit Debug payment preview never launches a payment SDK or creates a charge. It demonstrates
paid, awaiting confirmation, canceled, failed and late-confirmation journeys using separate per-maker
in-memory repositories. Native simulator/compiler results remain pending at this checkpoint; real
provider confirmation/webhooks, device SDK return paths and owner setup remain release gates.

Parity: Payments / Review payment / Continue to payment / Payment pending / Paid online / Paid at the
desk / Refresh payment status / Receipts and credit notes / Share document / Done. Source adds22
payment state/API cases and2 native payment journeys; these counts are intended, not evidence of a pass.

The corrected compiler run executed all 188 native cases and all 20 inherited UI journeys on the
phone successfully. Both new payment journeys then stopped in the native outcome popover: its
separate title scroll area was incorrectly chosen by the generic app-content helper, despite the
action being fully visible and hittable. Payment tests now assert the actual dialog title and the
complete action frame, capture it, then use the native button activation. Shared scrolling and
payment behavior are unchanged. The complete corrected phone/tablet and Release gate is pending.

## A4 Notifications and trusted routing — implementation checkpoint (2026-10-17)

Visual follow-up accepted: the complete two-line Submit request button is visible in the current phone capture, and [`072275f` CI39004152168](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39004152168) reran every inherited journey successfully on phone and tablet. Request-review buttons that fit the viewport require their entire frame before activation; other app controls retain their prior native behavior. The native trace showed valid modal scroll extent: search resumed, but its old fixed half-budget reversal undid progress. Request-only direction now follows target edges with the same 24-attempt bound. The cause of individual injected gesture no-ops remains unproven; diagnostic overlays and the targeted workflow were removed before this accepted run.

Native build evidence (visual follow-up pending): [`a989989` CI38998510266](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/38998510266) passed 161 native state/API tests and 20 native UI journeys on both phone and tablet, 18 Python generation/fixture checks, and the unsigned physical-device Release build, with no failed or skipped tests. The phone before-submit screenshot was rejected because midpoint activation left the second label line below the screen. The stricter request-only visibility check was included with A5; its complete native rerun and fully visible phone screenshot are accepted in the follow-up above. These are fixture/compiler results; real backend/provider/device validation remains a release gate.

Wire the native notification delegate, contextual permission UI, per-account device-only Keychain
registration metadata and generated create/delete operations. Consent differs from OS permission;
revoked permission pauses delivery and cleans up server IDs without erasing account consent. Token
rotation reconciles each freshly confirmed direct membership without changing the selected UI scope.
Only the two push operations can use the background makerspace override. Logout removes protected identity, screen holders and drafts immediately, resets SDK callbacks
synchronously with an ownership guard, awaits serialized server cleanup, then revokes/wipes credentials.
Cleanup authentication and Retry-After errors take precedence over simultaneous Keychain write failures;
pending server IDs remain recoverable and throttled cleanup cannot send repeated deletes.
Offline deletion remains pending; SDK callbacks cannot prove registration or delivery. Each live push
worker retains its credential installation epoch, so queued old-account work cannot send under a new
account. Foreground receipt hides untrusted remote banner content and refreshes only the current
maker's inbox after a fresh identity check, without navigation or scope changes.

Hints and URLs never choose a deployment or grant access. Current-origin native paths use an explicit
allowlist; current Inbox `/m/{slug}/member` links resolve the exact slug against fresh direct memberships.
Staff web-inbox links remain closed without native staff authority. Unknown versions fall back to the
freshly authorized Inbox. Conflicting slug/ID hints cannot change scope. Every push first refetches the authorized inbox. Identity, selection and actual
resource refetch must succeed before a one-use navigation ticket opens; stale account/view responses
cannot navigate. Read refusal, unavailable resources and Retry-After have visible recovery states.

The owner can set explicit `aps_environment` and `associated_domains` brand inputs with their actual
Apple team; prebuild regeneration preserves the validated configuration. Unconfigured builds have no
invented APNs or universal-link domains, and simulator signing excludes APNs. The DEBUG demo has
isolated permission/enable/token-rotation/tap previews, cross-makerspace navigation and refusal states;
it never asks OS permission, launches push SDK setup or registers a token.

Coalesce routing, token registration and foreground identity reads, releasing busy state before every
waiter continues. Add installation-epoch checks before publishing foreground/restored identity so an old `/me` response
cannot restore protected UI after session invalidation. Preserve privacy and draft state across app
backgrounding, and retain scope-aware notification navigation across phone/tablet layout changes.

Schedule the request-review countdown only when a Retry-After deadline exists; the normal review
uses identical static submission controls and keeps the same busy, empty-cart and deadline guards.
This removes needless scheduled work without claiming a proven cause for the phone scroll stall.
Allow 120 minutes for the complete native suite and unsigned physical-device Release compilation;
all tests, profiles and gestures remain enabled. Review buttons that fit vertically must be fully
inside visible content before native activation and the before-submit capture: a hittable midpoint
could leave the second line below the phone screen at the largest type size. Native and visual
acceptance of this stronger check remain pending.

Parity: Notifications / Enable notifications / Notifications are off for this device. / Open system
settings / Open update. Local generation/capability/source checks pass; native state/API/UI tests and
rendered phone/tablet evidence await the A4 compiler checkpoint. Real APNs delivery, server link files,
provider keys and cross-deployment payload attribution remain deferred backend/release inputs.

## A3 Member actions — implementation checkpoint (2026-10-16)

Completion evidence: [`e427626` CI38974366101](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/38974366101) passed 109 native state/API tests and 18 native UI journeys on both phone and tablet, 14 Python generation/fixture checks, and the unsigned physical-device Release build. These are contract-fixture/compiler results; real device/provider/backend validation remains a release gate.

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
