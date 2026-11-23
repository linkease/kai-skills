import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'components/system-packs/common/skills/kai-software/scripts'

class SoftwareModuleTests(unittest.TestCase):
    def setUp(self):
        self.pwsh = os.environ.get('KAI_DESKTOP_PWSH') or shutil.which('pwsh')
        if not self.pwsh:
            self.skipTest('native PowerShell required')

    def test_market_definitions_load_without_dispatching_or_reading_stdin(self):
        path = str(SCRIPTS / 'market.ps1').replace("'", "''")
        result = subprocess.run([self.pwsh, '-NoProfile', '-NonInteractive', '-Command',
            ". '" + path + "'; foreach($name in @('Market-Plan','Market-ApplyPackages','Market-Inventory')){if(!(Get-Command $name -ErrorAction SilentlyContinue)){throw 'missing module function'}}"],
            input='', text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changed_modules_fail_before_dispatch(self):
        for entry, module in [('market.ps1', 'market/plan.ps1'), ('scoop.ps1', 'scoop/client.ps1')]:
            with self.subTest(entry=entry), tempfile.TemporaryDirectory(prefix='software modules ') as temporary:
                scripts = Path(temporary) / 'scripts'
                shutil.copytree(SCRIPTS, scripts)
                with (scripts / module).open('a') as f:
                    f.write('\nthrow "tampered module executed"\n')
                result = subprocess.run([self.pwsh, '-NoProfile', '-NonInteractive', '-File', str(scripts / entry)],
                    input='{}', text=True, capture_output=True, timeout=15)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Software module integrity mismatch', result.stderr)
                self.assertNotIn('tampered module executed', result.stdout)

if __name__ == '__main__':
    unittest.main()
