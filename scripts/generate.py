"""Generate native branding and light/dark assets, and stage the authoritative API contract.

Only Python's standard library plus the build-time rsvg-convert executable are required.
Run before xcodegen generate, and again automatically before app builds.
"""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def inside(relative):
    path = (ROOT / relative).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError("Brand assets must stay inside the repository")
    return path


def generate(raster=True):
    brand = json.loads((ROOT / "branding/brand.json").read_text())
    for key in ["ios_bundle_id", "ios_team_id"]:
        if not re.fullmatch(r"[A-Za-z0-9.-]*", brand[key]):
            raise ValueError(f"Invalid {key}")
    if not brand["ios_bundle_id"] or any(ord(c) < 32 for c in brand["app_name"]) or any(c in brand["app_name"] for c in '$#;\\') or "//" in brand["app_name"]:
        raise ValueError("Invalid app name or bundle ID")
    if brand["server_url"] is not None:
        from urllib.parse import urlsplit
        u = urlsplit(brand["server_url"])
        if u.scheme != "https" or not u.hostname or u.username or u.password or u.path not in ["", "/"] or u.query or u.fragment:
            raise ValueError("Locked server_url must be an HTTPS origin")
    write(ROOT / "Brand.xcconfig", "// Generated from branding/brand.json.\n"
          + f"BRAND_BUNDLE_ID = {brand['ios_bundle_id']}\n"
          + f"BRAND_DISPLAY_NAME = {brand['app_name']}\n"
          + f"BRAND_TEAM_ID = {brand['ios_team_id']}\n")
    swift_literal = lambda value: "nil" if value is None else json.dumps(value, ensure_ascii=False)
    write(ROOT / "SpaceWorks/Generated/Brand.swift", "// Generated. Do not edit.\nimport Foundation\nenum Brand {\n"
          + "\n".join(f"    static let {name}: String{'?' if key in ['server_url', 'support_url', 'privacy_url'] else ''} = {swift_literal(brand[key])}"
                      for name, key in [("appName", "app_name"), ("bundleID", "ios_bundle_id"), ("serverURL", "server_url"), ("supportURL", "support_url"), ("privacyURL", "privacy_url")])
          + "\n}\n")
    for mode in ["Debug", "Release"]:
        info = {"CFBundleDisplayName": brand["app_name"], "UILaunchScreen": {}, "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False}}
        info["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
        info["UISupportedInterfaceOrientations~ipad"] = info["UISupportedInterfaceOrientations"] + ["UIInterfaceOrientationPortraitUpsideDown"]
        if mode == "Debug":
            info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
        target = ROOT / f"SpaceWorks/Generated/Info-{mode}.plist"
        target.write_bytes(plistlib.dumps(info))
        (ROOT / f"SpaceWorks/Generated/Attestation-{mode}.entitlements").write_bytes(plistlib.dumps({
            "com.apple.developer.devicecheck.appattest-environment": "development" if mode == "Debug" else "production"}))
    tokens = json.loads(inside(brand["theme_tokens"]).read_text())
    if set(tokens["light"]) != set(tokens["dark"]):
        raise ValueError("Light and dark semantic roles must match")
    assets = ROOT / "SpaceWorks/Assets.xcassets"
    write(assets / "Contents.json", json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    declarations = []
    for role, light in tokens["light"].items():
        name = "sw" + "".join(w.title() for w in role.split("-"))
        declarations.append(f'    static let {name} = Color("{role}")')
        colors = []
        for mode in ["light", "dark"]:
            color = tokens[mode][role]
            if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
                raise ValueError(f"Invalid token {mode}.{role}")
            entry = {"idiom": "universal", "color": {"color-space": "srgb", "components": {
                "red": "0x" + color[1:3], "green": "0x" + color[3:5], "blue": "0x" + color[5:7], "alpha": "1.000"}}}
            if mode == "dark":
                entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
            colors.append(entry)
        write(assets / f"{role}.colorset/Contents.json", json.dumps({"colors": colors, "info": {"author": "xcode", "version": 1}}, indent=2))
    write(ROOT / "SpaceWorks/Generated/Theme.swift", "// Generated from semantic tokens, both appearances.\nimport SwiftUI\nextension Color {\n" + "\n".join(declarations) + "\n}\n")
    wordmark = assets / "Wordmark.imageset"
    wordmark.mkdir(parents=True, exist_ok=True)
    for name, master in [("light.png", "lockup-horizontal-one-colour-ink.png"), ("dark.png", "lockup-horizontal-reversed.png")]:
        shutil.copyfile(ROOT / "design/logo" / master, wordmark / name)
    write(wordmark / "Contents.json", json.dumps({"images": [{"idiom": "universal", "filename": "light.png"},
        {"idiom": "universal", "filename": "dark.png", "appearances": [{"appearance": "luminosity", "value": "dark"}]}],
        "info": {"author": "xcode", "version": 1}}))
    icon = assets / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    if raster:
        source = inside(brand["app_icon"])
        rect = ET.parse(source).getroot().find("{http://www.w3.org/2000/svg}rect")
        background = rect.get("fill") if rect is not None else None
        if not background or not re.fullmatch(r"#[0-9A-Fa-f]{6}", background):
            raise ValueError("App icon must define its opaque background as a top-level rect fill")
        subprocess.run(["rsvg-convert", "--background-color", background, "-w", "1024", "-h", "1024", "-o", str(icon / "AppIcon.png"), str(source)], check=True)
    write(icon / "Contents.json", json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))
    schema = ROOT / "api/openapi.json"
    expected = json.loads((ROOT / "api/provenance.json").read_text())["sha256"]
    if hashlib.sha256(schema.read_bytes()).hexdigest() != expected:
        raise ValueError("API contract hash differs from its recorded provenance")
    # Apple's generator models any multipart root component as a multipart enum. The supplied
    # refresh schema references the SAME component for JSON and multipart; select its documented
    # JSON representation so that DeviceRefresh remains a generated Codable object. No fields,
    # operations or response schemas are changed, and the authoritative source stays untouched.
    document = json.loads(schema.read_bytes())
    for operations in document["paths"].values():
        for operation in operations.values():
            if not isinstance(operation, dict):
                continue
            content = operation.get("requestBody", {}).get("content", {})
            if "application/json" in content:
                operation["requestBody"]["content"] = {"application/json": content["application/json"]}
    write(ROOT / "Packages/SpaceWorksAPI/Sources/SpaceWorksAPI/openapi.json", json.dumps(document, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-raster", action="store_true", help="Only for generator tests on hosts without librsvg")
    generate(not parser.parse_args().no_raster)
