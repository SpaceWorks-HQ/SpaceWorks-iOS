# Space Works mobile development

1. `docs/PRD.md` is the spec. If it and the code disagree, the PRD wins. If the PRD is unclear,
   **stop and ask**. Don't invent API fields.
2. Only the generated client talks to the server. Never hand-write models. Never call an endpoint that
   is not in `api/openapi.json`.
3. Work one phase at a time. For each phase: plan → implement → tests → CI green → commit(s) → phase
   note in `docs/CHANGELOG.md`. Small commits, imperative one-line messages, e.g.
   `feat(a0): theme generated from design tokens`. Add `Co-Authored-By: Codex <noreply@openai.com>` to
   commits Codex wrote.
4. **Parity**: same screens, same names, same flows, same error copy on both platforms. At the end of
   each phase, each agent writes a parity checklist (screens and states covered) into the phase note.
   The human compares the two.
5. Tests per phase: unit tests for every view model / state holder and the networking core, a
   MockWebServer / URLProtocol stub test for every API call used, and UI tests for the phase's main flow.
   A phase with failing or skipped tests is not done.
6. Secrets: none in the repo, ever. No analytics or third-party SDKs beyond §6 without asking.
7. Accessibility and dark mode are part of "done" in every phase, not a final polish pass.

## Branch delivery workflow

The owner merged the A0 foundation and subsequently updated the delivery workflow:

- Start ongoing work from `dev`, commit there, and push to `origin/dev`.
- Do not open pull requests or create feature branches for this batch; consolidate on `dev`. After the required repository native/CI, unsigned Release and actual visual gates pass, merge the tested `dev` directly into `main`, as authorized by the owner.
- Retire obsolete work branches only after their work is safely retained. Preserve the owner's configured commit identity and the required Codex co-author trailer.

## Complete-build execution addendum (owner, 2026-10-16; delivery updated 2026-10-18)

The owner requested the remaining phases as one batch, with Android and iOS agents in parallel.
Implement each phase sequentially on `dev`, with phase commits, tests, CI evidence, and a changelog
parity checklist. A green phase may proceed without an intermediate merge. Consolidate the batch
on `dev`, complete the required repository validation and actual visual review, then merge the tested
work directly into `main` under the owner's latest authorization. Follow the branch delivery policy
above; do not open pull requests or create feature branches for this batch. Preserve `docs/PRD.md`
byte-for-byte.
Phone and tablet layouts, portrait/landscape, light/dark and largest Dynamic Type are now in scope.
Use generated contract operations only. Record missing backend contracts as `backend-request`
issues and continue independent work when prerequisites permit. Local Docker is the development API;
development attestation and local HTTP must remain Debug-only. Store credentials only in Keychain.

Mobile-specific onboarding/auth UX and motion belong in `docs/mobile-auth-ux-spec.md` and
`tokens/mobile-motion.json` in this repository. Do not push mobile implementation/spec additions
to the Design repository. The Design submodule supplies the existing brand masters and colors.
