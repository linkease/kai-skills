"""jq selection at public helpers; firmware tools are never replaced."""
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
BOOT=ROOT/'components/system-packs/common/skills/kai-tool-bootstrap/scripts'


class JqTests(unittest.TestCase):
    def owner_fixture(self, directory):
        root = Path(directory)
        scripts = root / 'scripts'
        shutil.copytree(BOOT, scripts)
        resources = root / 'resources'
        resources.mkdir()
        bin = root / 'bin'
        bin.mkdir()
        firmware = bin / 'jq'
        firmware.write_text('#!/bin/sh\nexit 5\n')
        firmware.chmod(0o700)
        core = bin / 'fixture-core'
        core.write_text('#!/bin/sh\ncase "$1" in\n--version) echo "zsetup 0.5.4";;\ncontext) echo x86_64;;\nrun) shift 2; exec "$@";;\n*) exit 92;;\nesac\n')
        core.chmod(0o700)
        owner = resources / 'jq-install.sh'
        owner.write_text('#!/bin/sh\nset -eu\necho owner >> "$CALLS"\n'
                         'case "${TEST_INSTALL_MODE:-install}" in fail) exit 19;; noop) exit 0;; esac\n'
                         'mkdir -p "$HOME/.local/bin"\ncp "$TEST_JQ_SOURCE" "$HOME/.local/bin/jq"\n')
        (resources / 'jq-owner.sha256').write_text(hashlib.sha256(owner.read_bytes()).hexdigest() + '  jq-install.sh\n')
        env = {**os.environ, 'HOME': directory, 'PATH': str(bin) + ':' + os.environ['PATH'],
               'KAI_ZSETUP_BIN': str(core), 'TEST_JQ_SOURCE': shutil.which('jq'),
               'KAI_PLATFORM': 'istoreos', 'CALLS': str(root / 'calls')}
        env.pop('KAI_JQ_BIN', None)
        return scripts, owner, firmware, env

    def test_missing_jq_installs_through_verified_owner_rechecks_and_reuses(self):
        with tempfile.TemporaryDirectory() as directory:
            scripts, owner, firmware, env = self.owner_fixture(directory)
            before = firmware.read_bytes()
            for action, expected in [('plan', 'install-needed'), ('ensure', 'installed'), ('ensure', 'reused')]:
                result = subprocess.run(['sh', str(scripts / 'prepare.sh'), action, '--tool', 'jq'],
                                        env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)['status'], expected)
                if action == 'plan':
                    self.assertFalse(Path(env['CALLS']).exists())
            self.assertEqual(Path(env['CALLS']).read_text().splitlines(), ['owner'])
            self.assertEqual(firmware.read_bytes(), before)

    def test_failed_or_ineffective_install_is_not_reported_installed(self):
        for mode, code in [('fail', 19), ('noop', 11)]:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                scripts, owner, firmware, env = self.owner_fixture(directory)
                result = subprocess.run(['sh', str(scripts / 'prepare.sh'), 'ensure', '--tool', 'jq'],
                    env={**env, 'TEST_INSTALL_MODE': mode}, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(json.loads(result.stdout)['status'], 'failed')
                self.assertFalse((Path(directory) / '.local/bin/jq').exists())

    def test_owner_checksum_failure_returns_a_receipt_without_executing_it(self):
        with tempfile.TemporaryDirectory() as directory:
            scripts, owner, firmware, env = self.owner_fixture(directory)
            owner.write_text(owner.read_text() + '# changed after manifest\n')
            result = subprocess.run(['sh', str(scripts / 'prepare.sh'), 'ensure', '--tool', 'jq'],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(json.loads(result.stdout)['status'], 'failed')
            self.assertFalse(Path(env['CALLS']).exists())

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
