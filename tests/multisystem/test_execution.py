"""Public CLI contracts; child programs observe argv and side effects directly."""
import base64
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / 'tools/multisystem/execution.py'


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='kai exec 中文 ')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def call(self, action, request):
        p = subprocess.run([sys.executable, str(CLI), action], input=json.dumps(request),
                           capture_output=True, text=True, timeout=12)
        self.assertTrue(p.stdout.strip(), p.stderr)
        return p, json.loads(p.stdout)

    def test_argv_cwd_stdin_and_environment_are_preserved(self):
        marker = self.work / 'unexpected'
        args = ['with space', '中文', "a'b\"c", '', f'$(touch "{marker}")', f'; touch "{marker}"', f'`touch "{marker}"`']
        program = 'import os,sys,json; print(json.dumps(dict(argv=sys.argv[1:],cwd=os.getcwd(),value=os.getenv("KAI_VALUE"),stdin=sys.stdin.read())))'
        p, r = self.call('run', {'argv': [sys.executable, '-c', program, *args], 'cwd': str(self.work), 'env': {'KAI_VALUE': '甲 $HOME'}, 'stdin': '输入\n'})
        self.assertEqual(p.returncode, 0, r)
        observed = json.loads(r['stdout'])
        self.assertEqual(observed, dict(argv=args, cwd=str(self.work), value='甲 $HOME', stdin='输入\n'))
        self.assertFalse(marker.exists())
        _, second = self.call('run', {'argv': [sys.executable, '-c', 'import os; print(os.getenv("KAI_VALUE","absent"))']})
        self.assertEqual(second['stdout'].strip(), 'absent')

    def test_real_shell_source_does_not_persist_between_calls(self):
        _, first = self.call('run', {'argv': ['bash', '-c', 'export KAI_SESSION=one; printf %s "$KAI_SESSION"']})
        _, second = self.call('run', {'argv': ['bash', '-c', 'printf %s "${KAI_SESSION-unset}"']})
        self.assertEqual(first['stdout'], 'one')
        self.assertEqual(second['stdout'], 'unset')

    def test_exit_missing_command_and_bounded_streams(self):
        p, r = self.call('run', {'argv': [sys.executable, '-c', 'import sys; print("err",file=sys.stderr); sys.exit(37)']})
        self.assertEqual((p.returncode, r['exitCode'], r['category']), (37, 37, 'command-failed'))
        self.assertIn('err', r['stderr'])
        _, missing = self.call('run', {'argv': [str(self.work / 'missing')]})
        self.assertEqual(missing['category'], 'missing-executable')
        _, large = self.call('run', {'argv': [sys.executable, '-c', 'import sys; print("x"*300000); print("y"*300000,file=sys.stderr)'], 'outputLimitBytes': 1024})
        self.assertEqual(large['exitCode'], 0)
        self.assertLessEqual(len(large['stdout'].encode()), 1024)
        self.assertLessEqual(len(large['stderr'].encode()), 1024)
        self.assertTrue(large['stdoutTruncated'] and large['stderrTruncated'])

    def test_timeout_and_signal_cancel_kill_descendants(self):
        for mode in ['timeout', 'cancel']:
            with self.subTest(mode=mode):
                marker = self.work / mode
                started = self.work / (mode + '.started')
                child = 'import time,pathlib; time.sleep(1.5); pathlib.Path(' + repr(str(marker)) + ').write_text("leaked")'
                parent = 'import subprocess,sys,time,pathlib; subprocess.Popen([sys.executable,"-c",' + repr(child) + ']); pathlib.Path(' + repr(str(started)) + ').touch(); time.sleep(30)'
                request = {'argv': [sys.executable, '-c', parent], 'timeoutSeconds': 0.3 if mode == 'timeout' else 10}
                p = subprocess.Popen([sys.executable, str(CLI), 'run'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                self.addCleanup(lambda p=p: p.kill() if p.poll() is None else None)
                p.stdin.write(json.dumps(request)); p.stdin.close(); p.stdin = None
                if mode == 'cancel':
                    deadline = time.monotonic() + 3
                    while not started.exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue(started.exists())
                    p.send_signal(signal.SIGTERM)
                stdout, stderr = p.communicate(timeout=4)
                self.assertTrue(stdout, stderr)
                result = json.loads(stdout)
                self.assertEqual(result['category'], 'timeout' if mode == 'timeout' else 'cancelled')
                time.sleep(1.6)
                self.assertFalse(marker.exists(), 'descendant escaped termination')

    def test_fixture_facts_do_not_infer_distribution_from_opkg(self):
        cases = [
            ({'kernel': 'Linux', 'architecture': 'x86_64', 'osRelease': 'ID=ubuntu\nID_LIKE=debian', 'home': '/home/a', 'commands': {'apt-get': '/usr/bin/apt-get', 'opkg': '/usr/bin/opkg'}}, ('linux', 'ubuntu', 'apt', 'x64', 'native')),
            ({'kernel': 'Linux', 'architecture': 'mips', 'osRelease': '', 'commands': {'opkg': '/bin/opkg'}}, ('linux', 'unknown', 'unknown', 'unknown', 'native')),
            ({'kernel': 'Linux', 'architecture': 'aarch64', 'osRelease': 'ID=istoreos\nID_LIKE="lede openwrt"', 'home': '/root'}, ('istoreos', 'istoreos', 'opkg', 'arm64', 'native')),
            ({'kernel': 'Darwin', 'architecture': 'arm64', 'home': '/Users/a', 'commands': {'brew': '/opt/homebrew/bin/brew'}}, ('macos', 'macos', 'brew', 'arm64', 'native')),
            ({'kernel': 'Darwin', 'architecture': 'x86_64', 'home': '/Users/a', 'commands': {'brew': '/usr/local/bin/brew'}}, ('macos', 'macos', 'brew', 'x64', 'native')),
            ({'kernel': 'MINGW64_NT-10.0', 'architecture': 'x86_64', 'home': 'C:/Users/a', 'msystem': 'MINGW64'}, ('windows', 'windows', 'winget', 'x64', 'git-bash')),
            ({'kernel': 'Windows', 'architecture': 'AMD64', 'home': 'C:/Users/a', 'msystem': 'MINGW64'}, ('windows', 'windows', 'winget', 'x64', 'git-bash')),
            ({'kernel': 'Windows', 'architecture': 'AMD64', 'shell': 'powershell', 'home': 'C:\\Users\\a'}, ('windows', 'windows', 'winget', 'x64', 'native')),
            ({'kernel': 'Linux', 'architecture': 'x86_64', 'osRelease': 'ID=debian', 'wslDistro': 'Debian', 'home': '/home/linux'}, ('linux', 'debian', 'apt', 'x64', 'wsl')),
        ]
        for raw, expected in cases:
            with self.subTest(raw=raw):
                _, result = self.call('classify', raw)
                self.assertEqual(tuple(result[k] for k in ['platform', 'distribution', 'packageManager', 'architecture', 'environment']), expected)
                self.assertEqual(result['home'], raw.get('home', 'unknown'))

    def test_windows_plan_uses_native_bridge_and_rejects_wsl_as_bash(self):
        request = {'argv': ['C:\\Program Files\\Example\\app.exe', '中文', 'a b', ''], 'target': {'platform': 'windows', 'shell': 'native'}, 'cwd': 'C:\\项目 空格', 'env': {'KAI_TEST': 'value'}}
        _, plan = self.call('plan', request)
        self.assertEqual(plan['launcher'][0], 'powershell.exe')
        script = base64.b64decode(plan['launcher'][-1]).decode('utf-16le')
        payload64 = script.split("FromBase64String('", 1)[1].split("')", 1)[0]
        payload = json.loads(base64.b64decode(payload64))
        self.assertEqual(payload['argv'], request['argv'])
        self.assertEqual(payload['cwd'], request['cwd'])
        _, invalid = self.call('plan', {**request, 'target': {'platform': 'windows', 'shell': 'git-bash', 'bashPath': 'C:\\Windows\\System32\\bash.exe'}})
        self.assertEqual(invalid['category'], 'usage')

    def test_ssh_boundary_preserves_argv_and_separates_transport_failure(self):
        key = self.work / 'key'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        known = self.work / 'known_hosts'; known.write_text('lab.example ' + key.with_suffix('.pub').read_text())
        ssh = self.work / 'ssh-boundary'
        ssh.write_text('#!/usr/bin/env python3\nimport subprocess,sys,shlex\np=subprocess.run(shlex.split(sys.argv[-1]),input=sys.stdin.buffer.read());sys.exit(p.returncode)\n')
        ssh.chmod(0o700)
        transport = {'kind': 'ssh', 'host': 'lab.example', 'user': 'root', 'knownHosts': str(known), 'sshBin': str(ssh)}
        argv = [sys.executable, '-c', 'import sys,json; print(json.dumps(sys.argv[1:]));sys.exit(255)', 'a b', "中文'$();`", '']
        p, result = self.call('run', {'argv': argv, 'cwd': str(self.work), 'transport': transport})
        self.assertEqual((p.returncode, result['exitCode'], result['category']), (255, 255, 'command-failed'))
        self.assertEqual(json.loads(result['stdout']), argv[3:])
        ssh.write_text('#!/bin/sh\nexit 255\n')
        _, failed = self.call('run', {'argv': ['true'], 'transport': transport})
        self.assertEqual(failed['category'], 'transport')


if __name__ == '__main__':
    unittest.main()
