import copy
import hashlib
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("motion", ROOT / "scripts/generate_motion.py")
motion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(motion)


class MotionTests(unittest.TestCase):
    def test_generated_native_motion_matches_local_contract(self):
        document = json.loads((ROOT / "tokens/mobile-motion.json").read_text())
        output = motion.render_motion(document)
        self.assertEqual(output, (ROOT / "SpaceWorks/Generated/MobileMotion.swift").read_text())
        self.assertIn(f'static let expand: Double = {document["duration_ms"]["expand"] / 1000:g}', output)

    def test_motion_rejects_logo_animation_and_reduced_motion_delays(self):
        original = json.loads((ROOT / "tokens/mobile-motion.json").read_text())
        for section, key, invalid in [("onboarding", "logo_motion", "scale"), ("onboarding", "blocking_delay_ms", 100),
                                      ("reduce_motion", "opacity_duration_ms", 120), ("reduce_motion", "spatial_transitions", True)]:
            document = copy.deepcopy(original)
            document[section][key] = invalid
            with self.assertRaises(ValueError):
                motion.render_motion(document)

    def test_native_logo_assets_preserve_configured_source_bytes_in_both_appearances(self):
        artwork_spec = importlib.util.spec_from_file_location("artwork", ROOT / "scripts/brand_artwork.py")
        artwork = importlib.util.module_from_spec(artwork_spec)
        artwork_spec.loader.exec_module(artwork)
        brand = json.loads((ROOT / "branding/brand.json").read_text())
        for asset, filename, source in artwork.selected_artwork(ROOT, brand):
            self.assertEqual((ROOT / f"SpaceWorks/Assets.xcassets/{asset}.imageset/{filename}").read_bytes(), source.read_bytes())

    def test_native_accent_font_has_recorded_license_and_provenance(self):
        font = ROOT / "SpaceWorks/Resources/Fonts/Unbounded-Variable.ttf"
        self.assertEqual(hashlib.sha256(font.read_bytes()).hexdigest(), "87526b420190c9008a880bbf1780ab8c1563d55abb772a9cc6ed7e7b81306c3d")
        self.assertEqual((font.parent / "OFL-Unbounded.txt").read_bytes(), (ROOT / "design/fonts/LICENSES/OFL-Unbounded.txt").read_bytes())
