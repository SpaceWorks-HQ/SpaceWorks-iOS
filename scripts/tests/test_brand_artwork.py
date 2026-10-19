from pathlib import Path
import importlib.util
import shutil
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('brand_artwork', HERE.parent / 'brand_artwork.py')
ART = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(ART)
ROOT = HERE.parents[1]

class ArtworkTests(unittest.TestCase):
    def make_root(self, root):
        (root / 'design/logo').mkdir(parents=True)
        for _, _, master in ART.DEFAULTS.values():
            shutil.copyfile(ROOT / 'design/logo' / master, root / 'design/logo' / master)
    def test_unconfigured_artwork_preserves_all_existing_masters(self):
        selected = ART.selected_artwork(ROOT, {})
        self.assertEqual(len(selected), 6)
        self.assertTrue(all('design' in path.parts for _, _, path in selected))
        self.assertFalse(any(ART.artwork_flags({}).values()))
    def test_custom_light_dark_artwork_is_selected_with_native_renderer_flags(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); self.make_root(root)
            (root / 'branding').mkdir()
            brand = {}
            for key, (_, _, master) in ART.DEFAULTS.items():
                brand[key] = 'branding/' + key + '.png'
                shutil.copyfile(root / 'design/logo' / master, root / brand[key])
            selected = ART.selected_artwork(root, brand)
            self.assertTrue(all('branding' in path.parts for _, _, path in selected))
            self.assertTrue(all(ART.artwork_flags(brand).values()))
            self.assertEqual({(asset, name) for asset, name, _ in selected},
                             {('Wordmark', 'light.png'), ('Wordmark', 'dark.png'), ('BrandStacked', 'light.png'), ('BrandStacked', 'dark.png'), ('BrandSymbol', 'light.png'), ('BrandSymbol', 'dark.png')})
    def test_partial_pair_missing_file_escape_and_non_png_fail_before_use(self):
        for brand in ({'logo_symbol':'design/logo/symbol.png'},
                      {'logo_symbol':'../outside.png','logo_symbol_reversed':'design/logo/symbol.png'},
                      {'logo_stacked':'missing.png','logo_stacked_reversed':'missing.png'},
                      {'logo_stacked':True,'logo_stacked_reversed':False},
                      {'logo_symbol':'design/logo/symbol.svg','logo_symbol_reversed':'design/logo/symbol-reversed.png'}):
            with self.subTest(brand=brand), self.assertRaises(ValueError): ART.selected_artwork(ROOT, brand)
    def test_single_custom_pair_does_not_claim_other_asset_was_customized(self):
        brand={'logo_stacked':'design/logo/lockup-stacked.png','logo_stacked_reversed':'design/logo/lockup-stacked-reversed.png'}
        self.assertEqual(ART.artwork_flags(brand), {'hasCustomSymbol':False,'hasCustomStacked':True,'hasCustomWordmark':True})

if __name__ == '__main__': unittest.main()
