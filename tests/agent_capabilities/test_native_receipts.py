import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/agent_capabilities'))
spec = importlib.util.spec_from_file_location('native_readonly_review', ROOT / 'tools/agent_capabilities/native_readonly.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class NativeReceiptTests(unittest.TestCase):
    def test_preservation_does_not_turn_partial_nonzero_query_into_full_pass(self):
        self.check(1, 'partial', {'hasMore': True}, [{'code': 'FILE_WINDOW_LIMIT'}], False)

    def test_complete_success_remains_a_pass(self):
        self.check(0, 'succeeded', {'content': 'native source', 'hasMore': False}, [], True)

    def check(self, code, status, init, errors, passed):
        receipt = {'operationStatus': status, 'facts': {'initScript': init}, 'errors': errors}
        config = {'host': 'example.invalid', 'user': 'test', 'knownHosts': '/not-used'}
        process = subprocess.CompletedProcess([], code, b'{}', b'KA3_PRESERVATION=passed')
        with tempfile.TemporaryDirectory() as temporary, \
                mock.patch.object(native, 'payload', return_value=('synthetic', {})), \
                mock.patch.object(native.subprocess, 'run', return_value=process), \
                mock.patch.object(native, 'validate_result', return_value=receipt):
            output = Path(temporary)
            self.assertEqual(native.run('istoreos-opkg', config, output), passed)
            record = json.loads((output / 'istoreos-opkg.json').read_text())
            self.assertEqual(record['preservationStatus'], 'passed')
            self.assertEqual(record['status'], 'passed' if passed else 'partial')


if __name__ == '__main__':
    unittest.main()
