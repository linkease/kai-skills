import functools
import http.server
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('business_release', ROOT / 'tools/release/business_release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='business release 中文 ')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work = Path(cls.temp.name)
        # A real clean commit, without changing the developer's working tree.
        cls.source = cls.work / 'source'; cls.source.mkdir()
        for name in ('skills', 'bundles'):
            shutil.copytree(ROOT / name, cls.source / name)
        for name in ('business-catalog.json', 'install.sh', 'install.ps1', 'tools/install-business.sh',
                     'tools/build-release.sh', 'tools/release/business_release.py',
                     'docs/verification/business-bm0-inventory.json'):
            target = cls.source / name; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        for args in (['init', '-q'], ['add', '.'],
                     ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                      '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture']):
            subprocess.run(['git', '-C', str(cls.source), *args], check=True, capture_output=True)
        cls.first, cls.second = cls.work / 'first', cls.work / 'second'
        cls.manifest = release.build(cls.source, cls.first)
        release.build(cls.source, cls.second)

    def extract(self, kind, identity):
        artifact = next(a for a in self.manifest['artifacts']
                        if a['kind'] == kind and a['id'] == identity and a['format'] == 'zip')
        destination = Path(tempfile.mkdtemp(prefix='relocated 中文 ', dir=self.work))
        release.unpack(self.first / artifact['path'], 'zip', destination, artifact['root'])
        return destination / artifact['root']

    def command(self, *args):
        result = subprocess.run(args, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_all_units_have_two_identical_builds_and_exact_single_skill_bytes(self):
        self.assertEqual(len(self.manifest['packages']), 32)
        self.assertEqual(len(self.manifest['collections']), 12)
        self.assertEqual(len(self.manifest['artifacts']), 88)
        self.assertEqual({p.name: release.sha(p) for p in self.first.iterdir()},
                         {p.name: release.sha(p) for p in self.second.iterdir()})
        for package in self.manifest['packages']:
            single = self.extract('skill', package['id'])
            self.assertEqual(release.tree_digest(single), package['treeDigest'])
            self.assertEqual(list(single.rglob('SKILL.md')), [single / 'SKILL.md'])

    def test_every_offline_collection_installs_upgrades_and_uninstalls_after_relocation(self):
        for collection in self.manifest['collections']:
            identity = Path(collection['lockPath']).stem
            with self.subTest(identity=identity):
                bundle = self.extract(collection['kind'], identity)
                renamed = bundle.with_name('renamed 根目录'); bundle.rename(renamed)
                target = renamed.parent / 'agent skills 中文'
                if collection['kind'] == 'bundle':
                    selection = ['--bundle', identity]
                else:
                    selection = ['--platform', collection['platform'], '--all', '--mode', collection['mode']]
                arguments = ['sh', str(renamed / 'install.sh'), *selection,
                             '--consumer', 'generic', '--target-skills', str(target)]
                plan = self.command(*arguments, '--dry-run', '--json')
                self.assertFalse(target.exists())
                self.assertEqual({p['id'] for p in json.loads(plan.stdout)['packages']},
                                 {p['id'] for p in collection['members']})
                self.command(*arguments)
                self.assertEqual({p.parent.name for p in target.glob('*/SKILL.md')},
                                 {p['id'] for p in collection['members']})
                self.command(*arguments, '--upgrade')
                self.command(*arguments, '--uninstall')
                self.assertEqual(list(target.glob('*/SKILL.md')), [])

    def test_native_powershell_first_plan_finds_embedded_bootstrap_for_both_business_collections(self):
        powershell = os.environ.get('KAI_DESKTOP_PWSH') or shutil.which('pwsh')
        self.assertTrue(powershell, 'PowerShell is required; do not skip native entry contracts')
        for identity in ('development', 'software-management'):
            directory = self.extract('bundle', identity)
            target = directory.parent / 'untouched'
            result = self.command(powershell, '-NoLogo', '-NoProfile', '-NonInteractive', '-File',
                                  str(directory / 'install.ps1'), '-Bundle', identity, '-Action', 'Plan',
                                  '-TargetSkills', str(target))
            plan = json.loads(result.stdout)
            self.assertTrue(Path(plan['bootstrap']).is_file())
            self.assertIn('resources/runtime/kai-tool-bootstrap', plan['bootstrap'].replace('\\', '/'))
            self.assertFalse(target.exists())

    def valid_evidence(self):
        evidence = release.evidence_template(self.first)
        receipts = self.work / 'receipts'; receipts.mkdir(exist_ok=True)
        receipt = receipts / 'fixture-result.txt'; receipt.write_text('synthetic gate fixture only\n')
        for result in evidence['results']:
            result['status'] = 'passed'
            result['receipts'] = [{'path': receipt.name, 'sha256': release.sha(receipt)}]
        path = receipts / 'evidence.json'; release.write_json(path, evidence)
        return path, evidence

    def test_release_gate_requires_every_frozen_case_and_exact_candidate_receipts(self):
        path, evidence = self.valid_evidence()
        passed = release.gate(self.first, path)
        self.assertEqual(passed['status'], 'release-ready')
        self.assertEqual(len([r for r in self.manifest['requirements'] if r['kind'] == 'native']), 30)
        self.assertGreater(passed['requiredPassed'], 100)
        for mutation in ('missing', 'failed', 'stale-package', 'bad-receipt', 'stale-manifest'):
            modified = json.loads(json.dumps(evidence))
            if mutation == 'missing': modified['results'].pop()
            if mutation == 'failed': modified['results'][0]['status'] = 'skipped'
            if mutation == 'stale-package': modified['results'][0]['packageDigests'] = {}
            if mutation == 'bad-receipt': modified['results'][0]['receipts'][0]['sha256'] = 'sha256:' + '0' * 64
            if mutation == 'stale-manifest': modified['manifestDigest'] = 'sha256:' + '0' * 64
            release.write_json(path, modified)
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                release.gate(self.first, path)

    def test_build_records_actual_dirty_state_and_never_overwrites_existing_output(self):
        path = self.source / 'install.sh'
        original = path.read_bytes()
        try:
            path.write_bytes(original + b'\n# fixture dirty source\n')
            output = self.work / 'dirty'
            manifest = release.build(self.source, output)
            self.assertEqual(manifest['sourceState'], 'worktree')
            with self.assertRaisesRegex(ValueError, 'clean committed'):
                release.gate(output, self.work / 'absent-evidence.json')
            with self.assertRaisesRegex(ValueError, 'new directory'):
                release.build(self.source, output)
        finally:
            path.write_bytes(original)

    def test_tampered_archive_and_missing_artifact_are_rejected(self):
        for mutation in ('changed', 'missing'):
            output = Path(tempfile.mkdtemp(dir=self.work))
            for path in self.first.iterdir():
                shutil.copyfile(path, output / path.name)
            archive = output / self.manifest['artifacts'][0]['path']
            if mutation == 'changed': archive.write_bytes(archive.read_bytes() + b'tampered')
            else: archive.unlink()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                release.verify(output)

    def test_unpack_rejects_traversal_windows_drive_paths_and_symbolic_links(self):
        for name in ('../escape', 'root/../../escape', 'C:/escape', 'root/dir\\escape', 'other/file'):
            with tempfile.TemporaryDirectory(dir=self.work) as temporary:
                temporary = Path(temporary)
                path = temporary / 'unsafe.zip'
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr(name, b'unsafe')
                with self.subTest(name=name), self.assertRaises(ValueError):
                    release.unpack(path, 'zip', temporary / 'destination', 'root')
        with tempfile.TemporaryDirectory(dir=self.work) as temporary:
            temporary = Path(temporary)
            path = temporary / 'link.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                info = zipfile.ZipInfo('root/link'); info.create_system = 3
                info.external_attr = 0o120777 << 16
                archive.writestr(info, b'/outside')
            with self.assertRaises(ValueError):
                release.unpack(path, 'zip', temporary / 'destination', 'root')

    def test_download_fetches_new_bytes_and_rejects_a_different_remote_manifest(self):
        class QuietHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args): pass
        handler = functools.partial(QuietHandler, directory=str(self.first))
        with http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                url = 'http://127.0.0.1:' + str(server.server_port)
                downloaded = self.work / 'fresh download 中文'
                release.fetch(self.first / 'release-manifest.json', url, downloaded, allow_http=True)
                self.assertEqual(release.sha(downloaded / 'release-manifest.json'),
                                 release.sha(self.first / 'release-manifest.json'))
                pinned = self.work / 'wrong-manifest.json'
                pinned.write_bytes((self.first / 'release-manifest.json').read_bytes() + b'\n')
                failed = self.work / 'failed download'
                with self.assertRaisesRegex(ValueError, 'differs from frozen'):
                    release.fetch(pinned, url, failed, allow_http=True)
                self.assertFalse(failed.exists())
            finally:
                server.shutdown(); thread.join()


if __name__ == '__main__':
    unittest.main()
