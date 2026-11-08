import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

COMMON = Path(__file__).resolve().parents[2] / 'components/system-packs/common/skills'


class SoftwareTaskResources(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        for name in ['kai-software', 'kai-tool-bootstrap']:
            shutil.copytree(COMMON / name, self.root / name)
        self.request = self.root / 'request.json'
        self.request.write_text(json.dumps({'software': 'bash', 'targetId': 'resource-test'}))

    def call(self):
        return subprocess.run(
            ['bash', str(self.root / 'kai-software/scripts/software-task.sh'), 'query', str(self.request)],
            env={**os.environ, 'ZSETUP_TASK_TARGET_ID': 'resource-test'},
            text=True, capture_output=True,
        )

    def test_distributed_owner_runs_without_a_sibling_checkout(self):
        actual = self.call()
        self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
        result = json.loads(actual.stdout)
        self.assertEqual(result['protocol'], 'software-task/v1')
        self.assertEqual(result['targetId'], 'resource-test')
        self.assertTrue(result['details']['satisfies'])

    def test_changed_owner_is_rejected_before_any_owner_instruction_runs(self):
        marker = self.root / 'unwanted'
        script = self.root / 'kai-software/resources/owner/software/task.sh'
        self.assertTrue(script.is_file(), 'owner resources must be distributed')
        script.write_text('#!/bin/bash\ntouch ' + repr(str(marker)) + '\n')
        actual = self.call()
        self.assertEqual(actual.returncode, 21, actual.stdout + actual.stderr)
        self.assertEqual(json.loads(actual.stdout)['reason'], 'owner-resource-integrity')
        self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
