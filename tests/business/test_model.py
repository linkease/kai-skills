import copy
import importlib.util
from pathlib import Path
import tempfile
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('business_model', ROOT / 'tools/business/model.py')
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.distribution = model.Distribution()

    def test_shared_skills_have_only_kai_names_and_no_historical_aliases(self):
        self.assertEqual(self.distribution.composition['aliases'], {})
        shared = [p for p in self.distribution.packages.values()
                  if p['component'] in ('common', 'linux')]
        self.assertEqual(len(shared), 9)
        self.assertIn("kai-system-information", {p["id"] for p in shared})
        for package in shared:
            self.assertTrue(package['id'].startswith('kai-'))
            body = (ROOT / package['canonicalPath'] / 'SKILL.md').read_text()
            self.assertNotRegex(body.split('---', 2)[1], r'(?m)^aliases\s*:')
        for name in ('istoreos-download-acceleration', 'istoreos-mise-runtime',
                     'istoreos-network-quality', 'istoreos-package-manager', 'istoreos-storage-path'):
            self.assertNotIn(name, self.distribution.packages)
            for package in self.distribution.packages.values():
                self.assertNotIn(name, package['description'])
            with self.assertRaises(ValueError):
                self.distribution.select(skill=name)
        self.assertIn('istoreos-download-acceleration',
                      self.distribution.runtime_closure('istoreos-kspeeder-domainfold-fetch'))

    def test_capability_catalog_covers_every_business_package_and_keeps_personal_dynamic(self):
        catalog = self.distribution.capability_catalog()
        self.assertEqual([group['id'] for group in catalog['groups']],
                         ['software', 'istoreos', 'systems', 'personal'])
        self.assertEqual(len(catalog['capabilities']), 25)
        personal = next(group for group in catalog['groups'] if group['kind'] == 'personal')
        self.assertEqual(personal['id'], 'personal')
        self.assertNotIn('personal', {item['group'] for item in catalog['capabilities']})
        covered = {module['id'] for item in catalog['capabilities'] for module in item['modules']}
        expected = {name for name, package in self.distribution.packages.items()
                    if package['kind'] == 'business'}
        self.assertEqual(covered & expected, expected)
        optional = [item for item in catalog['capabilities'] if item['ownership'] == 'optional']
        self.assertEqual([item['id'] for item in optional], ['download-acceleration'])

    def test_invalid_capability_projection_is_rejected(self):
        for mutation, expected in (
            ('dangling', 'invalid capability module'),
            ('primary-resource', 'primary capability module is not a business package'),
            ('personal-product', 'invalid group'),
            ('uncovered', 'coverage mismatch'),
        ):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                shutil.copytree(ROOT / 'components', root / 'components')
                shutil.copy2(ROOT / 'catalog.json', root / 'catalog.json')
                path = root / 'components/capabilities.json'
                import json
                value = json.loads(path.read_text())
                if mutation == 'dangling':
                    value['capabilities'][0]['modules'][0]['id'] = 'missing-module'
                elif mutation == 'primary-resource':
                    value['capabilities'][0]['modules'][0]['id'] = 'istoreos-storage-path'
                elif mutation == 'personal-product':
                    value['capabilities'][0]['group'] = 'personal'
                else:
                    value['capabilities'] = [item for item in value['capabilities']
                                             if item['id'] != 'windows-services']
                path.write_text(json.dumps(value))
                with self.assertRaisesRegex(ValueError, expected):
                    model.Distribution(root)

    def test_shared_skill_alias_or_platform_prefix_cannot_be_reintroduced(self):
        for change in ('alias', 'prefix'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                shutil.copytree(ROOT / 'components', root / 'components')
                shutil.copy2(ROOT / 'catalog.json', root / 'catalog.json')
                skill = root / 'components/system-packs/common/skills/kai-download-acceleration'
                if change == 'alias':
                    p = skill / 'SKILL.md'
                    p.write_text(p.read_text().replace('---\n', '---\naliases: istoreos-download-acceleration\n', 1))
                    error = 'must not publish aliases'
                else:
                    skill.rename(skill.with_name('istoreos-shared-download'))
                    error = 'require the kai- prefix'
                with self.assertRaisesRegex(ValueError, error):
                    model.Distribution(root)

    def test_one_skill_does_not_activate_code_resource_dependencies(self):
        result = self.distribution.select(skill='kai-project-dependencies')
        self.assertEqual([p['id'] for p in result['packages']], ['kai-project-dependencies'])
        self.assertEqual(result['programOperations'], [])
        self.assertFalse(result['serviceOperations'])
        self.assertEqual(self.distribution.runtime_closure('kai-project-dependencies'),
                         ['kai-dev-environment', 'kai-tool-bootstrap'])

    def test_bundles_expand_only_declared_business_members_and_deduplicate(self):
        config = copy.deepcopy(self.distribution.config)
        config['bundles']['joined'] = {'bundles': ['development', 'software-management']}
        result = model.Distribution(declaration=config).select(bundle='joined')
        self.assertEqual([p['id'] for p in result['packages']],
                         ['kai-dev-environment', 'kai-download-acceleration', 'kai-project-dependencies', 'kai-project-run', 'kai-software'])

    def test_all_ten_platform_modes_match_existing_active_presets(self):
        for preset in self.distribution.legacy['presets']:
            actual = self.distribution.select(platform=preset['platform'], all_skills=True, mode=preset['mode'])
            expected = {p.parent.name for p in (ROOT / preset['path'] / 'skills').glob('*/SKILL.md')}
            self.assertEqual({p['id'] for p in actual['packages']}, expected)
        own = self.distribution.select(platform='istoreos', all_skills=True, mode='remote-control', own_transport=True)
        self.assertTrue(all(p['kind'] != 'transport' for p in own['packages']))

    def test_wrong_platform_architecture_selection_or_mode_is_rejected(self):
        for args in [dict(skill='missing'), dict(bundle='missing'), dict(all_skills=True),
                     dict(all_skills=True, platform='windows'),
                     dict(skill='kai-software', bundle='development'),
                     dict(skill='kai-software', mode='remote-control'),
                     dict(skill='kai-software', platform='windows', architecture='arm64'),
                     dict(skill='istoreos-luci-recovery', platform='ubuntu'),
                     dict(skill='kai-software', platform='unknown'),
                     dict(skill='kai-software', mode='unknown')]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                self.distribution.select(**args)

    def test_missing_member_and_cyclic_bundle_fail_during_load(self):
        for bundles in [{'bad': {'skills': ['missing']}},
                        {'a': {'bundles': ['b']}, 'b': {'bundles': ['a']}}, {'empty': {}}]:
            config = copy.deepcopy(self.distribution.config)
            config['bundles'] = bundles
            with self.assertRaises(ValueError):
                model.Distribution(declaration=config)

    def test_paths_cannot_traverse_or_follow_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'ok').mkdir()
            (root / 'alias').symlink_to(root / 'ok', target_is_directory=True)
            for name in ['../escape', '/absolute', 'alias', 'missing']:
                with self.subTest(name=name), self.assertRaises(ValueError):
                    model.safe_path(root, name)

    def test_locked_member_content_and_version_conflicts_are_explicit(self):
        a = {'id': 'kai-software', 'version': '1.1.0', 'treeDigest': 'sha256:' + 'a' * 64}
        self.assertEqual(model.validate_locked_members([a, a]), [a])
        for changed in [dict(a, version='1.2.0'), dict(a, treeDigest='sha256:' + 'b' * 64), dict(a, id='../bad')]:
            with self.assertRaises(ValueError):
                model.validate_locked_members([a, changed])


if __name__ == '__main__':
    unittest.main()
