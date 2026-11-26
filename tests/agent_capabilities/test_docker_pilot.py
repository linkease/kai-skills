import json
from pathlib import Path
import unittest

import test_readonly
ROOT=test_readonly.ROOT


class DockerPilotTests(unittest.TestCase):
    def setUp(self):
        self.fixture = test_readonly.ReadOnlyTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def seed(self, wrapper, configured, registered, error):
        f = self.fixture
        f.file('/etc/init.d/dockerd', '#!/bin/sh\nexec ' + wrapper + ' dockerd "$@"\n')
        f.file('/rom/etc/init.d/dockerd', '#!/bin/sh\nprocd_set_param command /usr/bin/dockerd\n')
        f.file('/etc/config/dockerd', "option data_root '" + configured + "'\n")
        f.file('/tmp/dockerd/daemon.json', json.dumps({'data-root': configured}))
        f.file('/etc/quickstart/storage/docker.json', json.dumps({'phase': 'active', 'targetRoot': registered, 'configDigest': 'local-recomputable-digest'}))
        f.file('/run/kai-service/dockerd.json', json.dumps({'command': [wrapper, 'dockerd'], 'running': False}))
        f.file('/var/log/dockerd.log', 'wrapper: entered\n' + error + '\nwrapper: exit 1\n')

    def test_frozen_history_and_unfamiliar_wrapper_preserve_all_conflicting_sources(self):
        history = json.loads((ROOT / 'tests/agent_capabilities/fixtures/docker-registration-conflict.json').read_text())
        for wrapper in [history['launcher'], '/usr/local/libexec/unseen-start-boundary']:
            with self.subTest(wrapper=wrapper):
                self.seed(wrapper, history['configuredRoot'], history['registration']['targetRoot'], history['lastError'])
                before = self.fixture.fingerprint()
                p, receipt = self.fixture.query('--service', 'dockerd')
                self.assertEqual(p.returncode, 0, receipt)
                text = json.dumps(receipt)
                for fact in [wrapper, history['configuredRoot'], history['registration']['targetRoot'], 'active', 'DOCKER_DATA_ROOT_CHANGED', 'exit 1']:
                    self.assertIn(fact, text)
                self.assertEqual(before, self.fixture.fingerprint())
                self.assertEqual(receipt['effects'], {'requested': [], 'completed': [], 'unknown': [], 'remaining': []})
                for prescription in ['nextAction', 'taskComplete', 'mustRemoveGuard']:
                    self.assertNotIn(prescription, receipt)

    def test_opposite_evidence_does_not_invent_a_registration_conflict_or_guard_failure(self):
        self.seed('/usr/bin/dockerd', '/mnt/selected/docker', '/mnt/selected/docker', 'container initialization failed: read-only filesystem')
        before = self.fixture.fingerprint()
        _, receipt = self.fixture.query('--service', 'dockerd')
        text = json.dumps(receipt)
        self.assertIn('read-only filesystem', text)
        self.assertNotIn('DOCKER_DATA_ROOT_CHANGED', text)
        self.assertNotIn('quickstart-storage-guard', text)
        self.assertEqual(before, self.fixture.fingerprint())

    def test_large_log_is_explicitly_expandable_and_late_evidence_remains_readable(self):
        self.seed('/usr/libexec/unknown-launcher', '/mnt/chosen/docker', '/mnt/other/docker', 'initial failure')
        text = ('unrelated observation\n' * 200) + 'opaque-wrapper policy-denial: chosen endpoint differs\n'
        path = self.fixture.file('/var/log/dockerd.log', text)
        _, receipt = self.fixture.query('--service', 'dockerd', '--sections', 'logs')
        self.assertTrue(receipt['facts']['logs']['hasMore'])
        self.assertIsNone(receipt['facts']['logs']['content'])
        offset = len(text.encode()) - 120
        _, page = self.fixture.query('--service', 'dockerd', '--file', '/var/log/dockerd.log', '--offset', str(offset), '--length', '120')
        self.assertIn('chosen endpoint differs', json.dumps(page))
        self.assertEqual(path.read_text(), text)
