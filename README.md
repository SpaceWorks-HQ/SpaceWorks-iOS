# Space Works for iOS

iOS 17+ native SwiftUI app. Start with [the PRD](docs/PRD.md); current scope is **A0 Base**. Each later phase waits until its predecessor is merged.

## Development workflow

Use `dev` for ongoing changes and push commits to `origin/dev`. After implementation and CI validation finish, open the final pull request from `dev` to `main`. The A0 foundation is already merged into `main`.

## Build and test

```sh
git submodule update --init --recursive
brew install xcodegen librsvg
python3 scripts/generate.py
python3 -m unittest discover -s scripts/tests -v
xcodegen generate
xcodebuild test -project SpaceWorks.xcodeproj -scheme SpaceWorks -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
```

Choose an installed iPhone simulator (`xcrun simctl list devices available`). CI selects one automatically and retains the test results and screenshots. On a host without a Mac, CI is the Swift compiler; passing Python checks alone does not complete the phase.

`project.yml` is the project source. The SPM build plugin generates client/models from `api/openapi.json` into build output; generated Swift and Xcode projects are never committed. The authoritative source stays byte-identical. A tested build projection selects the refresh operation's documented JSON representation because Apple's generator turns a shared JSON/multipart component into an unencodable multipart enum. No API fields or schemas change. `scripts/regenerate-api.sh` builds the API package independently. A0 filters health and refresh operations, with dependencies, using Apple's generator filter. Add operations when later phases need them, never hand-write API payload models. [Contract provenance](api/provenance.json) records the supplied schema hash and source revision.

Brand configuration and signing: [WHITE-LABEL.md](docs/WHITE-LABEL.md). Current validation and parity: [CHANGELOG.md](docs/CHANGELOG.md). Platform fonts remain in use pending Gilroy app-embedding clearance.
