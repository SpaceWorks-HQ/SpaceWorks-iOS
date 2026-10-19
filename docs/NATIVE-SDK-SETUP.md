# Native provider setup

SDK code is compiled in CI. A compiled adapter is not evidence of a configured provider or a
completed real-device transaction. Debug demo flows never invoke these SDKs or send their sample
values to a service.

Sign-in methods render only from the server's `GET /api/v1/config` `native.providers` block
(contract SHA-256 `962e6a4b…`). Every native method uses the same attested device flow: a fresh
attestation challenge, the method's proof, then a device grant through a generated operation.
A response without `refresh` and a UUID `device_grant.id` is refused; no browser cookie or
access-only response is ever accepted as an app session.

| Integration | Native adapter | Owner/server setup |
|---|---|---|
| Device integrity | DeviceCheck App Attest; fresh key per sign-in, `clientDataHash = SHA-256(challenge)`, sent as `{"type":"app_attest","key_id","attestation"}` through the schema's open proof alternative. Simulators in Debug send `{"type":"development"}`. | Approved native app registration (blank makerspace) with the actual App ID Prefix; App Attest capability for the registered bundle/team; development registration for Debug builds |
| Minimum version | `native.min_app_version.ios`, compared by dotted numeric components on launch | Native app registration "Min supported version" (production) |
| Google | Official GoogleSignIn 10.0.0 with the server-issued nonce; the ID token audience is `native.providers.google.ios_client_id` (no server client ID) | Register the iOS OAuth client; set "Google ios client id"; put its reversed client ID in `branding/brand.json` `google_reversed_client_id` so the callback scheme is registered |
| Apple | AuthenticationServices with the server nonce; sends the authorization code (for revocation at deletion) and first-time name | Sign in with Apple capability; list the bundle ID in "Apple native app ids" |
| Organization OIDC | Discovery from the published issuer, authorization code + PKCE (S256) in an ephemeral `ASWebAuthenticationSession`, then the ID token goes to `POST /auth/social/oidc/{slug}`. Discovery and the code exchange talk only to the identity provider. | Add `spaceworks://auth/callback` as a redirect URI on the provider's existing public client (the published `client_id`) |
| Phone | `POST /auth/phone/login/start` with `delivery: device` and a fresh challenge; confirm with the code, the same challenge and its attestation before the challenge expires (180 s by default). Member-only. | Phone login and SMS delivery enabled on the server |
| Push | UserNotifications/APNs; routing keys arrive under the payload's `data` dictionary | APNs key in Platform push settings; `aps_environment` in `branding/brand.json` |
| QR | VisionKit scanner and explicit manual-code fallback | Real camera permission/device; server resolves the opaque code |
| Payments | Stripe PaymentSheet or Razorpay Checkout, selected by the intent's `vendor` | Per-makerspace provider credentials on the server; no app secrets |

Google clears its SDK session after obtaining a token; the app's Keychain device grant remains the
sole app session. Provider tokens are passed straight to the generated operation and are never
logged or persisted. Social sign-in returns tokens only (the backend satisfies MFA through the
provider); password and phone sign-in may return the generated MFA challenge.

Reauthentication for account deletion supports password (+ authenticator code), the separate phone
reauthentication code, and native Google/Apple/organization proof with the server's reauthentication
nonce, including a requested second factor. GitHub proof is web-only.

Sources: [Google release](https://github.com/google/GoogleSignIn-iOS/releases/tag/10.0.0),
[Google integration](https://developers.google.com/identity/sign-in/ios/sign-in),
[App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity),
[RFC 8252](https://www.rfc-editor.org/rfc/rfc8252).
