import contextlib
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).parents[1] / 'device-matrix.py'
spec = importlib.util.spec_from_file_location('device_matrix', MODULE_PATH)
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


class DeviceMatrixTests(unittest.TestCase):
    def test_unknown_profile_fails_before_invoking_simulator(self):
        with patch.object(matrix, 'simctl') as simulator:
            with self.assertRaises(SystemExit):
                matrix.select('unknown')
            simulator.assert_not_called()

    def test_tablet_never_silently_falls_back_to_phone(self):
        def simulator(*args):
            if args[1] == 'runtimes':
                return json.dumps({'runtimes': [{'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-18-5', 'version': '18.5', 'isAvailable': True}]})
            return json.dumps({'devicetypes': [{'name': 'iPhone 16', 'identifier': 'phone-type'}]})
        with patch.object(matrix, 'simctl', side_effect=simulator):
            with self.assertRaisesRegex(SystemExit, 'No compatible requested simulator hardware'):
                matrix.select('tablet')

    def test_landscape_tablet_records_accessibility_and_requested_hardware(self):
        calls = []
        def simulator(*args):
            calls.append(args)
            if args[:2] == ('list', 'runtimes'):
                return json.dumps({'runtimes': [{'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-18-5', 'version': '18.5', 'isAvailable': True}]})
            if args[:2] == ('list', 'devicetypes'):
                return json.dumps({'devicetypes': [{'name': 'iPad Pro 11-inch (M4)', 'identifier': 'tablet-type'}]})
            return 'test-simulator' if args[0] == 'create' else ''
        previous = pathlib.Path.cwd()
        with tempfile.TemporaryDirectory() as folder:
            try:
                os.chdir(folder)
                with patch.dict(os.environ, {'GITHUB_ENV': str(pathlib.Path(folder) / 'env')}), patch.object(matrix, 'simctl', side_effect=simulator), contextlib.redirect_stdout(io.StringIO()):
                    matrix.select('tablet-landscape')
                evidence = json.loads(pathlib.Path('validation-device.json').read_text())
                self.assertEqual(evidence['name'], 'iPad Pro 11-inch (M4)')
                self.assertTrue(evidence['landscape_required'])
                self.assertIn(('ui', 'test-simulator', 'content_size', 'accessibility-extra-extra-extra-large'), calls)
                self.assertIn('SIMULATOR_ID=test-simulator', pathlib.Path('env').read_text())
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
