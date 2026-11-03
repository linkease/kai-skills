import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/business'))
from package import tree_digest


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='business ownership 中文 ')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.target = self.work / 'skills'

    def call(self, *args, root=ROOT, **env):
        return subprocess.run(['sh', str(root / 'install.sh'), *args, '--consumer', 'generic',
            '--target-skills', str(self.target)], env={**os.environ, **env},
            text=True, capture_output=True, timeout=60)

    def ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def state(self):
        return json.loads((self.target / '.linkease-skills/business-state.json').read_text())

    def test_single_and_collection_owners_survive_both_install_orders(self):
        for first, second in [(('--skill', 'kai-download-acceleration'), ('--bundle', 'development')),
                              (('--bundle', 'development'), ('--skill', 'kai-download-acceleration'))]:
            self.ok(self.call(*first)); self.ok(self.call(*second))
            self.ok(self.call('--bundle', 'development', '--uninstall'))
            self.assertTrue((self.target / 'kai-download-acceleration/SKILL.md').is_file())
            self.assertEqual(set(self.state()['packages']), {'kai-download-acceleration'})
            self.ok(self.call('--skill', 'kai-download-acceleration', '--uninstall'))

    def test_overlapping_collections_retain_shared_package_until_last_owner(self):
        self.ok(self.call('--bundle', 'development'))
        self.ok(self.call('--bundle', 'software-management'))
        self.ok(self.call('--bundle', 'development', '--uninstall'))
        self.assertEqual(set(self.state()['packages']), {'kai-software', 'kai-download-acceleration'})
        self.ok(self.call('--bundle', 'software-management', '--uninstall'))
        self.assertFalse((self.target / 'kai-download-acceleration').exists())

    def test_duplicate_install_and_uninstall_are_idempotent(self):
        self.ok(self.call('--skill', 'kai-software'))
        before = self.state()
        self.ok(self.call('--skill', 'kai-software'))
        self.assertEqual(before, self.state())
        self.ok(self.call('--skill', 'kai-software', '--uninstall'))
        self.ok(self.call('--skill', 'kai-software', '--uninstall'))

    def test_user_modified_and_foreign_skill_remain_untouched_even_with_force(self):
        self.ok(self.call('--bundle', 'development'))
        file = self.target / 'kai-dev-environment/SKILL.md'
        file.write_text(file.read_text() + '\nuser edit\n')
        before = tree_digest(self.target)
        for args in [('--bundle', 'development', '--uninstall'), ('--bundle', 'development', '--upgrade'),
                     ('--bundle', 'development', '--upgrade', '--force')]:
            self.assertNotEqual(self.call(*args).returncode, 0)
            self.assertEqual(tree_digest(self.target), before)

    def test_failed_transaction_restores_files_and_ownership(self):
        self.ok(self.call('--skill', 'kai-software'))
        unrelated = self.target / 'unrelated'; unrelated.mkdir(); (unrelated / 'keep').write_text('keep')
        before = tree_digest(self.target)
        for point in ['before-swap', 'after-old-move']:
            result = self.call('--bundle', 'development', LINKEASE_BUSINESS_TEST_FAIL=point)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(tree_digest(self.target), before)
            self.assertEqual(list(self.work.glob('.linkease-business-transaction.*')), [])

    def changed_source(self):
        source = self.work / 'release'
        (source / 'tools').mkdir(parents=True)
        shutil.copy2(ROOT / 'install.sh', source / 'install.sh')
        shutil.copy2(ROOT / 'tools/install-business.sh', source / 'tools/install-business.sh')
        shutil.copytree(ROOT / 'skills', source / 'skills')
        shutil.copytree(ROOT / 'bundles', source / 'bundles')
        changed = source / 'skills/kai-download-acceleration/SKILL.md'
        changed.write_text(changed.read_text() + '\nnew release fixture\n')
        package_file = changed.parent / 'skill-package.json'
        package = json.loads(package_file.read_text())
        package['version'] = '1.2.0'
        package_file.write_text(json.dumps(package))
        digest = tree_digest(changed.parent)
        catalog = json.loads((ROOT / 'business-catalog.json').read_text())
        for member in catalog['skills']:
            if member['id'] == 'kai-download-acceleration':
                member.update(version='1.2.0', treeDigest=digest)
        (source / 'business-catalog.json').write_text(json.dumps(catalog))
        for file in (source / 'bundles').glob('*.json'):
            lock = json.loads(file.read_text())
            for member in lock['members']:
                if member['id'] == 'kai-download-acceleration':
                    member.update(version='1.2.0', treeDigest=digest)
            file.write_text(json.dumps(lock))
        return source

    def test_shared_content_conflict_requires_explicit_coherent_upgrade(self):
        self.ok(self.call('--skill', 'kai-download-acceleration'))
        self.ok(self.call('--bundle', 'development'))
        source = self.changed_source()
        before = tree_digest(self.target)
        self.assertNotEqual(self.call('--skill', 'kai-download-acceleration', '--upgrade', root=source).returncode, 0)
        self.assertEqual(tree_digest(self.target), before)
        self.ok(self.call('--skill', 'kai-download-acceleration', '--upgrade', '--update-shared', root=source))
        state = self.state()
        self.assertEqual(state['packages']['kai-download-acceleration']['version'], '1.2.0')
        for selection in state['selections'].values():
            for member in selection['members']:
                if member['id'] == 'kai-download-acceleration':
                    self.assertEqual(member['version'], '1.2.0')

    def test_symlink_retarget_is_a_conflict_even_with_identical_content(self):
        self.ok(self.call('--skill', 'kai-software', '--symlink'))
        alternative = self.work / 'same-content'
        shutil.copytree(ROOT / 'skills/kai-software', alternative)
        installed = self.target / 'kai-software'
        installed.unlink(); installed.symlink_to(alternative, target_is_directory=True)
        self.assertNotEqual(self.call('--skill', 'kai-software', '--uninstall').returncode, 0)
        self.assertTrue(installed.is_symlink())

    def test_corrupt_selection_relationship_is_rejected(self):
        self.ok(self.call('--skill', 'kai-software'))
        file = self.target / '.linkease-skills/business-state.json'
        state = self.state()
        state['selections']['skill:kai-software']['members'][0]['treeDigest'] = 'sha256:' + 'f' * 64
        file.write_text(json.dumps(state))
        before = tree_digest(self.target)
        self.assertNotEqual(self.call('--skill', 'kai-software', '--uninstall').returncode, 0)
        self.assertEqual(tree_digest(self.target), before)

    def paused(self, point, *args):
        marker = self.work / ('pause-' + point)
        process = subprocess.Popen(['sh', str(ROOT / 'install.sh'), *args, '--consumer', 'generic',
            '--target-skills', str(self.target)], env={**os.environ,
            'LINKEASE_BUSINESS_TEST_PAUSE_AT': point, 'LINKEASE_BUSINESS_TEST_PAUSE_FILE': str(marker)},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        def cleanup():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 10
        while not Path(str(marker) + '.ready').exists():
            if process.poll() is not None:
                self.fail(str(process.communicate()))
            if time.monotonic() > deadline:
                self.fail('installer did not reach the requested transaction point')
            time.sleep(0.01)
        return process, marker

    def test_live_lock_rejects_second_installer_without_losing_first_selection(self):
        process, marker = self.paused('before-swap', '--bundle', 'development')
        self.assertNotEqual(self.call('--bundle', 'software-management').returncode, 0)
        Path(str(marker) + '.release').touch()
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, stdout + stderr)
        self.assertEqual(set(self.state()['selections']), {'bundle:development'})

    def test_pre_lock_plan_cannot_erase_a_completed_concurrent_install(self):
        process, marker = self.paused('before-lock', '--bundle', 'development')
        self.ok(self.call('--bundle', 'software-management'))
        Path(str(marker) + '.release').touch()
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, stdout + stderr)
        self.assertEqual(set(self.state()['selections']), {'bundle:development', 'bundle:software-management'})

    def test_sigkill_after_old_directory_move_is_recovered_by_next_install(self):
        self.ok(self.call('--skill', 'kai-software'))
        process, marker = self.paused('after-old-move', '--bundle', 'development')
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate(timeout=5)
        self.assertFalse(self.target.exists())
        self.ok(self.call('--bundle', 'development'))
        self.assertEqual(set(self.state()['selections']), {'skill:kai-software', 'bundle:development'})
        self.assertEqual(list(self.work.glob('.linkease-business-transaction.*')), [])

    def test_term_before_swap_preserves_old_install_and_cleans_owned_resources(self):
        self.ok(self.call('--skill', 'kai-software'))
        before = tree_digest(self.target)
        process, marker = self.paused('before-swap', '--bundle', 'development')
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate(timeout=5)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual(tree_digest(self.target), before)
        self.assertEqual(list(self.work.glob('.linkease-business-transaction.*')), [])
        self.assertFalse((self.work / '.skills.linkease-business-lock').exists())

    def test_unknown_lock_is_preserved(self):
        lock = self.work / '.skills.linkease-business-lock'; lock.mkdir()
        (lock / 'foreign').write_text('keep')
        self.assertNotEqual(self.call('--skill', 'kai-software').returncode, 0)
        self.assertEqual((lock / 'foreign').read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
