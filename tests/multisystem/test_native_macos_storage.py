"""Native APFS gate; run against a staged preset with KAI_NATIVE_PRESET."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == 'darwin' and os.environ.get('KAI_NATIVE_PRESET'),
                     'requires a staged preset on native macOS')
class NativeMacStorageTests(unittest.TestCase):
    def test_writable_data_directory_is_eligible_and_uses_its_actual_mount(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('KAI_NATIVE_WORK')) as folder:
            root = Path(folder)
            (root / 'write-probe').write_text('keep')
            helper = Path(os.environ['KAI_NATIVE_PRESET']) / 'skills/kai-storage-files/scripts/usage.sh'
            result = subprocess.run(['/bin/bash', str(helper), 'storage', str(root), '1'],
                env={**os.environ, 'KAI_PLATFORM':'macos', 'KAI_USAGE_PYTHON':sys.executable},
                text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(result.stdout)
            self.assertFalse(data['facts']['read_only'], data)
            self.assertTrue(data['eligibleForInstall'], data)
            actual = subprocess.check_output(['/bin/df', '-P', str(root)], text=True)
            mount = actual.splitlines()[-1].split(None, 5)[5]
            self.assertEqual(data['facts']['mount_point'], mount, data)
            self.assertEqual((root / 'write-probe').read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
