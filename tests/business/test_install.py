import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='business install 中文 ')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.target = self.work / 'agent skills 中文'

    def call(self, *args, target=True, root=ROOT, **env):
        command = ['sh', str(root / 'install.sh'), *args]
        if target:
            command += ['--consumer', 'generic', '--target-skills', str(self.target)]
        return subprocess.run(command, env={**os.environ, **env}, text=True, capture_output=True, timeout=60)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def active(self):
        return {path.parent.name for path in self.target.glob('*/SKILL.md')}

    def test_single_install_plan_is_exact_and_does_not_create_destination(self):
        result = self.call('--skill', 'kai-download-acceleration', '--dry-run', '--json')
        self.assert_ok(result)
        plan = json.loads(result.stdout)
        self.assertEqual([p['id'] for p in plan['packages']], ['kai-download-acceleration'])
        self.assertFalse(plan['serviceOperations'])
        self.assertEqual(plan['programOperations'], [])
        self.assertFalse(self.target.exists())
        self.assert_ok(self.call('--skill', 'kai-download-acceleration'))
        self.assertEqual(self.active(), {'kai-download-acceleration'})

    def test_business_bundle_actual_members_match_plan(self):
        result = self.call('--bundle', 'development', '--dry-run', '--json')
        self.assert_ok(result)
        expected = {p['id'] for p in json.loads(result.stdout)['packages']}
        self.assert_ok(self.call('--bundle', 'development'))
        self.assertEqual(self.active(), expected)
        self.assertEqual(expected, {'kai-dev-environment', 'kai-project-dependencies', 'kai-download-acceleration'})

    def test_platform_all_remote_has_exact_business_and_transport_members(self):
        result = self.call('--platform', 'windows', '--all', '--mode', 'remote-control', '--dry-run', '--json')
        self.assert_ok(result)
        expected = {p['id'] for p in json.loads(result.stdout)['packages']}
        self.assertIn('target-ssh-powershell-controller', expected)
        self.assertFalse(any(p.startswith('istoreos-') for p in expected))
        self.assert_ok(self.call('--platform', 'windows', '--all', '--mode', 'remote-control'))
        self.assertEqual(self.active(), expected)

    def test_invalid_inputs_and_foreign_directory_are_preserved(self):
        for args in [('--skill', 'missing'), ('--bundle', '../escape'),
                     ('--all',), ('--skill', 'kai-software', '--bundle', 'development'),
                     ('--skill', 'istoreos-luci-recovery', '--platform', 'windows'),
                     ('--skill', 'kai-software', '--platform', 'windows', '--architecture', 'arm64')]:
            result = self.call(*args)
            self.assertNotEqual(result.returncode, 0, args)
            self.assertFalse(self.target.exists())
        foreign = self.target / 'kai-software'; foreign.mkdir(parents=True)
        (foreign / 'keep').write_text('keep')
        self.assertNotEqual(self.call('--skill', 'kai-software').returncode, 0)
        self.assertEqual((foreign / 'keep').read_text(), 'keep')

    def test_explicit_consumer_path_and_query_actions(self):
        self.assert_ok(self.call('--list-skills', target=False))
        self.assert_ok(self.call('--list-bundles', target=False))
        self.assert_ok(self.call('--describe-skill', 'kai-software', target=False))
        self.assert_ok(self.call('--describe-bundle', 'development', target=False))
        result = self.call('--skill', 'kai-software', '--consumer', 'codex', '--dry-run', '--json',
                           target=False, CODEX_HOME=str(self.work / 'custom-codex'))
        self.assert_ok(result)
        self.assertEqual(json.loads(result.stdout)['destination'], str(self.work / 'custom-codex/skills'))

    def test_offline_copy_requires_no_source_repository_or_python(self):
        offline = self.work / 'offline'
        (offline / 'tools').mkdir(parents=True)
        shutil.copy2(ROOT / 'install.sh', offline / 'install.sh')
        shutil.copy2(ROOT / 'tools/install-business.sh', offline / 'tools/install-business.sh')
        catalog = json.loads((ROOT / 'business-catalog.json').read_text())
        catalog['skills'] = [p for p in catalog['skills'] if p['id'] == 'kai-software']
        (offline / 'business-catalog.json').write_text(json.dumps(catalog))
        shutil.copytree(ROOT / 'skills/kai-software', offline / 'skills/kai-software')
        result = self.call('--skill', 'kai-software', root=offline)
        self.assert_ok(result)
        self.assertEqual(self.active(), {'kai-software'})

    def test_old_preset_command_still_dry_runs(self):
        result = self.call('--platform', 'ubuntu', '--mode', 'on-device', '--dry-run')
        self.assert_ok(result)
        self.assertIn('preset=ubuntu-on-device', result.stdout)
        self.assertFalse(self.target.exists())

    def test_native_powershell_plan_requires_no_bash_and_writes_nothing(self):
        powershell = os.environ.get('KAI_DESKTOP_PWSH') or shutil.which('pwsh')
        if not powershell:
            self.fail('Set KAI_DESKTOP_PWSH for the native entry contract')
        if not Path(powershell).is_file():
            self.fail('PowerShell executor required for the native entry contract')
        result = subprocess.run([powershell, '-NoLogo', '-NoProfile', '-NonInteractive', '-File',
            str(ROOT / 'install.ps1'), '-Action', 'Plan', '-Skill', 'kai-software', '-TargetSkills', str(self.target)],
            text=True, capture_output=True)
        self.assert_ok(result)
        self.assertEqual(json.loads(result.stdout)['packages'], ['kai-software'])
        self.assertFalse(self.target.exists())

    def test_windows_symlink_is_rejected_before_destination_is_created(self):
        binary = self.work / 'bin'; binary.mkdir()
        uname = binary / 'uname'; uname.write_text('#!/bin/sh\necho MINGW64_NT\n'); uname.chmod(0o755)
        result = self.call('--skill', 'kai-software', '--symlink',
                           PATH=str(binary) + os.pathsep + os.environ['PATH'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('supports --copy', result.stderr)
        self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
