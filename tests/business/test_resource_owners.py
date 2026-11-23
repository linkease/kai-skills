import hashlib
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]

class IndependentOwnerTests(unittest.TestCase):
    def test_shared_task_sync_preserves_separately_pinned_scoop_owner(self):
        subprocess.run([sys.executable, '-B', str(ROOT / 'tools/sync-software-owner.py'),
                        '--source', str(ROOT.parent / 'zsetup-scripts'), '--check'], check=True)
        for directory in [ROOT / 'components/system-packs/common/skills/kai-software', ROOT / 'skills/kai-software']:
            resources = directory / 'resources'
            lock = json.loads((resources / 'scoop-owner.lock.json').read_text())
            payload = (resources / lock['path']).read_bytes()
            self.assertEqual(len(payload), lock['size'])
            self.assertEqual(hashlib.sha256(payload).hexdigest(), lock['sha256'])

if __name__ == '__main__':
    unittest.main()
