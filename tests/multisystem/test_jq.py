"""jq selection at public helpers; firmware tools are never replaced."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
BOOT=ROOT/'components/system-packs/common/skills/kai-tool-bootstrap/scripts'


class JqTests(unittest.TestCase):
    def test_windows_install_request_on_linux_stops_before_any_installer(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);bin=home/'bin';bin.mkdir();marker=home/'unexpected-installer'
            for name,body in [('jq','exit 5'),('sha256sum','touch "$KAI_TEST_MARKER"; exit 93')]:
                p=bin/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o700)
            p=subprocess.run(['bash',str(BOOT/'tool.sh'),'ensure','jq'],
                env={**os.environ,'HOME':directory,'PATH':str(bin)+':'+os.environ['PATH'],'KAI_PLATFORM':'windows','KAI_TEST_MARKER':str(marker)},
                text=True,capture_output=True,timeout=5)
            self.assertEqual(p.returncode,18,p.stderr)
            self.assertEqual(json.loads(p.stdout)['status'],'unavailable')
            self.assertFalse(marker.exists())

    def test_dependency_source_query_uses_complete_managed_jq_without_installing_an_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);bin=home/'bin';bin.mkdir()
            system=bin/'jq';system.write_text('#!/bin/sh\necho "no ONIGURUMA" >&2\nexit 5\n');system.chmod(0o700)
            managed=home/'.local/bin/jq';managed.parent.mkdir(parents=True);managed.symlink_to(shutil.which('jq'))
            project=home/'project 中文';project.mkdir();(project/'package.json').write_text('{"dependencies":{"sample":"git+https://example.test/a/b.git"}}')
            cli=BOOT.parent.parent/'kai-project-dependencies/scripts/dependencies.sh'
            p=subprocess.run(['bash',str(cli),'sources','npm','22.14.0',str(project)],
                env={**os.environ,'HOME':directory,'PATH':str(bin)+':'+os.environ['PATH']},text=True,capture_output=True,timeout=5)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertEqual(json.loads(p.stdout)['sources'],[{'name':'sample','type':'git'}])

    def test_jq_bootstrap_is_discoverable_without_any_jq(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);bin=home/'bin';bin.mkdir()
            for name in ['bash','dirname','uname']:
                (bin/name).symlink_to(shutil.which(name))
            p=subprocess.run(['bash',str(BOOT/'tool.sh'),'plan','jq'],
                env={**os.environ,'HOME':directory,'PATH':str(bin),'KAI_PLATFORM':'istoreos'},
                text=True,capture_output=True,timeout=5)
            self.assertEqual(p.returncode,0,p.stderr)
            d=json.loads(p.stdout);self.assertEqual(d['tool'],'jq')
            self.assertEqual(d['status'],'install-needed');self.assertFalse(d['serviceOperations'])

    def test_basic_firmware_jq_is_retained_and_complete_managed_jq_is_selected(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);bin=home/'bin';bin.mkdir()
            system=bin/'jq';system.write_text('#!/bin/sh\necho "jq was compiled without ONIGURUMA" >&2\nexit 5\n');system.chmod(0o700)
            managed=home/'.local/bin/jq';managed.parent.mkdir(parents=True);managed.symlink_to(shutil.which('jq'))
            p=subprocess.run(['bash',str(BOOT/'tool.sh'),'probe','jq'],
                env={**os.environ,'HOME':directory,'PATH':str(bin)+':'+os.environ['PATH'],'KAI_PLATFORM':'istoreos'},text=True,capture_output=True,timeout=5)
            self.assertEqual(p.returncode,0,p.stderr)
            d=json.loads(p.stdout);self.assertEqual(d['path'],str(managed));self.assertEqual(d['status'],'reused')
            self.assertIn('ONIGURUMA',system.read_text())


if __name__=='__main__': unittest.main()
