import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('prepare_capability_evaluation', ROOT / 'tools/agent_capabilities/prepare_evaluation.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
contract_spec=importlib.util.spec_from_file_location('evaluation_contract',ROOT/'tools/agent_capabilities/contract.py')
contract=importlib.util.module_from_spec(contract_spec)
contract_spec.loader.exec_module(contract)


class EvaluationMaterialsTests(unittest.TestCase):
    def test_startup_scenarios_have_complete_native_structure_and_valid_uci_sections(self):
        cards=json.loads((ROOT/'tests/agent_capabilities/task-cards.json').read_text())['cards']
        native=(ROOT/'tests/agent_capabilities/fixtures/dockerd-native-init.sh').read_text()
        for card in cards:
            if not card.get('service'):continue
            with self.subTest(card=card['id']):
                docs=card['documents']
                self.assertEqual(docs['/rom/etc/init.d/dockerd'],native)
                for name in ['/rom/etc/init.d/dockerd','/etc/init.d/dockerd']:
                    source=docs[name]
                    self.assertTrue(source.startswith('#!/bin/sh /etc/rc.common\n'))
                    for token in ['USE_PROCD=1','start_service()', 'procd_open_instance','procd_close_instance','process_config']:
                        self.assertIn(token,source)
                    self.assertEqual(subprocess.run(['sh','-n'],input=source,text=True,capture_output=True).returncode,0)
                self.assertIn("config globals 'globals'",docs['/etc/config/dockerd'])
                command=json.loads(docs['/run/kai-service/dockerd.json'])['dockerd']['instances']['main']['command']
                self.assertEqual(command[-1],'--config-file=/tmp/dockerd/daemon.json')
    def test_receipt_scenarios_use_the_actual_published_result_contract(self):
        cards=json.loads((ROOT/'tests/agent_capabilities/task-cards.json').read_text())['cards']
        checked=0
        for card in cards:
            if '/observations/receipt.json' in card['documents']:
                with self.subTest(card=card['id']):
                    contract.validate_result(json.loads(card['documents']['/observations/receipt.json']),expected_target='case-target')
                    checked+=1
        self.assertEqual(checked,3)
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
