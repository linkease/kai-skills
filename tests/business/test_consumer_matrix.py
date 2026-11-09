import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ConsumerMatrixTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='kai consumer matrix 中文 ')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.home = self.work / 'home'
        self.xdg = self.work / 'xdg'
        self.project = self.work / 'project'
        for directory in (self.home, self.xdg, self.project):
            directory.mkdir()
        self.environment = {
            **os.environ,
            'HOME': str(self.home),
            'XDG_CONFIG_HOME': str(self.xdg),
            'KAI_SKILLS_PROJECT_ROOT': str(self.project),
            'KAI_SKILLS_RELEASE': '6.0.0-matrix',
        }
        self.environment.pop('CODEX_HOME', None)

    def call(self, consumer, scope, action=None, target=None):
        args = ['sh', str(ROOT / 'install.sh'), '--skill', 'kai-software',
                '--consumer', consumer, '--scope', scope]
        if target is not None:
            args.extend(['--target-skills', str(target)])
        if action is not None:
            args.append(action)
        return subprocess.run(args, env=self.environment, text=True,
                              capture_output=True, timeout=60)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_three_consumers_at_user_and_project_scope(self):
        matrix = {
            ('codex', 'user'): self.home / '.agents/skills',
            ('codex', 'project'): self.project / '.agents/skills',
            ('claude', 'user'): self.home / '.claude/skills',
            ('claude', 'project'): self.project / '.claude/skills',
            ('opencode', 'user'): self.xdg / 'opencode/skills',
            ('opencode', 'project'): self.project / '.opencode/skills',
        }
        for (consumer, scope), target in matrix.items():
            with self.subTest(consumer=consumer, scope=scope):
                self.assert_ok(self.call(consumer, scope))
                state = json.loads((target / '.linkease-skills/business-state.json').read_text())
                selection = state['selections']['skill:kai-software']
                self.assertEqual(selection['consumer'], consumer)
                self.assertEqual(selection['scope'], scope)
                self.assertEqual(selection['release'], '6.0.0-matrix')
                self.assert_ok(self.call(consumer, scope, '--upgrade'))
                self.assert_ok(self.call(consumer, scope, '--uninstall'))
                self.assertFalse((target / 'kai-software').exists())

    def test_explicit_target_wins_without_losing_consumer_scope_identity(self):
        target = self.work / 'explicit target'
        self.assert_ok(self.call('claude', 'project', target=target))
        selection = json.loads(
            (target / '.linkease-skills/business-state.json').read_text()
        )['selections']['skill:kai-software']
        self.assertEqual((selection['consumer'], selection['scope']), ('claude', 'project'))
        self.assertFalse((self.project / '.claude').exists())


if __name__ == '__main__':
    unittest.main()
