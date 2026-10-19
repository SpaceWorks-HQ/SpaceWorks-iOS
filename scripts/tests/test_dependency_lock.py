import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dependency_lock', ROOT / 'scripts/dependency_lock.py')
lock = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lock)


class DependencyLockTests(unittest.TestCase):
    def testReviewedArtifactIsStagedByteForByte(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'generated/workspace/Package.resolved'
            lock.stage(ROOT / 'Dependencies/Package.resolved', target)
            self.assertEqual(target.read_bytes(), (ROOT / 'Dependencies/Package.resolved').read_bytes())
            self.assertTrue(lock.check(ROOT / 'Dependencies/Package.resolved', target)['byte_identical'])

    def testChangedTransitiveRevisionIsRejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'Package.resolved'
            lock.stage(ROOT / 'Dependencies/Package.resolved', target)
            changed = json.loads(target.read_text(encoding='utf-8'))
            changed['pins'][0]['state']['revision'] = '0' * 40
            target.write_text(json.dumps(changed), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'differs from the reviewed'):
                lock.check(ROOT / 'Dependencies/Package.resolved', target)

    def testMalformedSourceDoesNotReplaceWorkspace(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'unreviewed.json'
            source.write_text('{"version":3,"pins":[]}', encoding='utf-8')
            target = Path(directory) / 'Package.resolved'
            target.write_bytes(b'existing workspace input')
            with self.assertRaises(ValueError):
                lock.stage(source, target)
            self.assertEqual(target.read_bytes(), b'existing workspace input')
