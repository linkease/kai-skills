"""Public PKI CLI contracts against the native Windows certificate stores."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == 'win32' and os.environ.get('KAI_NATIVE_PKI_HELPER'),
                     'requires native Windows and a current trusted PKI bundle')
class NativeWindowsPkiTests(unittest.TestCase):
    def call(self, action, state, bundle=None, extra=()):
        argv = ['pwsh.exe', '-NoProfile', '-NonInteractive', '-File',
                os.environ['KAI_NATIVE_PKI_HELPER'], '-Action', action,
                '-StateDirectory', str(state)]
        if action in ('Check', 'Plan', 'Repair'):
            argv += ['-Bundle', str(bundle or Path(os.environ['KAI_NATIVE_PKI_BUNDLE']))]
        argv += list(extra)
        result = subprocess.run(argv, capture_output=True, text=True,
                                encoding='utf-8', timeout=45)
        self.assertTrue(result.stdout.strip(), result.stderr)
        return result, json.loads(result.stdout)

    def test_plan_valid_bundle_does_not_create_state(self):
        with tempfile.TemporaryDirectory(prefix='kai pki 中文 ') as temporary:
            state = Path(temporary) / 'state'
            result, receipt = self.call('Plan', state)
            self.assertEqual(result.returncode, 0, receipt)
            self.assertEqual(receipt['status'], 'ready')
            self.assertFalse(receipt['systemProxyChanged'])
            self.assertFalse(receipt['rootStoreChanged'])
            self.assertFalse(state.exists())

    def test_refresh_requirement_rejects_material_before_writing(self):
        with tempfile.TemporaryDirectory(prefix='kai pki refresh ') as temporary:
            state = Path(temporary) / 'state'
            result, receipt = self.call('Repair', state, extra=('-MinimumValiditySeconds', '2592000'))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(receipt['status'], 'failed')
            self.assertIn('remaining validity', receipt['message'])
            self.assertFalse(state.exists())

    def test_unowned_lock_file_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix='kai pki foreign lock ') as temporary:
            state = Path(temporary) / 'state'
            state.mkdir()
            lock = state / '.lock'
            lock.write_bytes(b'foreign lock: preserve this content')
            result, receipt = self.call('Repair', state)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(receipt['status'], 'failed')
            self.assertEqual(lock.read_bytes(), b'foreign lock: preserve this content')
            self.assertFalse((state / 'state.json').exists())

    def test_restore_conflicting_owner_preserves_objects_then_recovers(self):
        import uuid
        with tempfile.TemporaryDirectory(prefix='kai pki ownership ') as temporary:
            state = Path(temporary) / 'state'
            result, receipt = self.call('Repair', state)
            self.assertEqual(result.returncode, 0, receipt)
            journal = state / 'state.json'
            original = json.loads(journal.read_text(encoding='utf-8'))
            try:
                changed = {**original, 'owner': str(uuid.uuid4())}
                journal.write_text(json.dumps(changed), encoding='utf-8')
                result, receipt = self.call('Restore', state)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(receipt['status'], 'failed')
                result, receipt = self.call('Plan', state)
                self.assertEqual(result.returncode, 0, receipt)
                self.assertTrue(all(m['present'] for m in receipt['materials']))
            finally:
                journal.write_text(json.dumps(original), encoding='utf-8')
                result, receipt = self.call('Restore', state)
                self.assertEqual(result.returncode, 0, receipt)

    def test_root_candidate_is_rejected_before_writing(self):
        with tempfile.TemporaryDirectory(prefix='kai pki root boundary ') as temporary:
            work = Path(temporary)
            result, roots = self.call('Roots', work / 'state')
            self.assertEqual(result.returncode, 0)
            bundle = json.loads(Path(os.environ['KAI_NATIVE_PKI_BUNDLE']).read_text())
            bundle['certificates'].append({'der': roots['roots'][0], 'source': 'native-root'})
            changed = work / 'invalid-root.json'
            changed.write_text(json.dumps(bundle), encoding='utf-8')
            state = work / 'state'
            result, receipt = self.call('Repair', state, changed)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(receipt['status'], 'failed')
            self.assertFalse(state.exists())

    def test_repair_is_idempotent_and_restore_preserves_previous_material(self):
        with tempfile.TemporaryDirectory(prefix='kai pki lifecycle 中文 ') as temporary:
            state = Path(temporary) / 'state'
            before, roots_before = self.call('Roots', state)
            self.assertEqual(before.returncode, 0)
            result, plan = self.call('Plan', state)
            self.assertEqual(result.returncode, 0, plan)
            previous = {(m['kind'], m['sha256']): m['present'] for m in plan['materials']}
            try:
                result, receipt = self.call('Repair', state)
                self.assertEqual(result.returncode, 0, receipt)
                self.assertEqual(receipt['added'], sum(not x for x in previous.values()))
                result, receipt = self.call('Repair', state)
                self.assertEqual(result.returncode, 0, receipt)
                self.assertEqual(receipt['added'], 0)
                self.assertEqual(receipt['reused'], len(previous))
                result, receipt = self.call('Check', state)
                self.assertEqual(result.returncode, 0, receipt)
                self.assertEqual(receipt['status'], 'healthy')
            finally:
                result, restored = self.call('Restore', state)
                self.assertEqual(result.returncode, 0, restored)
            result, plan_after = self.call('Plan', state)
            self.assertEqual(result.returncode, 0, plan_after)
            self.assertEqual({(m['kind'], m['sha256']): m['present'] for m in plan_after['materials']}, previous)
            result, roots_after = self.call('Roots', state)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(set(roots_before['roots']), set(roots_after['roots']))
            result, receipt = self.call('Restore', state)
            self.assertEqual(result.returncode, 0, receipt)

    def test_tampered_crl_is_rejected_before_any_state_write(self):
        import base64
        with tempfile.TemporaryDirectory(prefix='kai pki invalid 中文 ') as temporary:
            work = Path(temporary)
            bundle = json.loads(Path(os.environ['KAI_NATIVE_PKI_BUNDLE']).read_text())
            value = bytearray(base64.b64decode(bundle['crls'][0]['der']))
            value[-1] ^= 1
            bundle['crls'][0]['der'] = base64.b64encode(value).decode()
            changed = work / 'invalid.json'
            changed.write_text(json.dumps(bundle), encoding='utf-8')
            state = work / 'state'
            result, receipt = self.call('Repair', state, changed)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(receipt['status'], 'failed')
            self.assertFalse(state.exists())


if __name__ == '__main__':
    unittest.main()
