import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('prepare_capability_evaluation', ROOT / 'tools/agent_capabilities/prepare_evaluation.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class EvaluationMaterialsTests(unittest.TestCase):
    def test_full_matrix_stays_frozen_and_every_card_has_a_withheld_rubric(self):
        cards = json.loads((ROOT / 'tests/agent_capabilities/task-cards.json').read_text())['cards']
        scope = json.loads((ROOT / 'tests/agent_capabilities/evaluation-scope.json').read_text())
        self.assertEqual(len(cards), 12)
        self.assertEqual(len({c['id'] for c in cards}), len(cards))
        self.assertEqual(len(cards) * len(scope['conditions']) * scope['modelConfigurations'] * scope['repetitions'], 216)
        for card in cards:
            self.assertTrue(card['prompt'] and card['documents'] and card['rubric'])
            self.assertTrue((ROOT / 'components/system-packs' / card['skill']).is_file())

    def test_model_visible_documents_do_not_include_grading_or_execute_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / 'owned-scenarios'
            with contextlib.redirect_stdout(io.StringIO()):
                prepare.prepare(dest)
            suite = json.loads((dest / 'suite.json').read_text())
            self.assertEqual(len(suite['cards']), 12)
            for card in suite['cards']:
                self.assertNotIn('rubric', card)
                self.assertNotIn('expectedFacts', card)
                root = Path(card['root'])
                self.assertEqual(root.parent, dest)
                for name in card['documents']:
                    path = root / name.lstrip('/')
                    self.assertTrue(path.is_file())
                    self.assertFalse(path.stat().st_mode & 0o111)
            with self.assertRaises(FileExistsError):
                prepare.prepare(dest)


if __name__ == '__main__':
    unittest.main()
