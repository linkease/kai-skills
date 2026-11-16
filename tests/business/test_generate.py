import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/business'))
from generate import generate
from model import Distribution
from package import tree_digest

compose_spec = importlib.util.spec_from_file_location('compose', ROOT / 'tools/compose.py')
compose = importlib.util.module_from_spec(compose_spec)
compose_spec.loader.exec_module(compose)


class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='business generation 中文 ')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)

    def test_independent_and_collection_content_is_identical_and_repeatable(self):
        first, second = self.work / 'a', self.work / 'b'
        generate(first); generate(second)
        self.assertEqual(tree_digest(first), tree_digest(second))
        distribution = Distribution()
        catalog = json.loads((first / 'business-catalog.json').read_text())
        capabilities = json.loads((first / 'capability-catalog.json').read_text())
        self.assertEqual(len(catalog['skills']), 32)
        self.assertEqual(catalog['capabilityCatalog'], 'capability-catalog.json')
        self.assertEqual(capabilities, distribution.capability_catalog())
        self.assertEqual(len(list((first / 'bundles').glob('*.json'))), 12)
        packages = {p['id']: p for p in catalog['skills']}
        for bundle in (first / 'bundles').glob('*.json'):
            value = json.loads(bundle.read_text())
            for member in value['members']:
                self.assertEqual(member['treeDigest'], tree_digest(first / 'skills' / member['id']))
                self.assertEqual(member['version'], packages[member['id']]['version'])
        result = subprocess.run(['sh', str(ROOT / 'tools/generate-platforms.sh'), str(first / 'platforms')],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for preset in distribution.legacy['presets']:
            directory = first / preset['path']
            selection = distribution.select(platform=preset['platform'], mode=preset['mode'], all_skills=True)
            self.assertEqual({p.parent.name for p in (directory / 'skills').glob('*/SKILL.md')},
                             {p['id'] for p in selection['packages']})
            for package in selection['packages']:
                self.assertEqual(tree_digest(directory / 'skills' / package['id']), packages[package['id']]['treeDigest'])

    def test_foreign_output_is_preserved(self):
        directory = self.work / 'foreign' / 'skills' / 'kai-software'
        directory.mkdir(parents=True)
        (directory / 'keep').write_text('user')
        with self.assertRaises(ValueError):
            generate(self.work / 'foreign')
        self.assertEqual((directory / 'keep').read_text(), 'user')

    def test_composition_provenance_reports_the_actual_git_state(self):
        repository = self.work / 'source'
        repository.mkdir()
        subprocess.run(['git', 'init', '-q', str(repository)], check=True)
        subprocess.run(['git', '-C', str(repository), 'config', 'user.email', 'test@example.invalid'], check=True)
        subprocess.run(['git', '-C', str(repository), 'config', 'user.name', 'Test'], check=True)
        (repository / 'tracked').write_text('one')
        subprocess.run(['git', '-C', str(repository), 'add', 'tracked'], check=True)
        subprocess.run(['git', '-C', str(repository), 'commit', '-qm', 'fixture'], check=True)
        original = compose.ROOT
        self.addCleanup(setattr, compose, 'ROOT', original)
        compose.ROOT = repository
        commit, state = compose.git_source()
        self.assertEqual(state, 'committed')
        self.assertEqual(commit, subprocess.check_output(
            ['git', '-C', str(repository), 'rev-parse', 'HEAD'], text=True).strip())
        (repository / 'untracked').write_text('two')
        self.assertEqual(compose.git_source()[1], 'worktree')


if __name__ == '__main__':
    unittest.main()
