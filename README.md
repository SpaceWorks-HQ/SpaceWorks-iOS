# Space Works for iOS

iOS 17+ native SwiftUI app for iPhone and iPad. [The PRD](docs/PRD.md) defines the flows; the owner's extensions in [AGENTS.md](AGENTS.md) add tablets, shared onboarding/auth UX and completion of the remaining phases on `dev`. [CHANGELOG.md](docs/CHANGELOG.md) records actual phase implementation, tests and parity. Only recorded passing phases count as complete.

## Development workflow

Use `dev` for ongoing changes and push commits to `origin/dev`. After implementation and CI validation finish, open the final pull request from `dev` to `main`. The A0 foundation is already merged into `main`.

## Build and test

Use Xcode 26.2 with the iOS 26 SDKs, matching CI's pinned toolchain. Select that installation
through `xcode-select` or `DEVELOPER_DIR`; Xcode 16.4 cannot compile the pinned Stripe SDK.

```sh
git submodule update --init --recursive
brew install xcodegen librsvg
python3 scripts/generate.py
python3 -m unittest discover -s scripts/tests -v
xcodegen generate
python3 scripts/lint.py
```

Follow [RELEASE-READINESS.md](docs/RELEASE-READINESS.md) for simulator selection and the exact test command, including the ad-hoc simulator Keychain signing identity. CI tests representative phone/tablet profiles, retains screenshots and compiles an unsigned physical-device Release build. Manually dispatch the workflow for the complete configured device matrix. Inspect recorded hardware/runtime names; the matrix does not represent every Apple device. Windows cannot compile SwiftUI; passing Python checks alone does not establish an iOS build or test pass.

`project.yml` is the project source. The SPM build plugin generates client/models from a tested build projection of `api/openapi.json`; generated Swift and Xcode projects are never committed. The authoritative schema stays byte-identical. `scripts/regenerate-api.sh` builds the API package independently. Operation filters expand with implemented phases; never hand-write API payload models. [Contract provenance](api/provenance.json) records the supplied schema hash and source revision.

Choose a server on launch or lock one HTTPS origin in `branding/brand.json`. Debug builds allow documented local Docker origins and an explicitly labelled, isolated in-memory demo. Demo authentication, notifications and checkout previews do not establish a live session, push delivery or payment. Release builds omit demo entry points. [LOCAL-DOCKER-VALIDATION.md](docs/LOCAL-DOCKER-VALIDATION.md) separates local API evidence from fixtures.

The backend and owner provisioning are deferred. Unsupported native contracts remain unavailable; see [backend dependencies](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/issues/3). Real attestation, providers, push, checkout, account deletion and store distribution require the deployment inputs and verification in the release guide.

Brand configuration and signing: [WHITE-LABEL.md](docs/WHITE-LABEL.md). Space Works uses the pinned Design semantic colors, static logo masters, native system text and licensed Unbounded accent font. Gilroy is not embedded without app-embedding permission. Never commit signing material, provider secrets or test credentials.
