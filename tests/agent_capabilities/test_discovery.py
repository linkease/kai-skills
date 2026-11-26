import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[2]


class DiscoveryTests(unittest.TestCase):
    def test_all_canonical_interfaces_have_advisory_metadata_and_exact_identity(self):
        inventory=json.loads((ROOT/'docs/architecture/readonly-capability-surfaces.json').read_text())
        paths=sorted((ROOT/'components').rglob('SKILL.md'))
        self.assertEqual({p.parent.name for p in paths},{r['resource'] for r in inventory['resources']})
        for p in paths:
            with self.subTest(skill=p.parent.name):
                text=p.read_text();head,body=text.split('---',2)[1:]
                self.assertRegex(head,r'(?m)^name: '+re.escape(p.parent.name)+r'$')
                self.assertRegex(head,r'(?m)^description: .+')
                self.assertIn('resource-discovery: explicit',head)
                self.assertNotRegex(head,r'(?m)^auto-use: (prefer|require)$')
                self.assertNotRegex(head,r'(?m)^routing-group: system-primary$')
                self.assertLessEqual(len(text.encode()),6500)
                self.assertTrue(body.strip())

    def test_runtime_instructions_do_not_impose_old_task_workflows(self):
        patterns=[r'Select one primary skill',r'一次只加载一个主 skill',r'先加载 `istoreos-system-task-router`',
            r'先跑加速闭环',r'follow the dependency workflow below',r'keep the dependency task as the primary lane',
            r'Honor.*next.helper',r'honor its correlation/next-helper',r'默认 auto 且不启动服务',
            r'use only after the shared Debian evidence pass',r'Wait for explicit user confirmation',
            r'only when a selected system skill names the endpoint']
        paths=[p for p in (ROOT/'components').rglob('*.md') if '/resources/owner/' not in p.as_posix()]
        for p in paths:
            text=p.read_text()
            for pattern in patterns:self.assertNotRegex(text,re.compile(pattern,re.I),str(p.relative_to(ROOT)))
        text=(ROOT/'components/system-packs/istoreos/agents/istoreos.md').read_text()
        self.assertIn('一个、多个、不使用 skill',text)
        self.assertIn('宿主管理',text)
        self.assertIn('通用分析继续可用',text)

    def test_entry_contracts_describe_real_write_parameters_and_boundaries(self):
        base=ROOT/'components/system-packs/istoreos/skills'
        for name,fields in {
            'istoreos-service-manager':['expectedInitSHA256','expectedConfigSHA256','expectedEngineId','expectedDataRoot','operationId'],
            'istoreos-docker-data-root-migrate':['docker.data.copy','sourceIdentity','destinationParentIdentity','非空目标','不修改 UCI'],
            'istoreos-run-executable':['sha256','runner','arguments','workingDirectory','执行的是拥有的校验副本'],
            'istoreos-backup-restore':['checkpointId','diffId','verificationScope','受理不等于完成'],
            'istoreos-luci-recovery':['package.reinstall','artifact','sha256','不重启服务']}.items():
            text=(base/name/'SKILL.md').read_text()
            for field in fields:self.assertIn(field,text)
        text=(ROOT/'components/system-packs/common/skills/kai-project-run/SKILL.md').read_text()
        self.assertIn('project.kind',text);self.assertIn('requires explicit `runScript`',text)

    def test_document_links_are_explicit_and_resolve_inside_the_resource(self):
        for p in (ROOT/'components').rglob('SKILL.md'):
            for target in re.findall(r'\]\(([^)]+)\)',p.read_text()):
                if '://' in target or target.startswith('#'):continue
                dest=p.parent/target.split('#')[0]
                self.assertTrue(dest.is_file(),str(p.relative_to(ROOT))+': '+target)

    def test_legacy_package_service_alias_has_no_inferred_mutation(self):
        p=ROOT/'components/system-packs/istoreos/skills/istoreos-package-manager/scripts/ensure_services_from_pkg.sh'
        text=p.read_text()
        self.assertNotIn('package.sh',text);self.assertNotIn('while ',text)
        result=subprocess.run(['sh',str(p),'unselected-package'],capture_output=True,text=True,timeout=5)
        self.assertNotEqual(result.returncode,0)
        receipt=json.loads(result.stdout)
        self.assertEqual(receipt['effects']['completed'],[])
        self.assertEqual(receipt['errors'][0]['code'],'INVALID_ARGUMENT')


if __name__=='__main__':unittest.main()
