import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MilestoneManifestTests(unittest.TestCase):
    def test_execution_receipt_identifies_the_actual_dirty_source_tree(self):
        with tempfile.TemporaryDirectory(prefix='kai runner evidence ') as folder:
            result = subprocess.run(['sh', str(ROOT / 'tools/test-multisystem.sh'),
                                     '--milestone', 'MS5', '--suite', 'contract', '--report-dir', folder],
                                    capture_output=True, text=True, cwd=ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads((Path(folder) / 'result.json').read_text())
            self.assertRegex(report['cases'][0]['sourceTreeDigest'], r'^[0-9a-f]{64}$')

    def test_public_runner_exposes_complete_test_scope(self):
        result = subprocess.run(
            ['sh', str(ROOT / 'tools/test-multisystem.sh'), '--list', '--json'],
            capture_output=True, text=True, cwd=ROOT,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual({m['id'] for m in data['milestones']}, {f'MS{i}' for i in range(11)})
        self.assertGreaterEqual(len(data['routingCases']), 30)
        self.assertEqual(len({c['id'] for c in data['cases']}), len(data['cases']))
        self.assertTrue(all(c['expected'] and c['evidence'] for c in data['cases']))
        python = next(c for c in data['routingCases'] if c['task'] == '安装 Python' and c['platform'] == 'ubuntu')
        pip = next(c for c in data['routingCases'] if c['task'] == 'pip install requests' and c['platform'] == 'ubuntu')
        self.assertEqual(python['skill'], 'kai-dev-environment')
        self.assertEqual(pip['skill'], 'kai-project-dependencies')
        self.assertNotEqual(python['skill'], pip['skill'])


if __name__ == '__main__':
    unittest.main()
