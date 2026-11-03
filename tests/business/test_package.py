import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/business'))
from model import Distribution
from package import build_package, tree_digest


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='single skill 中文 ')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.distribution = Distribution()

    def build(self, name):
        directory = self.work / name
        metadata = build_package(self.distribution, name, directory)
        return directory, metadata

    def test_all_public_skills_have_one_discoverable_entry_and_local_sources(self):
        for name in self.distribution.packages:
            directory, metadata = self.build(name)
            self.assertEqual(list(directory.rglob('SKILL.md')), [directory / 'SKILL.md'])
            self.assertEqual(metadata['treeDigest'], tree_digest(directory))
            self.assertTrue((directory / 'resources/source-metadata.json').is_file())
            for line in (directory / 'SKILL.md').read_text().splitlines():
                for link in re.findall(r'\]\(([^)]+)\)', line):
                    if not link.startswith(('http:', 'https:', '#')):
                        self.assertTrue((directory / link.split('#')[0]).exists(), (name, link))

    def test_bootstrap_and_each_public_script_run_with_no_sibling_skill_directory(self):
        entries = {'kai-tool-bootstrap': ('tool.sh', ['probe', 'jq']),
                   'kai-software': ('software.sh', ['info', 'apt:bash']),
                   'kai-dev-environment': ('runtime.sh', ['probe', 'node', 'invalid']),
                   'kai-project-dependencies': ('dependencies.sh', ['sources', 'npm', '22.14.0', str(self.work)]),
                   'kai-download-acceleration': ('accelerate.sh', ['doctor', 'file']),
                   'kai-storage-files': ('usage.sh', ['search', str(self.work), 'known 中文'])}
        for name, (script, args) in entries.items():
            with self.subTest(name=name):
                isolated = self.work / ('root-' + name)
                isolated.mkdir()
                directory = isolated / name
                build_package(self.distribution, name, directory)
                (self.work / 'known 中文').write_text('fixture')
                result = subprocess.run(['bash', str(directory / 'scripts' / script), *args],
                    cwd=self.work, env={**os.environ, 'KAI_PLATFORM': 'ubuntu',
                    'KAI_USAGE_BACKEND': 'native', 'KAI_USAGE_PYTHON': sys.executable,
                    'KAI_KSCLI_BIN': '/no-client'}, capture_output=True, text=True, timeout=20)
                self.assertNotIn('No such file or directory', result.stderr, result.stderr)
                if name in ['kai-tool-bootstrap', 'kai-software', 'kai-storage-files']:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                else:
                    self.assertTrue(result.stdout.strip(), result.stderr)
                    json.loads(result.stdout)

    def test_dependency_project_query_works_without_runtime_skill(self):
        directory, _ = self.build('kai-project-dependencies')
        project = self.work / 'project'; project.mkdir()
        (project / 'package.json').write_text('{"name":"fixture","dependencies":{"x":"1.0.0"}}')
        result = subprocess.run(['bash', str(directory / 'scripts/dependencies.sh'), 'sources', 'npm', '22.14.0', str(project)],
            env={**os.environ, 'KAI_PLATFORM': 'ubuntu'}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)['sources'], [{'name': 'x', 'type': 'registry'}])

    def test_istore_search_offline_fallback_has_its_own_catalog(self):
        directory, _ = self.build('istoreos-app-search')
        result = subprocess.run(['sh', str(directory / 'scripts/search.sh'), 'linkease', '3'],
            env={**os.environ, 'ISTORE_STORE_RESPONSE_FILE': str(self.work / 'absent-store-response')},
            capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rows = json.loads(result.stdout)
        self.assertTrue(rows)
        self.assertTrue(all(row['catalog_source'] == 'first-party-offline' for row in rows))
        self.assertTrue(any(row['name'] == 'linkease' for row in rows))

    def test_istore_executable_failure_survives_log_capture(self):
        directory, _ = self.build('istoreos-run-executable')
        executable = self.work / 'failed.run'
        executable.write_text('#!/bin/sh\nprintf "native-failure-fixture\\n"\nexit 7\n')
        result = subprocess.run(['sh', str(directory / 'scripts/run.sh'), str(executable)],
            env={**os.environ, 'CONFIRM_RUN_EXEC': 'YES', 'CONFIRM_BACKUP_SKIPPED': 'YES',
                'RUN_VIA_ISTORE_DOTRUN': 'no'}, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertIn('native-failure-fixture', result.stdout)

    def test_relocation_has_no_build_directory_dependency(self):
        directory, metadata = self.build('kai-tool-bootstrap')
        moved = self.work / 'moved space 中文' / directory.name
        moved.parent.mkdir(); shutil.move(directory, moved)
        result = subprocess.run(['bash', str(moved / 'scripts/tool.sh'), 'probe', 'jq'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(tree_digest(moved), metadata['treeDigest'])

    def test_generated_shells_parse_and_sibling_resource_paths_stay_inside_package(self):
        for name in self.distribution.packages:
            directory, _ = self.build(name)
            for script in directory.rglob('*.sh'):
                result = subprocess.run(['bash', '-n', str(script)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                for relative in re.findall(r'(\.\./\.\./(?:kai|istoreos|luci|target)-[a-z-]+/)', script.read_text()):
                    resolved = (script.parent / relative).resolve()
                    self.assertTrue(directory in resolved.parents, (name, script, relative))
                    self.assertTrue(resolved.is_dir(), (name, script, relative))

    def test_source_symlink_is_rejected_and_foreign_output_preserved(self):
        directory, _ = self.build('kai-tool-bootstrap')
        with self.assertRaises(ValueError):
            build_package(self.distribution, 'kai-tool-bootstrap', directory)
        self.assertTrue((directory / 'SKILL.md').exists())
        source = self.work / 'source'; source.mkdir()
        (source / 'SKILL.md').write_text('---\nname: kai-tool-bootstrap\ndescription: fixture\n---\n')
        (source / 'external').symlink_to(directory / 'SKILL.md')
        self.distribution.root = self.work
        self.distribution.resources['kai-tool-bootstrap'] = 'source'
        with self.assertRaises(ValueError):
            build_package(self.distribution, 'kai-tool-bootstrap', self.work / 'bad-output')


if __name__ == '__main__':
    unittest.main()
