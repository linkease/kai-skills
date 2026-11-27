import json
import unittest

import test_readonly


class JsonValueTests(unittest.TestCase):
    def setUp(self):
        self.fixture = test_readonly.ReadOnlyTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def test_optional_json_value_preserves_redacted_source_and_types(self):
        self.fixture.file('/etc/quickstart/storage/docker.json', json.dumps({
            'phase': 'active', 'token': 'synthetic-private',
            'target': {'path': '/mnt/space path/docker'}, 'flags': [True, None, 3]}))
        before = self.fixture.fingerprint()
        process, result = self.fixture.query('--service', 'dockerd', '--sections', 'config',
                                             '--json-values', 'true')
        self.assertEqual(process.returncode, 0, result)
        fact = result['facts']['storageRegistration']
        self.assertEqual(fact['jsonValue'], json.loads(fact['content']))
        self.assertEqual(fact['jsonValue']['phase'], 'active')
        self.assertEqual(fact['jsonValue']['flags'], [True, None, 3])
        self.assertEqual(fact['jsonValue']['token'], '[REDACTED]')
        self.assertNotIn('synthetic-private', json.dumps(result))
        self.assertEqual(before, self.fixture.fingerprint())

    def test_default_format_and_non_json_text_keep_the_original_content(self):
        self.fixture.file('/etc/config/dockerd', "option data_root '/mnt/chosen/docker'\n")
        self.fixture.file('/tmp/dockerd/daemon.json', '{"data-root":"/mnt/chosen/docker"}')
        _, plain = self.fixture.query('--service', 'dockerd', '--sections', 'config')
        self.assertNotIn('jsonValue', plain['facts']['generatedConfiguration'])
        process, decoded = self.fixture.query('--service', 'dockerd', '--sections', 'config',
                                               '--json-values', 'true')
        self.assertEqual(process.returncode, 0, decoded)
        self.assertEqual(decoded['facts']['configuration']['content'], plain['facts']['configuration']['content'])
        self.assertEqual(decoded['facts']['configuration']['jsonValueStatus'], 'non-json')
        self.assertEqual(decoded['facts']['generatedConfiguration']['jsonValue'],
                         {'data-root': '/mnt/chosen/docker'})

    def test_invalid_json_does_not_produce_an_invented_value(self):
        self.fixture.file('/tmp/dockerd/daemon.json', '{"data-root":')
        process, result = self.fixture.query('--service', 'dockerd', '--sections', 'config',
                                             '--json-values', 'true')
        self.assertNotEqual(process.returncode, 0)
        self.assertIsNone(result['facts']['generatedConfiguration'])
        self.assertIn('JSON_VALUE_UNAVAILABLE', json.dumps(result['errors']))

    def test_native_command_json_value_stays_untrusted_and_no_action_is_added(self):
        self.fixture.fake('ubus', "printf '%s' '{\"unknown-service\":{\"instances\":{\"one\":{\"command\":[\"/unknown/wrapper\"],\"running\":false}}}}'\n")
        process, result = self.fixture.query('--service', 'unknown-service', '--sections', 'runtime',
            '--json-values', 'true', env={**self.fixture.env, 'ISTOREOS_ROOT': ''})
        self.assertEqual(process.returncode, 0, result)
        fact = result['facts']['nativeServiceRecord']
        self.assertEqual(fact['jsonValue'], json.loads(fact['output']))
        self.assertTrue(fact['untrusted'])
        self.assertEqual(result['effects']['requested'], [])
        self.assertNotIn('diagnosis', result['facts'])

    def test_incomplete_file_window_never_claims_a_complete_json_value(self):
        self.fixture.file('/tmp/observed.json', '{"a":1}' + ' ' * 100)
        process, result = self.fixture.query('--service', 'example', '--file', '/tmp/observed.json',
            '--length', '16', '--json-values', 'true')
        self.assertEqual(process.returncode, 0, result)
        fact = result['facts']['selectedFile']
        self.assertTrue(fact['hasMore'])
        self.assertNotIn('jsonValue', fact)
        self.assertEqual(fact['jsonValueStatus'], 'incomplete-window')

    def test_requested_extra_value_does_not_relax_the_receipt_limit(self):
        self.fixture.file('/tmp/observed.json', json.dumps({'text': 'x' * 4000}))
        args = ('--service', 'example', '--file', '/tmp/observed.json', '--length', '4096')
        process, result = self.fixture.query(*args)
        self.assertEqual(process.returncode, 0, result)
        process, result = self.fixture.query(*args, '--json-values', 'true')
        self.assertNotEqual(process.returncode, 0)
        self.assertIn('RESULT_LIMIT', json.dumps(result['errors']))

    def test_missing_selected_parser_returns_unknown_without_installing(self):
        self.fixture.file('/tmp/observed.json', '{"a":1}')
        process, result = self.fixture.query('--service', 'example', '--file', '/tmp/observed.json',
            '--json-values', 'true', env={**self.fixture.env, 'KAI_JQ_BIN': str(self.fixture.root / 'absent')})
        self.assertNotEqual(process.returncode, 0)
        self.assertIsNone(result['facts']['selectedFile'])
        self.assertIn('JSON_VALUE_UNAVAILABLE', json.dumps(result['errors']))


if __name__ == '__main__':
    unittest.main()
