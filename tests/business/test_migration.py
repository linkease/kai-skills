import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
LEGACY = 'a7c5b1e7a855edcbac21ed25e46515e540fc4fae'


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='business migration 中文 ')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.target = self.work / 'agent skills'
        archive = subprocess.check_output(['git', 'archive', LEGACY, 'platforms/istoreos/on-device'], cwd=ROOT)
        checkout = self.work / 'legacy'; checkout.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:
            source.extractall(checkout, filter='data')
        subprocess.run(['sh', str(checkout / 'platforms/istoreos/on-device/install.sh'), '--target', str(self.target)],
                       check=True, capture_output=True)
        self.assertEqual(len(list(self.target.glob('*/SKILL.md'))), 20)

    def call(self, *args, **env):
        return subprocess.run(['sh', str(ROOT / 'install.sh'), *args, '--consumer', 'generic',
            '--target-skills', str(self.target)], env={**os.environ, **env}, text=True, capture_output=True, timeout=90)

    def ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_legacy_preset_becomes_system_selection_and_keeps_single_owner(self):
        keep = self.target / 'unrelated'; keep.mkdir(); (keep / 'keep').write_text('keep')
        result = self.call('--skill', 'kai-software', '--dry-run', '--json')
        self.ok(result)
        self.assertEqual(json.loads(result.stdout)['migratedPresets'], ['istoreos-on-device'])
        self.assertFalse((self.target / '.linkease-skills/business-state.json').exists())
        self.ok(self.call('--skill', 'kai-software'))
        state = json.loads((self.target / '.linkease-skills/business-state.json').read_text())
        self.assertEqual(set(state['selections']), {'skill:kai-software', 'system:istoreos:on-device'})
        self.assertEqual(len(list(self.target.glob('*/SKILL.md'))), 22)
        self.assertFalse((self.target / 'istoreos-package-manager').exists())
        self.ok(self.call('--platform', 'istoreos', '--mode', 'on-device', '--uninstall'))
        self.assertEqual({p.parent.name for p in self.target.glob('*/SKILL.md')}, {'kai-software'})
        self.assertEqual((keep / 'keep').read_text(), 'keep')

    def test_modified_legacy_content_stops_before_any_migration(self):
        file = self.target / 'istoreos-package-manager/SKILL.md'
        file.write_text(file.read_text() + '\nuser edit\n')
        self.assertNotEqual(self.call('--skill', 'kai-software').returncode, 0)
        self.assertIn('user edit', file.read_text())
        self.assertFalse((self.target / 'kai-software').exists())
        self.assertTrue((self.target / '.linkease-skills/istoreos-on-device.json').exists())

    def test_migration_failure_keeps_old_manifest_and_can_retry(self):
        result = self.call('--bundle', 'software-management', LINKEASE_BUSINESS_TEST_FAIL='after-old-move')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(list(self.target.glob('*/SKILL.md'))), 20)
        self.assertTrue((self.target / '.linkease-skills/istoreos-on-device.json').exists())
        self.ok(self.call('--bundle', 'software-management'))
        self.assertEqual(len(list(self.target.glob('*/SKILL.md'))), 22)

    def test_two_legacy_owners_migrate_without_losing_their_shared_members(self):
        for platform in ['ubuntu', 'debian']:
            result = subprocess.run(['sh', str(ROOT / 'platforms' / platform / 'on-device/install.sh'),
                '--target', str(self.target), '--force'], text=True, capture_output=True)
            self.ok(result)
        self.ok(self.call('--skill', 'kai-software'))
        state = json.loads((self.target / '.linkease-skills/business-state.json').read_text())
        self.assertTrue({'system:istoreos:on-device','system:ubuntu:on-device','system:debian:on-device'} <= set(state['selections']))
        self.ok(self.call('--platform', 'istoreos', '--all', '--mode', 'on-device', '--uninstall'))
        self.assertTrue((self.target / 'kai-dev-environment/SKILL.md').is_file())

    def test_uninstall_unselected_single_does_not_corrupt_legacy_ownership(self):
        self.ok(self.call('--skill', 'kai-software', '--uninstall'))
        # Whatever migration occurs, a subsequent ordinary operation must see a valid state.
        self.ok(self.call('--skill', 'kai-software'))

    def test_uninstall_one_old_selection_preserves_other_old_shared_ownership(self):
        result = subprocess.run(['sh', str(ROOT / 'platforms/ubuntu/on-device/install.sh'),
            '--target', str(self.target), '--force'], text=True, capture_output=True)
        self.ok(result)
        self.ok(self.call('--platform', 'istoreos', '--all', '--mode', 'on-device', '--uninstall'))
        self.assertTrue((self.target / '.linkease-skills/ubuntu-on-device.json').is_file())
        self.assertTrue((self.target / 'kai-dev-environment/SKILL.md').is_file())
        self.ok(self.call('--skill', 'kai-software'))


if __name__ == '__main__':
    unittest.main()
