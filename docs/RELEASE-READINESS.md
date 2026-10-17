# iOS release handoff

Prepared 16 October 2026. This is the release procedure and evidence ledger, not a claim of
store submission. Phase implementation and passing checks are recorded in `docs/CHANGELOG.md`.
The owner requested phones and tablets and deferred backend setup; that instruction supersedes
the original PRD's tablet exclusion and intermediate merge requirement. Work stays on `dev`
until the owner reviews the final `dev` to `main` pull request.

## Reproduce the app

Clone recursively and retain the reviewed `design/` commit. The authoritative contract is
`api/openapi.json`; do not substitute a schema from a local server checkout. Use Xcode 26.2 and
its iOS 26 SDKs, matching the CI pin. The pinned Stripe package uses UIKit APIs absent from the
Xcode 16.4 SDK. Select the correct installation through `DEVELOPER_DIR` or `xcode-select`.
On a Mac:

```sh
brew install xcodegen librsvg
python3 scripts/generate.py
python3 -m unittest discover -s scripts/tests -v
python3 scripts/lint.py
xcodegen generate
export GITHUB_ENV="$(mktemp)"
python3 scripts/device-matrix.py phone
SIMULATOR_ID="$(python3 -c 'import json; print(json.load(open("validation-device.json"))["udid"])')"
xcodebuild test -project SpaceWorks.xcodeproj -scheme SpaceWorks \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath DerivedData -resultBundlePath TestResults.xcresult \
  -skipPackagePluginValidation ONLY_ACTIVE_ARCH=YES CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

`device-matrix.py` writes to `GITHUB_ENV` in CI. The temporary-file assignment above supports a
local Mac invocation; omit it when running inside GitHub Actions.
The generated `LOCALCI` Keychain identity exists only for simulator tests. It must never
replace the Apple team identity or physical-device provisioning.

The `iOS` GitHub Actions workflow runs representative phone/tablet validation on pushes/PRs.
Dispatch it manually on the final commit to run compact/normal/large phone, iPad mini,
landscape iPad and large iPad profiles. Keep `validation-device.json`, test result bundles,
screenshots, logs and the dependency resolution record with the release evidence. Check actual
device/runtime names rather than claiming every iPhone/iPad was tested. The phone job also
compiles an unsigned physical-device Release build; that is compile evidence, not an installable
store build, a signed archive, or a real-device SDK test.

## Configure one deployment

`branding/brand.json` owns the display name, `ios_bundle_id`, `ios_team_id`, icon and semantic
theme path. `server_url: null` leaves server selection available; an HTTPS origin locks the
build to that deployment. Provide real HTTPS support and privacy URLs before distribution.
See `docs/WHITE-LABEL.md` for generator mechanics. Do not hand-edit generated assets,
`Brand.xcconfig`, generated API sources or the generated Xcode project.

Use an owner-controlled registered bundle ID and team. Configure the distribution certificate
and provisioning profile in the private signing environment. Verify the archive's effective
bundle ID, team, entitlements, capabilities, supported device family, version/build number,
icon, privacy resources and URL schemes. The current source version is controlled by
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; increment the build
number for each uploaded build. Never commit a certificate, private key, provisioning profile,
App Store Connect API key, APNs key, test password or service credential.

| Integration | Deployment input and verification |
|---|---|
| App Attest | Enable the capability for the real team/bundle ID; server must allow that app and validate the documented proof. Development and production environments must match the signed build. Test challenge, proof, refusal and fresh sign-in on real hardware. |
| Google | Registered iOS OAuth ID, server audience and reversed callback scheme must agree. `google_reversed_client_id`, when supplied to the brand generator, is the registered scheme. A web-only config response does not establish a supported native device-grant flow. |
| Apple | Enable Sign in with Apple, configure the correct native audience and use a supported server device-grant response. Test cancellation, repeat sign-in, revoked consent and account deletion cleanup when implemented. |
| Organization OIDC | Configure the exact registered callback and native delivery contract. Use the ephemeral native system authorization session; never substitute a web cookie session. |
| APNs | Owner supplies Push capability/provisioning and the private APNs provider key to the server. Verify production/sandbox topic, device registration, token change, logout deletion and foreground/cold-launch routing. |
| Universal links | Server publishes its real associated-domain file; app entitlement must match the owner's domain/team/app. Verify a link from outside the app, then authorization and fresh resource loading. A custom scheme alone is not universal-link verification. |
| Camera/evidence | Archive includes the purpose string; test first request, denial, later Settings enablement, no hardware, rotation, cancellation and manual entry. Upload only explicitly confirmed evidence through documented operations. |
| Payments | Server selects vendor and supplies runtime public checkout values; secrets remain on the server. Verify configured sandbox success, cancellation, failure, delayed webhook and later status refresh. SDK success alone never proves paid status. |

The repository backend-request issue tracks the missing contract work:
[native backend dependencies](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/issues/3).
Native minimum-version/provider configuration, staff device authority, push v2/link files,
Razorpay checkout fields and whole-account deletion need the owner's supported contracts.
Account management also has confirmed native limitations: the current backend refuses optional
authenticator enrollment from a device session and provider linking from a native client. Native
login enrollment challenges remain supported. Account session/export list schemas omit pagination
parameters; later pages must wait for a published contract. The app must keep these live paths
explicitly unavailable and never impersonate a browser client. Required-MFA disable controls stay
hidden; recovery-code replacement and supported MFA changes clear old sessions before returning
to sign-in. A wrong management password must not destroy a separately verified valid session.
Debug demo journeys exercise UI states with labelled in-memory data; they do not validate
attestation, authentication delivery, push, charges or deletion against a real service.

## Privacy and store content

The owner must confirm actual production collection, sharing, retention and SDK behavior before
answering App Store Connect privacy questions. Review the final archive, including all transitive
SDK privacy manifests and required-reason API usage. Do not declare that the app collects no data
because it has no analytics. Apple requires disclosure of relevant partner SDK practices as well
as the app's practices. [App privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy),
[privacy manifests](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk),
[SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).

| Area to verify | Production question to resolve |
|---|---|
| Account/contact | Name, email, optional phone, account identifiers and membership information: purpose, linkage, sharing and retention. |
| Device/security | Device grant, attestation and push identifiers: destinations, security purpose and deletion behavior. |
| Camera/photos | Whether captured evidence leaves the device, who can view it, storage duration and removal rules. QR scanning alone is distinct from photo upload. |
| Activity/payments | Requests, loans, bookings, event attendance, payment metadata and legally retained records; provider-specific processing. |
| Diagnostics | Verify actual SDK defaults and server logs; no app analytics was authorized. Do not assume dependencies never transmit diagnostics. |

Account creation requires a genuine in-app way to initiate whole-account deletion. A membership
leave action, disabled placeholder or demo completion does not satisfy that requirement. The
owner-deferred deletion contract remains a release gate; implement the PRD's blocker list,
fix links, reauthentication, confirmation and anonymized retained-record explanation when supplied.
[Apple account deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion).

Supply the real support/privacy URLs, description, subtitle, category, age/content answers,
device-specific screenshots, review notes and a stable reviewer account/makerspace. Suggested
description to adapt: “Find tools, request equipment, book a space and keep up with your makerspace.
See loans, events, tickets, payments and updates together in Space Works.” Include only features
enabled and working in the submitted deployment. Keep reviewer credentials in App Store Connect's
private review information, never the repository. Explain any hardware-dependent review path.

Concrete listing copy, screenshot capture order and private reviewer-access notes are prepared
in [STORE-LISTING.md](STORE-LISTING.md).

## Final acceptance and distribution

1. Record the exact app commit, Design commit, schema hash, dependency versions, CI run links and
   tested OS/hardware profiles. Require all phase checks to pass without skipped required tests.
2. Inspect the final app at large text, light/dark, portrait/landscape and narrow tablet windows.
   Verify VoiceOver order/labels, keyboard navigation/autofill, reduced motion, clear errors,
   static undistorted logos and reachable controls. Screenshot review complements functional tests.
3. On owner-provisioned devices verify real attestation/sign-in/refresh, providers, push, camera,
   payment reconciliation, deletion and account/makerspace isolation. Record unsupported cases
   explicitly rather than treating simulator/demo results as physical-device evidence.
4. Generate the project in the private Mac signing environment, archive the Release scheme for
   a generic iOS device, validate the signed archive in Xcode Organizer, then upload it to the
   owner's App Store Connect application. Simulator/unsigned CI outputs cannot be uploaded.
5. Use TestFlight first. Keep the production-compatible backend and reviewer account available,
   complete internal/external tester review as applicable, resolve feedback, and submit the
   accepted build with the matching privacy declarations and screenshots.

Record distribution evidence here after owner provisioning; no credentials belong in this ledger:

| Evidence | Value |
|---|---|
| Accepted app / Design commits | The exact tested source SHA and pinned Design input belong in the final [dev to main PR](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/pull/2) and matching CI artifacts; acceptance requires its completed validation section |
| Full device-matrix CI run | The final PR validation section must link the accepted six-profile run and reviewed artifacts; a pending or failed run does not establish acceptance |
| Signed archive / version / build | Owner signing environment required |
| Real-device provider test record | Owner backend/configuration required |
| Whole-account deletion verification | Updated owner contract required |
| TestFlight build / tester acceptance | Owner App Store Connect access required |
