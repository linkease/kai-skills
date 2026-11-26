import json
import shlex
import shutil
import unittest

import test_readonly


class RedactionFidelityTests(unittest.TestCase):
    def setUp(self):
        self.fixture = test_readonly.ReadOnlyTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def test_structured_redaction_preserves_nonsecret_facts_and_valid_json(self):
        cases = [
            {'token': 'synthetic-private', 'nested': {'apiKey': 'synthetic-private'}},
            {'authorization': {'token': 'synthetic-private'}},
            {'private_key': ['synthetic-private']},
            {'secretKey': 'synthetic-private'},
            {'token': True},
            {'endpoint': 'https://name:synthetic-private@example.invalid/?token=synthetic-private'},
            {'endpoint': 'https://example.invalid/?key=synthetic-private'},
            {'endpoint': 'https://example.invalid/?auth=synthetic-private'},
        ]
        texts = [json.dumps({**value, 'phase': 'active', 'target': {'path': '/mnt/selected/docker'}})
                 for value in cases]
        texts.append('{"to\\u006ben":"synthetic-private","phase":"active","target":{"path":"/mnt/selected/docker"}}')
        for text in texts:
            with self.subTest(text=text[:40]):
                self.fixture.file('/etc/quickstart/storage/docker.json', text)
                before = self.fixture.fingerprint()
                process, receipt = self.fixture.query('--service', 'dockerd', '--sections', 'config')
                self.assertEqual(process.returncode, 0, receipt)
                field = receipt['facts']['storageRegistration']
                self.assertIn('active', field['content'])
                self.assertNotIn('synthetic-private', json.dumps(receipt))
                value = json.loads(field['content'])
                self.assertEqual(value['target']['path'], '/mnt/selected/docker')
                self.assertTrue(field['redacted'])
                self.assertEqual(before, self.fixture.fingerprint())

    def test_missing_parser_is_unknown_without_install_or_secret_output(self):
        fixture = self.fixture
        fixture.file('/etc/quickstart/storage/docker.json', '{"token":"synthetic-private","phase":"active"}')
        for name in ['sh', 'dirname', 'awk', 'date', 'sed', 'mktemp', 'head', 'wc', 'tr', 'dd', 'sleep', 'cat', 'rm', 'mv']:
            target = shutil.which(name)
            self.assertIsNotNone(target)
            (fixture.bin / name).symlink_to(target)
        marker = fixture.root / 'INSTALL_CALLED'
        for name in ['opkg', 'apk', 'apt-get', 'curl', 'wget']:
            fixture.fake(name, 'touch ' + shlex.quote(str(marker)) + '\nexit 99\n')
        before = fixture.fingerprint()
        process, receipt = fixture.query('--service', 'dockerd', '--sections', 'config',
                                         env={**fixture.env, 'PATH': str(fixture.bin)})
        self.assertNotEqual(process.returncode, 0)
        self.assertIsNone(receipt['facts']['storageRegistration'])
        self.assertIn('REDACTION_UNAVAILABLE', json.dumps(receipt['errors']))
        self.assertNotIn('synthetic-private', json.dumps(receipt))
        self.assertFalse(marker.exists())
        self.assertEqual(before, fixture.fingerprint())

    def test_malformed_or_multiple_sensitive_documents_are_explicitly_unknown(self):
        for text in ['{"token":"synthetic-private","phase":"active"',
                     '{"token":"synthetic-private"}\n{"phase":"active"}']:
            with self.subTest(text=text):
                self.fixture.file('/etc/quickstart/storage/docker.json', text)
                process, receipt = self.fixture.query('--service', 'dockerd', '--sections', 'config')
                self.assertNotEqual(process.returncode, 0)
                self.assertIsNone(receipt['facts']['storageRegistration'])
                self.assertNotIn('synthetic-private', json.dumps(receipt))
                self.assertIn('REDACTION_UNAVAILABLE', json.dumps(receipt['errors']))

    def test_native_command_json_keeps_the_same_nonsecret_fields(self):
        text = json.dumps({'token': 'synthetic-private', 'phase': 'active',
                           'target': {'path': '/mnt/selected/docker'}})
        self.fixture.fake('logread', "printf '%s\\n' " + shlex.quote(text) + '\n')
        process, receipt = self.fixture.query('--service', 'dockerd', '--sections', 'logs',
                                             env={**self.fixture.env, 'ISTOREOS_ROOT': ''})
        self.assertEqual(process.returncode, 0, receipt)
        field = receipt['facts']['logs']
        self.assertIn('active', field['output'])
        self.assertNotIn('synthetic-private', json.dumps(receipt))
        self.assertEqual(json.loads(field['output'])['target']['path'], '/mnt/selected/docker')
        self.assertTrue(field['redacted'])


if __name__ == '__main__':
    unittest.main()
