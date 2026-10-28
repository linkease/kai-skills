import json
import hashlib
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / 'tools/multisystem/lab.py'


class LabTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config = Path(self.tmp.name) / 'lab.json'
        self.config.write_text(json.dumps({'sshTarget': 'operator@lab.example', 'remoteRoot': '/mnt/data/kai-lab', 'stateDir': self.tmp.name, 'runId': 'contract-run'}))

    def call(self, *args):
        return subprocess.run(['python3', str(LAB), '--config', str(self.config), *args], cwd=ROOT, capture_output=True, text=True)

    def test_plan_is_offline_and_owns_only_scoped_resources(self):
        p = self.call('plan', '--target', 'ubuntu')
        self.assertEqual(p.returncode, 0, p.stderr)
        data = json.loads(p.stdout)
        self.assertEqual(data['target'], 'ubuntu')
        self.assertEqual(data['distribution'], 'ubuntu:24.04')
        self.assertEqual(data['labels']['io.linkease.kai-skills.run'], 'contract-run')
        self.assertGreaterEqual(data['minFreeBytes'], 1024**3)
        self.assertFalse(data['mountsHostRoot'])
        self.assertFalse(data['mountsHostDockerSocket'])
        self.assertEqual(data['requiredEvidence'], ['identity', 'package-database', 'digest', 'on-device', 'ssh', 'cleanup'])

    def test_untrusted_target_and_unsafe_root_rejected_before_connect(self):
        for target, path in [('x;touch /tmp/not-allowed', '/mnt/data/lab'), ('root@lab.example', '/')]:
            self.config.write_text(json.dumps({'sshTarget': target, 'remoteRoot': path, 'stateDir': self.tmp.name, 'runId': 'contract-run'}))
            p = self.call('plan', '--target', 'ubuntu')
            self.assertNotEqual(p.returncode, 0)
            self.assertIn('invalid', p.stderr.lower())

    def test_istoreos_requires_firmware_curl_preservation_evidence(self):
        p = self.call('plan', '--target', 'istoreos')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('system-curl-unchanged', json.loads(p.stdout)['requiredEvidence'])

    def test_desktop_targets_are_not_silently_run_as_linux(self):
        p = self.call('plan', '--target', 'windows')
        self.assertNotEqual(p.returncode, 0)

    def test_gateway_candidate_is_digest_locked_before_any_connection(self):
        binary = Path(self.tmp.name) / 'candidate'
        binary.write_bytes(b'candidate fixture')
        config = json.loads(self.config.read_text())
        candidate = {'path': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                     'sourceCommit': 'a' * 40}
        config['gatewayCandidate'] = candidate
        self.config.write_text(json.dumps(config))
        p = self.call('plan', '--target', 'debian')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)['gatewayCandidate'],
                         {k: candidate[k] for k in ['sha256', 'sourceCommit']})
        binary.write_bytes(b'modified candidate')
        p = self.call('plan', '--target', 'debian')
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('candidate', p.stderr)

    def test_host_without_jq_is_snapshotted_before_target_preparation(self):
        directory=Path(self.tmp.name);bin=directory/'bin';bin.mkdir()
        (bin/'sh').symlink_to(shutil.which('sh'))
        for name,body in [('curl','echo curl-fixture'),('sha256sum',
                'for path do [ -n "$path" ] || exit 1; printf "fixture %s\\n" "$path"; done')]:
            program=bin/name;program.write_text('#!/bin/sh\n'+body+'\n');program.chmod(0o700)
        ssh=bin/'ssh'
        ssh.write_text('#!'+sys.executable+'\nimport subprocess,sys,shlex\n'
            'args=shlex.split(sys.argv[-1])\n'
            'if args[0]=="sh": sys.exit(subprocess.run(args).returncode)\n'
            'print("REACHED_TARGET_PREPARATION",file=sys.stderr);sys.exit(89)\n')
        ssh.chmod(0o700)
        p=subprocess.run([sys.executable,str(LAB),'--config',str(self.config),'scenario','--target','istoreos','--milestone','MS6'],
            env={**os.environ,'PATH':str(bin)},text=True,capture_output=True,timeout=5)
        self.assertEqual(p.returncode,1)  # fixture deliberately stops preparation
        self.assertIn('REACHED_TARGET_PREPARATION',p.stderr)
        guard=json.loads((directory/'MS6-host-curl.json').read_text())
        self.assertTrue(guard['unchanged']);self.assertIn('jq=absent',guard['before'])

    def test_client_candidate_is_source_and_digest_locked_offline(self):
        binary=Path(self.tmp.name)/'ks-cli-candidate';binary.write_bytes(b'client protocol fixture')
        config=json.loads(self.config.read_text())
        candidate={'path':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'sourceCommit':'b'*40}
        config['clientCandidate']=candidate;self.config.write_text(json.dumps(config))
        result=self.call('plan','--target','debian')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(result.stdout).get('clientCandidate'),{k:candidate[k] for k in ['sha256','sourceCommit']})
        binary.write_bytes(b'modified candidate')
        result=self.call('plan','--target','debian')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('candidate',result.stderr)


if __name__ == '__main__':
    unittest.main()
