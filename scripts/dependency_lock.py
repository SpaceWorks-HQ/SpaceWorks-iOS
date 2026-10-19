"""Stage and verify the reviewed Xcode dependency graph without resolving or updating it."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
CANONICAL = ROOT / 'Dependencies/Package.resolved'
WORKSPACE = ROOT / 'SpaceWorks.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'


def read_lock(path):
    data = Path(path).read_bytes()
    document = json.loads(data)
    if document.get('version') != 3 or not re.fullmatch(r'[0-9a-f]{64}', document.get('originHash', '')):
        raise ValueError('Expected the reviewed version-3 Xcode dependency lock')
    pins = document.get('pins', [])
    identities = [pin.get('identity') for pin in pins]
    if not pins or any(not isinstance(identity, str) or not identity for identity in identities) or len(set(identities)) != len(identities):
        raise ValueError('Dependency identities must be present and unique')
    for pin in pins:
        state = pin.get('state', {})
        if pin.get('kind') != 'remoteSourceControl' or not re.fullmatch(r'[0-9a-f]{40}', state.get('revision', '')) or not state.get('version'):
            raise ValueError('Every dependency must retain an exact reviewed version and revision')
    return data, document


def stage(source=CANONICAL, destination=WORKSPACE):
    read_lock(source)  # Refuse invalid input before touching the generated workspace.
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def check(source=CANONICAL, destination=WORKSPACE):
    expected, document = read_lock(source)
    actual, observed = read_lock(destination)
    if actual != expected:
        raise ValueError('Xcode dependency lock differs from the reviewed source input; review the change instead of resolving automatically')
    return {'kind': 'reviewed-dependency-lock-audit',
            'canonical_sha256': hashlib.sha256(expected).hexdigest(),
            'workspace_sha256': hashlib.sha256(actual).hexdigest(),
            'pins': len(document['pins']), 'origin_hash': observed['originHash'],
            'byte_identical': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['stage', 'check'])
    parser.add_argument('--output', type=Path, default=ROOT / 'dependency-lock-validation.json')
    args = parser.parse_args()
    if args.operation == 'stage':
        stage()
    else:
        report = check()
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print('Reviewed dependency lock retained without changes.')
