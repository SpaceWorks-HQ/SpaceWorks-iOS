# Localization readiness

English is the current development language. No additional language is claimed as translated.

App-owned UI copy lives in `SpaceWorks/Resources/Localizable.xcstrings`. Use literal SwiftUI labels, `LocalizedStringKey` for wrappers that only accept application labels, and `String(localized:)` before storing locally authored state messages. Keep user names, makerspace names, product descriptions, API details, identifiers and URLs verbatim; never reinterpret a server message as a localization key.

Run `python scripts/export_localization_catalog.py` after changing plain local labels. This seeds English keys and preserves existing translations. Xcode's string extraction handles interpolation and plural forms; use its localization editor/export flow to review format arguments and add languages. The seed script deliberately does not infer translations or parse API/fixture data.

The API package uses its own `Resources/en.lproj/Localizable.strings` and `Bundle.module` for application fallback errors. Detailed errors received from the server remain unchanged. Native purpose copy is in `SpaceWorks/Resources/en.lproj/InfoPlist.strings`; keep its English camera purpose aligned with the generated Info.plist.

Before adding a language, translate both app and API resources, review plural/number/date formatting, and run the phone/tablet matrix with the new language, largest Dynamic Type, and right-to-left layout where applicable. A translated text resource alone is not UI validation.

References: [Apple: preparing text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation), [Apple: localizing package resources](https://developer.apple.com/documentation/xcode/localizing-package-resources).
