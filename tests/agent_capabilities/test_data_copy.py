import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

from test_writes import ROOT, WriteFixture


class DataCopyTests(WriteFixture, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.script = ROOT / 'components/system-packs/istoreos/skills/istoreos-docker-data-root-migrate/scripts/apply.sh'
        self.source = self.root / 'source 数据'
        self.source.mkdir()
        self.destination = self.root / 'destination 数据'
        self.data = self.source / 'content'
        self.data.write_bytes(b'actual-source-data' * 256)
        self.data.chmod(0o640)
        os.utime(self.data, (1700000000, 1700000000))
        os.link(self.data, self.source / 'hard-link')
        (self.source / 'symbolic-link').symlink_to('content')
        self.real_rsync = shutil.which('rsync')
        self.assertTrue(self.real_rsync, 'Native rsync is required for the copy property test')
        self.fake('pidof', '''import os,sys
from pathlib import Path
if Path(os.environ['TEST_RUNNING']).exists():print('123');sys.exit(0)
sys.exit(1)
''')
        self.fake('docker', '''import os,sys
if os.environ.get('TEST_COPY_ENGINE_UP'):print('engine-one');sys.exit(0)
if os.environ.get('TEST_COPY_ENGINE_DENIED'):print('permission denied',file=sys.stderr);sys.exit(1)
print('Cannot connect to the Docker daemon: connection refused',file=sys.stderr);sys.exit(1)
''')

    def identity(self, path):
        inode = subprocess.check_output(['/usr/bin/stat', '-c', '%d:%i', str(path)], text=True).strip()
        filesystem = subprocess.check_output(['/usr/bin/stat', '-f', '-c', '%t:%i', str(path)], text=True).strip()
        return inode + ':' + filesystem

    def request(self, **parameters):
        self.index += 1
        path = self.root / ('copy-request-' + str(self.index) + '.json')
        value = {'schemaVersion': 1, 'operation': 'docker.data.copy', 'targetId': 'test-target', 'parameters': {
            'operationId': 'copy-' + str(self.index), 'source': str(self.source), 'destination': str(self.destination),
            'sourceIdentity': self.identity(self.source),
            'destinationIdentity': self.identity(self.destination) if self.destination.exists() else 'absent',
            'destinationParentIdentity': self.identity(self.root), 'serviceName': 'example',
            'endpoint': 'unix:///var/run/docker.sock', 'maxSourceBytes': 1048576, 'reserveBytes': 0, 'timeoutSeconds': 3,
            **parameters}}
        path.write_text(json.dumps(value))
        return path

    def test_copy_validates_real_contents_metadata_links_and_xattrs_without_changing_configuration(self):
        os.setxattr(self.data, 'user.kai-copy-test', b'preserved')
        before_config = self.config.read_bytes()
        before_init = self.init.read_bytes()
        request = self.request()
        p, result = self.apply(request)
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual(result['operationStatus'], 'succeeded')
        target = self.destination / 'content'
        self.assertEqual(target.read_bytes(), self.data.read_bytes())
        self.assertEqual(target.stat().st_mode, self.data.stat().st_mode)
        self.assertEqual(target.stat().st_mtime_ns, self.data.stat().st_mtime_ns)
        self.assertEqual(os.getxattr(target, 'user.kai-copy-test'), b'preserved')
        self.assertEqual(target.stat().st_ino, (self.destination / 'hard-link').stat().st_ino)
        self.assertEqual(os.readlink(self.destination / 'symbolic-link'), 'content')
        self.assertEqual(before_config, self.config.read_bytes())
        self.assertEqual(before_init, self.init.read_bytes())
        self.assertFalse(self.calls.exists(), 'Copy must not change UCI or start/stop a service')
        p, repeated = self.apply(request)
        self.assertEqual(p.returncode, 0)
        self.assertEqual(repeated, result)

    def test_nonempty_destination_is_never_merged_even_when_uci_already_points_to_it(self):
        self.destination.mkdir()
        unrelated = self.destination / 'unrelated-data'
        unrelated.write_text('do not merge')
        self.config.write_text(json.dumps({'main': {'data_root': str(self.destination)}}))
        p, result = self.apply(self.request())
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'DESTINATION_NOT_EMPTY')
        self.assertEqual(unrelated.read_text(), 'do not merge')
        self.assertFalse((self.destination / 'content').exists())

    def test_uci_equality_does_not_skip_copying_an_explicit_real_source(self):
        self.config.write_text(json.dumps({'main': {'data_root': str(self.destination)}}))
        p, result = self.apply(self.request())
        self.assertEqual(p.returncode, 0, result)
        self.assertEqual((self.destination / 'content').read_bytes(), self.data.read_bytes())
        self.assertFalse(result['facts']['copyScope']['configurationChanged'])
        self.assertFalse(result['facts']['copyScope']['servicesChanged'])

    def test_active_daemon_or_unknown_engine_permission_blocks_before_copy(self):
        self.running.touch()
        p, result = self.apply(self.request())
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'SOURCE_ACTIVE')
        self.assertFalse(self.destination.exists())
        self.running.unlink()
        p, result = self.apply(self.request(), TEST_COPY_ENGINE_DENIED='1')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'QUIESCENCE_UNKNOWN')
        self.assertFalse(self.destination.exists())

    def test_space_budget_and_changed_source_identity_block_before_copy(self):
        p, result = self.apply(self.request(sourceIdentity='different-filesystem'))
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'PRECONDITION_CHANGED')
        self.assertFalse(self.destination.exists())
        self.fake('df', "print('Filesystem 1024-blocks Used Available Capacity Mounted')\nprint('fixture 100 100 0 100% /fixture')\n")
        p, result = self.apply(self.request())
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'INSUFFICIENT_SPACE')
        self.assertFalse(self.destination.exists())

    def test_interrupted_copy_keeps_residual_data_and_does_not_replay_or_delete(self):
        self.fake('rsync', r'''import os,sys
from pathlib import Path
destination=Path(sys.argv[-1]);(destination/'partial').write_text('partial copy')
with open(os.environ['TEST_CALLS'],'a') as calls:calls.write('copy-invoked\n')
sys.exit(23)
''')
        request = self.request()
        p, result = self.apply(request)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['operationStatus'], 'unknown')
        self.assertEqual([e['id'] for e in result['effects']['unknown']], ['data-copy'])
        self.assertEqual((self.destination / 'partial').read_text(), 'partial copy')
        before = self.calls.read_bytes()
        p, repeat = self.apply(request)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(repeat, result)
        self.assertEqual(self.calls.read_bytes(), before)
        self.assertTrue(self.data.exists())
        p, result = self.apply(self.request())
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['errors'][0]['code'], 'DESTINATION_NOT_EMPTY')

    def test_checksum_comparison_failure_does_not_claim_copy_verified(self):
        self.fake('rsync', 'import os,sys\n' +
                  "if '--dry-run' in sys.argv:print('>fc........ changed-content');sys.exit(0)\n" +
                  'os.execv(' + repr(self.real_rsync) + ',[' + repr(self.real_rsync) + ']+sys.argv[1:])\n')
        p, result = self.apply(self.request())
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(result['verification']['status'], 'failed')
        self.assertEqual(result['operationStatus'], 'partial')
        self.assertTrue((self.destination / 'content').exists())
        self.assertTrue(self.data.exists())


if __name__ == '__main__':
    unittest.main()
