import filecmp
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT.parent / 'zsetup-scripts'


class PublicationTests(unittest.TestCase):
    def test_publication_is_complete_verified_and_repeatable(self):
        with tempfile.TemporaryDirectory(prefix='kai publication 中文 ') as name:
            work = Path(name)
            freeze_root = work / 'freeze'
            subprocess.run([sys.executable, '-B', str(ROOT / 'tools/release/freeze.py'),
                            'build', '--reasonix-root', str(ROOT.parent / 'reasonix-kai'),
                            '--output', str(freeze_root), '--version', '1.2.5-test',
                            '--allow-dirty-fixture'], check=True)
            release = freeze_root / 'zsetup'
            freeze_manifest = freeze_root / 'freeze-manifest.json'
            installer = work / 'installer.sh'
            entries = work / 'entries'
            channel = work / 'channel-install.sh'
            windows_installer = work / 'installer.ps1'
            windows_channel = work / 'setup.ps1'
            subprocess.run([sys.executable, '-B', str(SCRIPTS / 'apps/kai-skills/source/build.py'),
                            '--release', str(release), '--output', str(installer),
                            '--freeze-manifest', str(freeze_manifest), '--allow-fixture-freeze',
                            '--entrypoints-dir', str(entries),
                            '--windows-output', str(windows_installer),
                            ], check=True)
            subprocess.run([sys.executable, '-B', str(SCRIPTS / 'apps/kai-skills/source/build.py'),
                            '--channel-only', '--channel-entrypoint', str(channel),
                            '--windows-channel-entrypoint', str(windows_channel)], check=True)
            outputs = []
            for index in range(2):
                output = work / f'public-{index}'
                subprocess.run([sys.executable, '-B',
                                str(ROOT / 'tools/release/zsetup_publication.py'), 'build',
                                '--release', str(release), '--installer', str(installer),
                                '--windows-installer', str(windows_installer),
                                '--entrypoints', str(entries),
                                '--channel-entrypoint', str(channel),
                                '--windows-channel-entrypoint', str(windows_channel),
                                '--freeze-manifest', str(freeze_manifest), '--allow-fixture-freeze',
                                '--output', str(output)], check=True)
                subprocess.run([sys.executable, '-B',
                                str(ROOT / 'tools/release/zsetup_publication.py'),
                                'verify', str(output)], check=True)
                outputs.append(output)
            comparison = filecmp.dircmp(outputs[0], outputs[1])
            self.assertEqual((comparison.left_only, comparison.right_only, comparison.diff_files),
                             ([], [], []))
            version = json.loads((release / 'release-manifest.json').read_text())['version']
            self.assertEqual(len(list((outputs[0] / f'entrypoints/{version}/skills').glob('*.sh'))), 33)
            self.assertEqual(len(list((outputs[0] / f'entrypoints/{version}/systems').glob('*.sh'))), 3)
            public_entry = (outputs[0] / 'setup.sh').read_text()
            self.assertNotIn('KAI_SKILLS_REQUESTED_RELEASE=', public_entry)
            self.assertIn('bootstrap_zsetup', public_entry)
            self.assertEqual((outputs[0] / 'setup.sh').read_bytes(),
                             (outputs[0] / 'install.sh').read_bytes())
            self.assertEqual((outputs[0] / 'setup.ps1').read_bytes(), windows_channel.read_bytes())
            publication = json.loads((outputs[0] / 'publication-manifest.json').read_text())
            self.assertEqual(publication['windowsChannelEntry']['path'], 'setup.ps1')
            self.assertTrue((outputs[0] / publication['windowsInstaller']['path']).is_file())


if __name__ == '__main__':
    unittest.main()
