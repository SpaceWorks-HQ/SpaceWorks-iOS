"""Record and verify the already tested generator versions; never install or upgrade tools."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def inspect():
    expected = json.loads((ROOT / 'Dependencies/build-tools.json').read_text(encoding='utf-8'))['versions']
    commands = {'xcodegen': ['xcodegen', '--version'], 'librsvg': ['rsvg-convert', '--version']}
    observed = {}
    for name, command in commands.items():
        output = subprocess.check_output(command, text=True).strip()
        match = re.search(r'\b\d+\.\d+\.\d+\b', output)
        observed[name] = {'output': output, 'version': match.group() if match else None}
    report = {'kind': 'actual-build-generator-versions', 'expected': expected, 'observed': observed,
              'matches': all(observed[name]['version'] == version for name, version in expected.items())}
    (ROOT / 'build-tools.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    if not report['matches']:
        raise SystemExit('Generator version differs from the reviewed build input; review the toolchain instead of accepting an automatic upgrade.')
    print('Reviewed generator versions verified.')


if __name__ == '__main__':
    inspect()
