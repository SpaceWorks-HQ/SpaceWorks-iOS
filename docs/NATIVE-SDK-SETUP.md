# Native provider setup

SDK code is compiled in CI. A compiled adapter is not evidence of a configured provider or a
completed real-device transaction. The owner deferred the app backend; Debug demo flows never invoke
these SDKs or send their sample values to a service.

| Integration | Native adapter | Owner/server setup |
|---|---|---|
| Device integrity | DeviceCheck App Attest; fresh key per sign-in, SHA-256 challenge | Registered bundle/team, App Attest capability, server app allowlist and production proof contract |
| Google | Official GoogleSignIn 10.0.0, exact SPM release | Native iOS and server client IDs from approved native config; optional `google_reversed_client_id` in brand.json must be the registered reversed iOS client ID |
| Apple | AuthenticationServices authorization controller | Sign in with Apple capability, native token audience/server fix and approved native config |
| Organization OIDC | Ephemeral ASWebAuthenticationSession, validated state and exact `spaceworks://auth/callback` | Native device delivery callback contract; current web-only callback cannot be substituted |
| Push | UserNotifications/APNs delegate | APNs capability, owner provider key/server link files and server registration setup |
| QR | VisionKit scanner and explicit manual-code fallback | Real camera permission/device; server resolves the opaque code |

Live sign-in buttons are not rendered from web client IDs. The current schema does not include the
native provider/version configuration and social MFA union; update the authoritative snapshot when
the owner supplies them. Google refuses to launch without its registered callback scheme and clears
its SDK session after obtaining a token; the app's Keychain device grant remains the sole app session.
Provider operations return opaque identity tokens to the generated-client integration seam; tokens
are never logged or added to defaults. The original PRD remains unchanged.

Sources: [Google release](https://github.com/google/GoogleSignIn-iOS/releases/tag/10.0.0),
[Google integration](https://developers.google.com/identity/sign-in/ios/sign-in),
[App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity).
