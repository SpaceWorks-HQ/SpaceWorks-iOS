# Publish your own iOS build

This guide prepares a build for one deployment. A0 supplies the base; store release follows A7/A8.

1. Fork this repo and clone recursively (`git clone --recurse-submodules …`). Keep the pinned `design/` commit unless intentionally updating the design system.
2. Edit `branding/brand.json`: set your display name, unique reverse-domain `ios_bundle_id`, Apple `ios_team_id`, HTTPS deployment origin in `server_url`, and support/privacy URLs. A null server URL asks the user on launch; a fixed URL locks the build to that deployment. Paths, credentials, queries and fragments are rejected.
3. Replace `branding/app-icon.svg` with your artwork. It must have an explicit opaque top-level background rectangle (`fill="#RRGGBB"`). The generator rasterizes to an opaque 1024 px App Store icon. Point `app_icon` to this repository-local file. Change `theme_tokens` to your light/dark semantic token JSON if rebranding the theme; preserve all semantic roles.
4. Install Xcode, XcodeGen, Python 3.10+, and librsvg (`brew install xcodegen librsvg`). Run `python3 scripts/generate.py` then `xcodegen generate`. `Brand.xcconfig`, Swift constants, adaptive color assets, icons and staging schema are generated and ignored. Open the generated `SpaceWorks.xcodeproj`. Never edit or commit it.
5. Enroll your organization in the Apple Developer Program, register the bundle ID, and choose your signing team in your private build environment. Later phases enable App Attest and Push Notifications capabilities using your own identifiers.
6. Create an APNs key in your own Apple account and configure it privately on your server when A4 is implemented. iOS uses APNs directly; it does not need a Firebase project. Self-hosters publishing Android separately need their own Firebase project for Android FCM.
7. Inject signing certificates/provisioning profiles and `.p8` files from CI secrets. Never commit keys, tokens, provisioning files, or `google-services.json`. This repo's simulator CI needs no signing credentials.
8. Run the CI checks and archive a Release build using your Apple signing configuration. Check your deployment URL, dark/light themes, VoiceOver and the largest Dynamic Type size on a device. Supply support/privacy URLs and your own App Store privacy declarations, screenshots and reviewer demo account.
9. Upload to your App Store Connect account and TestFlight first. A8 covers publication after every earlier phase is merged and tested. A0 is not store-ready and does not implement authentication, attestation, push or payments.

The platform system font remains in use. Obtain explicit Gilroy app-embedding permission before converting and bundling the supplied brand webfonts. Brand assets retain their upstream licenses; this repo does not grant additional embedding rights.
