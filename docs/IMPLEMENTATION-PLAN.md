# Complete native app execution plan

The owner extended the PRD scope on 2026-10-16 to include tablets and requested the remaining
phases in one batch on `dev`. The original PRD remains unchanged. Each phase has generated-client
API coverage, state tests, main-flow UI tests, green macOS CI, commits and a parity note before the
next independent phase. Under the owner's latest delivery instruction, consolidate work on `dev`
and merge the tested branch directly into `main` after required repository validation and actual
visual review pass. No final pull request is required.

| Phase | Deliverable | Gate |
|---|---|---|
| A1 | Device password/attestation, MFA, atomic Keychain rotation, restore/logout, direct-membership switcher | Native provider configuration, authority and missing social contracts become backend requests |
| UX/onboarding | Optional introduction/replay, shared motion, native password focus/autofill, signup/recovery/email, all provider demo branches | A1 green; generated supported operations and real phone/tablet screenshots |
| A2 | Dashboard, inventory/search/detail, requests/loans, bookings/events, card, inbox | Authenticated generated client and validated makerspace |
| A3 | Hardware requests, renewal, booking, registration/ticket, profile/preferences | Server-confirmed write results; no local availability or permission calculation |
| A4 | APNs registration and validated in-app routing | Push v2 contract/server link files and owner APNs provisioning |
| A5 | Server-selected payment SDK, status reconciliation and documents | Supported vendor contract, owner publishable configuration |
| A6 | Permission/authority-gated staff requests and evidence/scanning | Native staff authority contract and real-camera validation |
| A7 | Sessions/membership/account deletion, privacy/accessibility/localization | Account deletion contract; store privacy inputs |
| A8 | White-label release guide, archive/TestFlight/store package | Owner signing/store access, reviewer account and policy URLs |

## Device and state matrix

Use compact stacked cards and independent tab navigation on phones. Use a persistent sidebar and
readable constrained content/list-detail on iPads. Avoid stretching forms to tablet width. The CI
matrix covers a small iPhone, common/large iPhone, iPad mini and large iPad, with landscape UI flows
and largest Dynamic Type in light/dark. API stubs remain deterministic; local Docker integration
evidence is recorded separately from simulator UI evidence. Real App Attest, camera, APNs and
payment-provider tests require configured devices/accounts and must never be described as passed
on a simulator.

The owner subsequently deferred the app backend and requested complete flow/UI coverage now.
Unsupported planned features will have explicit DEBUG-only in-memory demo journeys and production
integration seams; they will not invent endpoints, bypass authority or claim server verification.

The owner's additional UX checkpoint implements the mobile-local `docs/mobile-auth-ux-spec.md`
and `tokens/mobile-motion.json`. Master artwork stays static; sibling content honors Reduce Motion.
Native email verification is an authenticated Profile action. `email_verified=false` alone is not
an invented restricted-session authority; access-only `verification_only` results never enter the app.

The owner requested mobile UX work stay in the mobile repositories. `docs/mobile-auth-ux-spec.md`
and `tokens/mobile-motion.json` are versioned here; the Design submodule stays on its existing
brand asset/token baseline. New mobile flow and motion changes must not be pushed to Design.
