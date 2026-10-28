"""Run the public installer on native desktop filesystems, in a task directory."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform in ('darwin','win32') and os.environ.get('KAI_NATIVE_PRESET'),
                     'requires a staged preset on a native desktop')
class NativeLifecycleTests(unittest.TestCase):
    def test_unmodified_install_upgrades_and_uninstalls_with_unicode_destination(self):
        bash = os.environ.get('KAI_NATIVE_BASH', '/bin/bash')
        helper = (Path(os.environ['KAI_NATIVE_PRESET'])/'install.sh').as_posix()
        with tempfile.TemporaryDirectory(dir=os.environ.get('KAI_NATIVE_WORK')) as folder:
            destination = Path(folder)/'Agent 中文 space'
            def call(*options):
                p = subprocess.run([bash,'--noprofile','--norc','-c','exec sh "$@"',
                    'kai-native',helper,'--target',destination.as_posix(),*options],
                    capture_output=True,text=True,encoding='utf-8')
                self.assertEqual(p.returncode,0,p.stdout+p.stderr)
            call('--dry-run')
            self.assertFalse(destination.exists())
            call()
            self.assertTrue((destination/'kai-software/SKILL.md').is_file())
            call('--upgrade')
            manifests = list((destination/'.linkease-skills').glob('*.json'))
            self.assertEqual(len(manifests),1)
            self.assertEqual(len(json.loads(manifests[0].read_text(encoding='utf-8'))['skills']),8)
            call('--uninstall')
            self.assertFalse((destination/'kai-software').exists())


if __name__ == '__main__':
    unittest.main()
