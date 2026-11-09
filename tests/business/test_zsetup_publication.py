import filecmp
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT.parents[1] / 'zsetup-scripts'


class PublicationTests(unittest.TestCase):
    def test_publication_is_complete_verified_and_repeatable(self):
        with tempfile.TemporaryDirectory(prefix='kai publication 中文 ') as name:
            work = Path(name)
            release = work / 'release'
            subprocess.run([sys.executable, '-B', str(ROOT / 'tools/release/zsetup_release.py'),
                            'build', str(release)], check=True)
            installer = work / 'installer.sh'
            entries = work / 'entries'
            channel = work / 'channel-install.sh'
            subprocess.run([sys.executable, '-B', str(SCRIPTS / 'kai-skills/build.py'),
                            '--release', str(release), '--output', str(installer),
                            '--entrypoints-dir', str(entries),
                            ], check=True)
            subprocess.run([sys.executable, '-B', str(SCRIPTS / 'kai-skills/build.py'),
                            '--channel-only', '--channel-entrypoint', str(channel)], check=True)
            outputs = []
            for index in range(2):
                output = work / f'public-{index}'
                subprocess.run([sys.executable, '-B',
                                str(ROOT / 'tools/release/zsetup_publication.py'), 'build',
                                '--release', str(release), '--installer', str(installer),
                                '--entrypoints', str(entries),
                                '--channel-entrypoint', str(channel),
                                '--output', str(output)], check=True)
                subprocess.run([sys.executable, '-B',
                                str(ROOT / 'tools/release/zsetup_publication.py'),
                                'verify', str(output)], check=True)
                outputs.append(output)
            comparison = filecmp.dircmp(outputs[0], outputs[1])
            self.assertEqual((comparison.left_only, comparison.right_only, comparison.diff_files),
                             ([], [], []))
            version = json.loads((release / 'release-manifest.json').read_text())['version']
            self.assertEqual(len(list((outputs[0] / f'entrypoints/{version}/skills').glob('*.sh'))), 32)
            self.assertEqual(len(list((outputs[0] / f'entrypoints/{version}/systems').glob('*.sh'))), 2)
            public_entry = (outputs[0] / 'setup.sh').read_text()
            self.assertNotIn('KAI_SKILLS_REQUESTED_RELEASE=', public_entry)
            self.assertIn('bootstrap_zsetup', public_entry)
            self.assertEqual((outputs[0] / 'setup.sh').read_bytes(),
                             (outputs[0] / 'install.sh').read_bytes())


if __name__ == '__main__':
    unittest.main()
