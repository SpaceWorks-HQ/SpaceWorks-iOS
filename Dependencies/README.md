# Reviewed build dependencies

`Package.resolved` is the unmodified Xcode lock exported from actual source
`47e1880a5c7fe549608e2a38cba789d47cf152dc`, focused run
[39100123222](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/actions/runs/39100123222),
artifact 12125599794. SHA-256:
`4a0c17f8dbe46c87952310b079a07b89481d715af79b17a2d164581e7b7b2aa0`.
Its 20 version/revision pins include the direct and transitive app/code-generator dependencies.
The package/project declarations were unchanged at `775f298`. This provenance is an actual focused
build, not a claim that the old source passed complete final validation.

Following [Apple's CI guidance](https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows),
after generating the Xcode project run `python3 scripts/dependency_lock.py stage`.
Xcode builds use `-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile`.
`python3 scripts/dependency_lock.py check` rejects any byte change to the resulting workspace lock.
CI caches include the canonical lock's hash and archive both the observed lock and verification.
The generated project remains ignored; do not commit a generated Xcode project to retain the lock.

For an intentional dependency update, change the declared exact versions, resolve explicitly on
the pinned Xcode installation in a reviewed development checkout, inspect every changed version,
revision and upstream repository, then replace this canonical lock. Run the complete source/native,
device-profile and unsigned Release/resource gates. Never accept an automatically rewritten lock,
silently update a package, or treat an SDK compile as live provider/backend verification.

`build-tools.json` records XcodeGen 2.46.0 and librsvg 2.62.3 from the actual published installation
log. CI checks these versions after installation and records actual executable version output;
it fails closed if a future Homebrew install selects a different version. This does not promise
that Homebrew will retain an older formula. Review a deliberate toolchain update and its generated
assets instead of upgrading the expected version merely to make a check pass. Xcode 26.2 remains
the separately pinned Apple toolchain.

Dependencies and supplied fonts/assets retain their own applicable licenses. This file grants no
additional license or embedding rights and does not choose an application repository license.
