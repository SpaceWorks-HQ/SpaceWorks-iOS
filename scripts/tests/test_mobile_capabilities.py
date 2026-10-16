import importlib.util
import json
import plistlib
import shutil
import tempfile
from unittest import mock
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("capabilities", ROOT / "scripts/mobile_capabilities.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CapabilityTests(unittest.TestCase):
    def test_unconfigured_build_has_no_apns_or_invented_domains(self):
        self.assertEqual(module.capabilities({}, "Debug"), {})
        self.assertEqual(module.capabilities({"aps_environment": None, "associated_domains": []}, "Release"), {})

    def test_explicit_owner_configuration_preserves_domains_and_separates_debug_environment(self):
        brand = {"ios_team_id": "ABC1234567", "aps_environment": "production", "associated_domains": ["applinks:lab.example", "webcredentials:lab.example"]}
        debug = module.capabilities(brand, "Debug")
        release = module.capabilities(brand, "Release")
        self.assertEqual(debug["aps-environment"], "development")
        self.assertEqual(release["aps-environment"], "production")
        self.assertEqual(release["com.apple.developer.associated-domains"], brand["associated_domains"])

    def test_prebuild_preserves_explicit_capabilities_and_removes_disabled_ones(self):
        generation_spec = importlib.util.spec_from_file_location("capability_generation", ROOT / "scripts/generate.py")
        generator = importlib.util.module_from_spec(generation_spec)
        generation_spec.loader.exec_module(generator)
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory).resolve()
            for relative in ["branding/brand.json", "api/openapi.json", "api/provenance.json", "tokens/mobile-motion.json", "design/tokens/tokens.json"]:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            shutil.copytree(ROOT / "scripts", root / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
            shutil.copytree(ROOT / "Fixtures/Member", root / "Fixtures/Member")
            brand_file = root / "branding/brand.json"
            brand = json.loads(brand_file.read_text(encoding="utf-8"))
            brand.update(ios_team_id="ABC1234567", aps_environment="production", associated_domains=["applinks:lab.example"])
            brand_file.write_text(json.dumps(brand), encoding="utf-8")
            with mock.patch.object(generator, "ROOT", root), mock.patch.object(generator.shutil, "copyfile"):
                generator.generate(raster=False)
                for mode, environment in [("Debug", "development"), ("Release", "production")]:
                    values = plistlib.loads((root / f"SpaceWorks/Generated/Attestation-{mode}.entitlements").read_bytes())
                    self.assertEqual(values["aps-environment"], environment)
                    self.assertEqual(values["com.apple.developer.associated-domains"], ["applinks:lab.example"])
                self.assertNotIn("aps-environment", plistlib.loads((root / "SpaceWorks/Generated/Simulator.entitlements").read_bytes()))
                self.assertIn("pushConfigured = true", (root / "SpaceWorks/Generated/Brand.swift").read_text())
                brand.update(aps_environment=None, associated_domains=[])
                brand_file.write_text(json.dumps(brand), encoding="utf-8")
                generator.generate(raster=False)
                values = plistlib.loads((root / "SpaceWorks/Generated/Attestation-Release.entitlements").read_bytes())
                self.assertNotIn("aps-environment", values)
                self.assertNotIn("com.apple.developer.associated-domains", values)
                self.assertIn("pushConfigured = false", (root / "SpaceWorks/Generated/Brand.swift").read_text())

    def test_invalid_domains_team_and_environment_are_rejected(self):
        for value in ["applinks:*.example", "https://lab.example", "applinks:lab.example/path", "applinks:lab.example:443", "applinks:lab.example?mode=developer", "applinks:localhost", "applinks:user@lab.example"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.capabilities({"ios_team_id": "ABC1234567", "associated_domains": [value]}, "Release")
        for brand in [{"aps_environment": "development"}, {"aps_environment": "production"}, {"associated_domains": ["applinks:lab.example"]}]:
            with self.assertRaises(ValueError):
                module.capabilities(brand, "Debug")


if __name__ == "__main__":
    unittest.main()
