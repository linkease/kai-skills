import importlib.util
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('agent_baseline', ROOT/'tools/agent_capabilities/baseline.py')
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)


class BaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory = baseline.inventory()

    def test_all_published_packages_and_canonical_resources_have_owners(self):
        published = json.loads((ROOT/'business-catalog.json').read_text())
        self.assertEqual({p['id'] for p in published['skills']},
                         {p['id'] for p in self.inventory['packages']})
        paths = {p['path'] for p in self.inventory['entrypoints'] if p['repository']=='kai-skills'}
        for owner, origin in self.inventory['resources'].items():
            for path in baseline.source_files(ROOT/origin):
                self.assertIn(path.relative_to(ROOT).as_posix(), paths, owner)

    def test_entries_have_unique_identity_disposition_and_verifiable_content(self):
        entries = self.inventory['entrypoints']
        self.assertEqual(len(entries), len({(r['repository'], r['path']) for r in entries}))
        for row in entries:
            self.assertTrue(row['owner'] and row['disposition'] and row['milestone'])
            base = ROOT if row['repository']=='kai-skills' else ROOT.parent/'reasonix-kai'
            self.assertEqual(row['sha256'], baseline.sha(base/row['path']))

    def test_known_failures_are_visible_in_frozen_baseline(self):
        frozen = json.loads((ROOT/'docs/verification/agent-capability-baseline-20261126.json').read_text())
        signals = {s['signal'] for row in frozen['entrypoints'] for s in row['reviewSignals']}
        self.assertTrue({'forced-primary-skill', 'success-without-verification',
                         'business-route-gate'} <= signals)

    def test_regression_fixture_preserves_contradictions_without_device_secrets(self):
        path = ROOT/'tests/agent_capabilities/fixtures/docker-registration-conflict.json'
        body = path.read_text(); fixture = json.loads(body)
        self.assertEqual(fixture['registration']['phase'], 'active')
        self.assertNotEqual(fixture['configuredRoot'], fixture['registration']['targetRoot'])
        self.assertTrue(fixture['procdRunningWhileWaiting'])
        self.assertFalse(fixture['dockerApiReachable'])
        self.assertNotRegex(body, r'192\.168\.|sk-[A-Za-z0-9]{10,}|BEGIN .*PRIVATE KEY')

    def test_plan_requirements_cases_and_dependencies_are_complete(self):
        root = ROOT/'docs/architecture'
        plan = json.loads((root/'agent-capability-plan-20261126.json').read_text())
        self.assertEqual(plan['sourceSHA256'], baseline.sha(root/plan['source']))
        stages = {m['id']: m for m in plan['milestones']}
        self.assertEqual(set(stages), {f'KA{i}' for i in range(11)})
        self.assertEqual({r['id'] for r in plan['requirements']}, {f'R{i:02}' for i in range(1,21)})
        for requirement in plan['requirements']:
            self.assertTrue(requirement['milestones'])
            for stage in requirement['milestones']:
                self.assertIn(requirement['id'], stages[stage]['requirements'])
        visiting, visited = set(), set()
        def visit(mid):
            self.assertNotIn(mid, visiting)
            if mid in visited: return
            visiting.add(mid)
            for dep in stages[mid]['dependsOn']: visit(dep)
            visiting.remove(mid); visited.add(mid)
        for mid, stage in stages.items():
            visit(mid)
            self.assertTrue(stage['requiredTests'])
        cases = [t['id'] for m in stages.values() for t in m['requiredTests']]
        self.assertEqual(len(cases), len(set(cases)))
        self.assertEqual(len(cases), 57)


if __name__ == '__main__':
    unittest.main()
