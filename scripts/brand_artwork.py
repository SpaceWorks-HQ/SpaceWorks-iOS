"""Select explicit owner artwork without modifying the pinned Design masters."""
from pathlib import Path
import struct

DEFAULTS = {
    'logo_horizontal_one_colour_ink': ('Wordmark', 'light.png', 'lockup-horizontal-one-colour-ink.png'),
    'logo_horizontal_reversed': ('Wordmark', 'dark.png', 'lockup-horizontal-reversed.png'),
    'logo_stacked': ('BrandStacked', 'light.png', 'lockup-stacked.png'),
    'logo_stacked_reversed': ('BrandStacked', 'dark.png', 'lockup-stacked-reversed.png'),
    'logo_symbol': ('BrandSymbol', 'light.png', 'symbol.png'),
    'logo_symbol_reversed': ('BrandSymbol', 'dark.png', 'symbol-reversed.png'),
}
PAIRS = [('logo_horizontal_one_colour_ink', 'logo_horizontal_reversed'),
         ('logo_stacked', 'logo_stacked_reversed'), ('logo_symbol', 'logo_symbol_reversed')]


def selected_artwork(root, brand):
    root = Path(root).resolve()
    for light, dark in PAIRS:
        if (brand.get(light) is not None) != (brand.get(dark) is not None):
            raise ValueError(f'Configure both {light} and {dark}, or leave both unset')
    result = []
    for key, (asset, filename, master) in DEFAULTS.items():
        configured = brand.get(key)
        if configured is not None and (not isinstance(configured, str) or not configured):
            raise ValueError(f'{key} must name a repository-local PNG file')
        path = (root / (configured if configured is not None else 'design/logo/' + master)).resolve()
        if not path.is_relative_to(root) or path.suffix.lower() != '.png' or not path.is_file():
            raise ValueError(f'{key} must name an existing repository-local PNG file')
        if path.stat().st_size > 20 * 1024 * 1024:
            raise ValueError(f'{key} exceeds the 20 MiB artwork limit')
        with path.open('rb') as stream:
            header = stream.read(33)
        if len(header) < 33 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
            raise ValueError(f'{key} must be PNG artwork')
        width, height = struct.unpack('>II', header[16:24])
        if not 48 <= width <= 8192 or not 48 <= height <= 8192:
            raise ValueError(f'{key} must have dimensions from 48 through 8192 pixels')
        result.append((asset, filename, path))
    return result


def artwork_flags(brand):
    return {'hasCustomSymbol': brand.get('logo_symbol') is not None,
            'hasCustomStacked': brand.get('logo_stacked') is not None,
            'hasCustomWordmark': brand.get('logo_symbol') is not None or brand.get('logo_stacked') is not None}
