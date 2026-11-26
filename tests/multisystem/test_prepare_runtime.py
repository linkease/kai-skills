"""Preparation sequencing without network, package installation or host changes."""
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'components/system-packs/common/skills/kai-tool-bootstrap/scripts'


class PrepareRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='runtime 中文 ')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.scripts = self.work / 'scripts'
        shutil.copytree(SCRIPTS, self.scripts)
        self.calls = self.work / 'calls'
        self.env = {**os.environ, 'HOME': str(self.work), 'CALLS': str(self.calls)}

    def stub(self, name, text):
        (self.scripts / name).write_text('#!/bin/bash\nset -eu\n' + text)

    def call(self, action, **env):
        result = subprocess.run(['/bin/sh', str(self.scripts / 'prepare.sh'), action],
                                env={**self.env, **env}, capture_output=True, text=True, timeout=15)
        return result, json.loads(result.stdout)

    def test_native_plan_without_bash_or_jq_never_installs(self):
        minimal = self.work / 'bin'; minimal.mkdir()
        for cmd in ['dirname', 'uname']:
            (minimal / cmd).symlink_to(shutil.which(cmd))
        result, receipt = self.call('plan', PATH=str(minimal))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(receipt['ready'])
        self.assertEqual(receipt['stage'], 'bash')
        self.assertFalse(self.calls.exists())

    def test_jq_must_be_ready_before_core_probe(self):
        self.stub('jq.sh', 'echo jq >> "$CALLS"\necho \'{"status":"install-needed","exitCode":0}\'\n')
        self.stub('tool.sh', 'echo core >> "$CALLS"\nexit 37\n')
        result, receipt = self.call('plan', KAI_JQ_BIN=str(self.work / 'absent-jq'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(receipt['ready'])
        self.assertEqual(self.calls.read_text().splitlines(), ['jq'])

    def test_ready_paths_are_returned_and_no_installer_runs(self):
        jq = shutil.which('jq')
        self.stub('jq.sh', 'echo \'{"status":"reused","exitCode":0}\'\n')
        self.stub('tool.sh', 'echo "$1 $2" >> "$CALLS"\necho \'{"status":"reused","path":"/verified/core","exitCode":0}\'\n')
        result, receipt = self.call('probe', KAI_JQ_BIN=jq)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(receipt['ready'])
        self.assertEqual(receipt['tools']['zsetup']['path'], '/verified/core')
        self.assertEqual(self.calls.read_text().strip(), 'probe zsetup')

    def test_dependency_failure_does_not_continue(self):
        self.stub('jq.sh', 'echo \'{"status":"failed","exitCode":11}\'\nexit 11\n')
        self.stub('tool.sh', 'echo wrong >> "$CALLS"\nexit 37\n')
        result, receipt = self.call('ensure')
        self.assertEqual(result.returncode, 11)
        self.assertFalse(receipt['ready'])
        self.assertFalse(self.calls.exists())

    def test_core_conflict_is_not_ready_or_overwritten(self):
        self.stub('jq.sh', 'echo \'{"status":"reused","exitCode":0}\'\n')
        self.stub('tool.sh', 'echo \'{"status":"conflict","exitCode":17}\'\n')
        result, receipt = self.call('plan', KAI_JQ_BIN=shutil.which('jq'))
        self.assertFalse(receipt['ready'])
        self.assertEqual(receipt['tools']['zsetup']['status'], 'conflict')

    def test_jq_only_preparation_does_not_prepare_other_runtime_tools(self):
        self.stub('jq.sh', 'echo "$1 jq" >> "$CALLS"\necho \'{"tool":"jq","status":"installed","path":"/verified/jq","exitCode":0}\'\n')
        self.stub('tool.sh', 'echo unexpected-core >> "$CALLS"\nexit 37\n')
        result = subprocess.run(['/bin/sh', str(self.scripts / 'prepare.sh'), 'ensure', '--tool', 'jq'],
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['path'], '/verified/jq')
        self.assertEqual(self.calls.read_text().splitlines(), ['ensure jq'])

    def test_jq_only_plan_and_failed_install_keep_the_original_result(self):
        for action, status, code in [('plan', 'install-needed', 0), ('ensure', 'failed', 11)]:
            with self.subTest(action=action):
                receipt = json.dumps({'tool': 'jq', 'status': status, 'exitCode': code})
                self.stub('jq.sh', "printf '%s\\n' " + shlex.quote(receipt) + '\nexit ' + str(code) + '\n')
                result = subprocess.run(['/bin/sh', str(self.scripts / 'prepare.sh'), action, '--tool', 'jq'],
                                        env=self.env, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(json.loads(result.stdout)['status'], status)

    def test_invalid_tool_selection_cannot_start_preparation(self):
        self.stub('jq.sh', 'echo called >> "$CALLS"\nexit 37\n')
        for args in [('ensure', '--tool', 'everything'), ('ensure', '--tool', 'jq', 'extra')]:
            result = subprocess.run(['/bin/sh', str(self.scripts / 'prepare.sh'), *args],
                                    env=self.env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 2)
        self.assertFalse(self.calls.exists())


if __name__ == '__main__':
    unittest.main()
