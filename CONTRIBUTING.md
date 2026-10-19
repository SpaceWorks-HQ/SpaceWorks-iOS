# Contributing

Read [AGENTS.md](AGENTS.md), the immutable [PRD](docs/PRD.md), the current phase notes and
[release handoff](docs/RELEASE-READINESS.md) before changing behavior. Follow the owner's current
branch/PR instructions; do not create another delivery PR for the current batch.

Use the pinned Design submodule and supplied OpenAPI contract. Server calls and payload models
belong to the generated client. Report missing contracts rather than inventing endpoints, successful
payments, deletion or access. Keep credentials and personal data out of code, fixtures and logs.
Use private reporting for security issues; see [SECURITY.md](SECURITY.md).

On a Mac with the reviewed Xcode/generator versions:

```sh
git submodule update --init --recursive
python3 scripts/check_build_tools.py
python3 scripts/generate.py
python3 -m unittest discover -s scripts/tests -v
python3 scripts/lint.py
xcodegen generate
python3 scripts/dependency_lock.py stage
```

Use the exact native commands and simulator signing configuration in the release guide. Retain the
reviewed lock and no-automatic-resolution flags documented in [Dependencies](Dependencies/README.md).
Generated Swift, assets, entitlements and Xcode projects are not source edits. A dependency/toolchain
change requires explicit graph review and fresh native/Release proof; do not update versions implicitly.

Preserve native navigation, semantic branding, Dynamic Type/Bold Text, VoiceOver, Reduce Motion,
session ownership and cancellation. Test affected behavior without removing required cases or
pretending Windows source checks establish a SwiftUI build. Preserve exact source/run/artifact
provenance and actually inspect required full-OS captures. Fixture/demo results never establish
backend delivery or signed real-device behavior. Use small phase commits with the configured
owner identity and the required Codex trailer for Codex-authored changes.
