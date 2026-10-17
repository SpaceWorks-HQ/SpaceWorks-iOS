import hashlib
import json
from pathlib import Path
import plistlib
import struct
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]


def tables(data):
    result = {}
    if data[:4] == b'wOFF':
        count = struct.unpack_from('>H', data, 12)[0]
        for index in range(count):
            tag, offset, compressed, original, _ = struct.unpack_from('>4sIIII', data, 44 + index * 20)
            value = data[offset:offset + compressed]
            result[tag] = zlib.decompress(value) if compressed < original else value
    else:
        count = struct.unpack_from('>H', data, 4)[0]
        for index in range(count):
            tag, _, offset, length = struct.unpack_from('>4sIII', data, 12 + index * 16)
            result[tag] = data[offset:offset + length]
    # The SFNT checksum adjustment necessarily changes with the native container.
    result[b'head'] = result[b'head'][:8] + bytes(4) + result[b'head'][12:]
    return result


class BrandFontTests(unittest.TestCase):
    def test_native_containers_preserve_every_original_font_table_and_provenance(self):
        root = ROOT / 'SpaceWorks/Resources/Fonts'
        provenance = json.loads((root / 'Gilroy-provenance.json').read_text())
        self.assertEqual(len(provenance['faces']), 4)
        for face in provenance['faces']:
            source = (ROOT / face['source']).read_bytes()
            native = (root / face['native']).read_bytes()
            self.assertEqual(hashlib.sha256(source).hexdigest(), face['source_sha256'])
            self.assertEqual(hashlib.sha256(native).hexdigest(), face['native_sha256'])
            self.assertEqual(native[:4], b'\x00\x01\x00\x00')
            self.assertEqual(tables(source), tables(native), 'No glyph, name or metric table may change during conversion')

    def test_both_generated_app_configurations_register_every_bundled_brand_face(self):
        expected = {'Gilroy-Regular.ttf', 'Gilroy-Medium.ttf', 'Gilroy-SemiBold.ttf', 'Gilroy-Bold.ttf', 'Unbounded-Variable.ttf'}
        for configuration in ['Debug', 'Release']:
            info = plistlib.loads((ROOT / f'SpaceWorks/Generated/Info-{configuration}.plist').read_bytes())
            self.assertEqual(set(info['UIAppFonts']), expected)
        for name in expected:
            self.assertTrue((ROOT / 'SpaceWorks/Resources/Fonts' / name).is_file())
