import json
import unittest

import test_readonly


class SourceViewTests(unittest.TestCase):
    def setUp(self):
        self.fixture = test_readonly.ReadOnlyTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def test_complete_redacted_source_preserves_facts_without_duplicate_view(self):
        source = {'phase': 'active', 'token': 'synthetic-private',
                  'target': {'path': '/mnt/space path/docker'},
                  'flags': [True, None, 3], 'padding': 'x' * 2200}
        self.fixture.file('/etc/quickstart/storage/docker.json', json.dumps(source))
        before = self.fixture.fingerprint()
        process, result = self.fixture.query('--service', 'dockerd', '--sections', 'config', '--length', '4096')
        self.assertEqual(process.returncode, 0, result)
        fact = result['facts']['storageRegistration']
        expected = {**source, 'token': '[REDACTED]'}
        self.assertEqual(json.loads(fact['content']), expected)
        self.assertFalse(fact['hasMore'])
        self.assertTrue(fact['untrusted'])
        self.assertNotIn('jsonValue', fact)
        self.assertNotIn('synthetic-private', json.dumps(result))
        self.assertEqual(before, self.fixture.fingerprint())

    def test_removed_unreleased_option_is_rejected_before_observation(self):
        process, result = self.fixture.query('--service', 'dockerd', '--json-values', 'true')
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual(result['effects']['completed'], [])
        self.assertIn('INVALID_ARGUMENT', json.dumps(result['errors']))


if __name__ == '__main__':
    unittest.main()
