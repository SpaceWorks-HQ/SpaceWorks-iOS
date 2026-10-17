# Native Space Works fonts

Gilroy Regular, Medium, Semibold and Bold are converted from the owner's supplied Design WOFF assets for app content, with Dynamic Type and explicit heavier faces for Bold Text. The owner requested these assets in the native apps; their inclusion remains subject to the applicable Gilroy license and does not grant an open-source redistribution license. Upstream names/outlines/metrics are preserved; the native container checksum necessarily changes. `Gilroy-provenance.json` records all source/native hashes. Every upstream OS/2 weight field is400, so the app selects the actual supplied PostScript face explicitly rather than relying on synthetic weight lookup.

Unbounded remains one short accent phrase per layout. Native navigation titles, system activities, security codes and identifiers retain native platform typography where needed. Gilroy is not substituted into the outlined logo masters.

`Unbounded-Variable.ttf` is the unmodified variable font outlines converted from the Design submodule's `fonts/Unbounded-Variable.woff2` container using fontTools 4.67.0 and Brotli. Its SIL Open Font License 1.1 is included alongside it; the font's family/PostScript names, glyphs and weight axis (200–900) are preserved. Conversion changes the web container into Apple's supported native TrueType container without renaming the font.

- Source SHA-256: `0c8f2e9da9dbcff90d9e2741cf5c59be72e83d76c206cfa3b95f291416752ee4`
- Native SHA-256: `87526b420190c9008a880bbf1780ab8c1563d55abb772a9cc6ed7e7b81306c3d`
- Registered PostScript name: `Unbounded-Regular`

The original Space Works logo masters are outlined artwork and do not use this font at runtime.
