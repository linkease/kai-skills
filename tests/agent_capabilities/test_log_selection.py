import json
import shlex
import unittest

import test_readonly


class LogSelectionTests(unittest.TestCase):
    def setUp(self):
        self.fixture = test_readonly.ReadOnlyTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.calls = self.fixture.root / 'calls'
        self.env = {**self.fixture.env, 'ISTOREOS_ROOT': '', 'CALLS': str(self.calls)}

    def test_explicit_native_log_scope_is_literal_and_attributed(self):
        marker = self.fixture.root / 'EXECUTED'
        pattern = 'fatal|unfamiliar;$(touch ' + str(marker) + ')'
        self.fixture.fake('logread', 'printf "%s\\n" "$@" > "$CALLS"\nprintf "selected old failure\\n"\n')
        process, receipt = self.fixture.query('--service', 'example', '--sections', 'logs',
            '--log-count', '25', '--log-pattern', pattern, env=self.env)
        self.assertEqual(process.returncode, 0, receipt)
        self.assertEqual(self.calls.read_text().splitlines(), ['-l', '25', '-e', pattern])
        self.assertFalse(marker.exists())
        self.assertEqual(receipt['facts']['logSelection'],
                         {'tailMessages': 25, 'pattern': pattern, 'completeHistory': False})
        self.assertIn('selected old failure', receipt['facts']['logs']['output'])
        self.assertEqual(receipt['effects']['completed'], [])

    def test_unselected_logs_have_no_implicit_service_filter_or_tail(self):
        self.fixture.fake('logread', 'printf "%s" "$*" > "$CALLS"\nprintf "unrelated and old failure\\n"\n')
        process, receipt = self.fixture.query('--service', 'example', '--sections', 'logs', env=self.env)
        self.assertEqual(process.returncode, 0, receipt)
        self.assertEqual(self.calls.read_text(), '')
        self.assertNotIn('logSelection', receipt['facts'])
        self.assertIn('unrelated and old failure', receipt['facts']['logs']['output'])

    def test_invalid_or_ignored_scope_never_invokes_native_logread(self):
        self.fixture.fake('logread', 'echo called > "$CALLS"\n')
        for args in [('--sections', 'logs', '--log-count', '0'),
                     ('--sections', 'logs', '--log-count', '1001'),
                     ('--sections', 'logs', '--log-count', '1;true'),
                     ('--sections', 'logs', '--log-pattern', 'x' * 257),
                     ('--sections', 'config', '--log-count', '10'),
                     ('--file', '/var/log/example.log', '--log-count', '10')]:
            with self.subTest(args=args):
                process, receipt = self.fixture.query('--service', 'example', *args, env=self.env)
                self.assertNotEqual(process.returncode, 0)
                self.assertIn('INVALID_ARGUMENT', json.dumps(receipt['errors']))
        self.assertFalse(self.calls.exists())

    def test_even_a_selected_window_keeps_the_original_output_limit(self):
        self.fixture.fake('logread', "printf '%s' " + shlex.quote('x' * 5000) + '\n')
        process, receipt = self.fixture.query('--service', 'example', '--sections', 'logs',
            '--log-count', '1', env=self.env)
        self.assertNotEqual(process.returncode, 0)
        self.assertIsNone(receipt['facts']['logs'])
        self.assertIn('PROBE_OUTPUT_LIMIT', json.dumps(receipt['errors']))
        self.assertFalse(receipt['truncated'])


if __name__ == '__main__':
    unittest.main()
