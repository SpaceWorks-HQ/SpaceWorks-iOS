import hashlib
import importlib.util
import json
import pathlib
import struct
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("generate", ROOT / "scripts/generate.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class GenerationTests(unittest.TestCase):
    def test_authoritative_contract_is_unchanged_and_staged_for_plugin(self):
        source = (ROOT / "api/openapi.json").read_bytes()
        self.assertEqual(hashlib.sha256(source).hexdigest(), json.loads((ROOT / "api/provenance.json").read_text())["sha256"])
        staged = json.loads((ROOT / "Packages/SpaceWorksAPI/Sources/SpaceWorksAPI/openapi.json").read_bytes())
        expected = json.loads(source)
        content = expected["paths"]["/api/v1/auth/device/refresh"]["post"]["requestBody"]["content"]
        expected["paths"]["/api/v1/auth/device/refresh"]["post"]["requestBody"]["content"] = {"application/json": content["application/json"]}
        self.assertEqual(staged, expected, "Only refresh's documented JSON representation may be selected; all models must remain unchanged")
        self.assertEqual(len(json.loads(source)["paths"]), 635)

    def test_brand_config_drives_project_display_name_bundle_and_icon(self):
        brand = json.loads((ROOT / "branding/brand.json").read_text())
        config = (ROOT / "Brand.xcconfig").read_text()
        self.assertIn(f"BRAND_BUNDLE_ID = {brand['ios_bundle_id']}", config)
        self.assertIn(f"BRAND_DISPLAY_NAME = {brand['app_name']}", config)
        project = (ROOT / "project.yml").read_text()
        self.assertIn("$(BRAND_BUNDLE_ID)", project)
        self.assertIn("$(BRAND_DISPLAY_NAME)", project)
        self.assertIn("Brand.xcconfig", project)
        self.assertIn("AppIcon", project)
        self.assertEqual((ROOT / brand["app_icon"]).read_bytes(), (ROOT / "design/logo/app-icon.svg").read_bytes())
        icon = ROOT / "SpaceWorks/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        if icon.exists():
            data = icon.read_bytes()
            self.assertEqual(struct.unpack(">II", data[16:24]), (1024, 1024))
            self.assertEqual(data[25], 2, "App Store icon must be opaque RGB")

    def test_every_semantic_role_has_both_appearances(self):
        tokens = json.loads((ROOT / "design/tokens/tokens.json").read_text())
        for role in tokens["light"]:
            asset = json.loads((ROOT / f"SpaceWorks/Assets.xcassets/{role}.colorset/Contents.json").read_text())
            for index, mode in enumerate(["light", "dark"]):
                rgb = asset["colors"][index]["color"]["components"]
                actual = "#" + "".join(rgb[k][2:] for k in ["red", "green", "blue"])
                self.assertEqual(actual.upper(), tokens[mode][role].upper())
        self.assertEqual(tokens["light"]["bg"], "#FFF4E8")
        self.assertEqual(tokens["dark"]["bg"], "#142C2A")

    def test_theme_and_brand_generation_are_deterministic(self):
        paths = [ROOT / "SpaceWorks/Generated/Theme.swift", ROOT / "SpaceWorks/Generated/Brand.swift", ROOT / "Brand.xcconfig"]
        before = [p.read_bytes() for p in paths]
        generator.generate(raster=False)
        self.assertEqual(before, [p.read_bytes() for p in paths])

    def test_key_ui_text_pairs_meet_contrast_floor(self):
        def luminance(code):
            rgb = [int(code[i:i+2], 16) / 255 for i in [1, 3, 5]]
            linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
            return sum(a * b for a, b in zip(linear, [.2126, .7152, .0722]))
        tokens = json.loads((ROOT / "design/tokens/tokens.json").read_text())
        for mode in ["light", "dark"]:
            for ink, bg in [("ink", "bg"), ("muted", "bg"), ("accent-ink", "surface"), ("on-accent", "accent")]:
                values = sorted([luminance(tokens[mode][ink]), luminance(tokens[mode][bg])])
                self.assertGreaterEqual((values[1] + .05) / (values[0] + .05), 4.5)


if __name__ == "__main__":
    unittest.main()
