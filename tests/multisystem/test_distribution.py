"""Public distribution, migration, isolation and lifecycle contracts."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tarfile
import io
import unittest

ROOT=Path(__file__).resolve().parents[2]
COMMON={'kai-software','kai-dev-environment','kai-project-dependencies',
        'kai-download-acceleration','kai-storage-files','kai-tool-bootstrap'}
SCOPE=json.loads((ROOT/'tests/multisystem/scope.json').read_text())
ALIASES={row['oldId']:row['newId'] for row in SCOPE['migration'] if row['decision']=='extract-with-platform-adapter'}


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='kai distribution 中文 ')
        self.addCleanup(self.temp.cleanup)
        self.work=Path(self.temp.name)

    def test_declarative_presets_cover_platform_modes_and_activate_each_common_skill_once(self):
        output=self.work/'platforms'
        result=subprocess.run(['sh',str(ROOT/'tools/generate-platforms.sh'),str(output)],
                              text=True,capture_output=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        for platform in ['ubuntu','debian','istoreos','macos','windows']:
            for mode in ['on-device','remote-control']:
                preset=output/platform/mode
                self.assertTrue((preset/'preset.json').is_file(),str(preset))
                active={path.parent.name for path in (preset/'skills').glob('*/SKILL.md')}
                self.assertTrue(COMMON<=active,(platform,mode,active))
                self.assertFalse(set(ALIASES)&active,(platform,mode,active))
                if platform!='istoreos':self.assertFalse(any(name.startswith('istoreos-') for name in active))
                if mode=='on-device':self.assertFalse(any(name.startswith('target-') for name in active))
        active={p.parent.name for p in (output/'istoreos/on-device/skills').glob('*/SKILL.md')}
        retained={row['oldId'] for row in SCOPE['migration'] if row['decision']=='retain-platform-specific'}
        self.assertEqual(active,COMMON|retained)

    def test_installer_owns_legacy_resources_without_activating_legacy_skills(self):
        output=self.work/'platforms'
        subprocess.run(['sh',str(ROOT/'tools/generate-platforms.sh'),str(output)],check=True,capture_output=True)
        preset=output/'istoreos/on-device';target=self.work/'agent skills'
        result=subprocess.run(['sh',str(preset/'install.sh'),'--target',str(target)],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        for name in ALIASES:
            self.assertTrue((target/name/'scripts').is_dir(),name)
            self.assertFalse((target/name/'SKILL.md').exists(),name)
        manifest=json.loads((target/'.linkease-skills/istoreos-on-device.json').read_text())
        self.assertEqual({item['name'] for item in manifest['resources']},set(ALIASES))
        self.assertEqual(manifest['skillAliases'],ALIASES)
        protected=target/'unrelated';protected.mkdir();(protected/'keep').write_text('keep')
        result=subprocess.run(['sh',str(preset/'install.sh'),'--target',str(target),'--upgrade'],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        resource=target/'istoreos-storage-path/scripts/detect.sh';resource.write_text(resource.read_text()+'\n# user edit\n')
        result=subprocess.run(['sh',str(preset/'install.sh'),'--target',str(target),'--uninstall'],text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0);self.assertIn('# user edit',resource.read_text())
        self.assertEqual((protected/'keep').read_text(),'keep')

    def test_committed_legacy_preset_upgrade_removes_retired_skills_and_preserves_user_content(self):
        archive=subprocess.check_output(['git','archive','HEAD','platforms/istoreos/on-device'],cwd=ROOT)
        legacy=self.work/'old-checkout';legacy.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:source.extractall(legacy,filter='data')
        old=legacy/'platforms/istoreos/on-device/install.sh'
        target=self.work/'migrated skills'
        result=subprocess.run(['sh',str(old),'--target',str(target)],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(len(list(target.glob('*/SKILL.md'))),20)
        protected=target/'unrelated';protected.mkdir();(protected/'keep').write_text('keep')
        edited=target/'istoreos-storage-path/SKILL.md';original=edited.read_bytes();edited.write_bytes(original+b'\nuser change\n')
        new=ROOT/'platforms/istoreos/on-device/install.sh'
        result=subprocess.run(['sh',str(new),'--target',str(target),'--upgrade'],text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn(b'user change',edited.read_bytes())
        self.assertFalse((target/'kai-software').exists())
        edited.write_bytes(original)
        result=subprocess.run(['sh',str(new),'--target',str(target),'--upgrade'],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(len(list(target.glob('*/SKILL.md'))),22)
        for name in ALIASES:self.assertFalse((target/name/'SKILL.md').exists())
        result=subprocess.run(['sh',str(new),'--target',str(target),'--uninstall'],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual({p.name for p in target.iterdir()},{'unrelated'})
        self.assertEqual((protected/'keep').read_text(),'keep')

    def test_flattened_runtime_bundle_enters_hashed_owner_adapter_without_source_checkout(self):
        output=self.work/'platforms';subprocess.run(['sh',str(ROOT/'tools/generate-platforms.sh'),str(output)],check=True,capture_output=True)
        target=self.work/'standalone';subprocess.run(['sh',str(output/'istoreos/on-device/install.sh'),'--target',str(target)],check=True,capture_output=True)
        system=self.work/'system';(system/'etc').mkdir(parents=True);(system/'etc/openwrt_release').touch()
        home=self.work/'runtime';home.mkdir();bin_dir=self.work/'bin';bin_dir.mkdir();entries=self.work/'entries'
        programs={'uci':'printf "%s\\n" "$TEST_RUNTIME_HOME"',
                  'mise':'exit 4',
                  'mise-exec':'printf entered >> "$TEST_ENTRIES"; export HOME="$TEST_RUNTIME_HOME"; export PATH="$HOME/.local/share/mise/shims:$PATH"; exec sh'}
        for name,body in programs.items():
            path=bin_dir/name;path.write_text('#!/bin/sh\nset -eu\n'+body+'\n');path.chmod(0o700)
        env={**os.environ,'KAI_PLATFORM':'istoreos','ISTORE_SYSTEM_ROOT':str(system),
             'TEST_RUNTIME_HOME':str(home),'TEST_ENTRIES':str(entries),'PATH':str(bin_dir)+':'+os.environ['PATH']}
        helper=target/'kai-dev-environment/scripts/runtime.sh'
        result=subprocess.run(['bash',str(helper),'probe','node','22.14.0'],env=env,text=True,capture_output=True)
        self.assertEqual(result.returncode,4,result.stdout+result.stderr)
        self.assertEqual(json.loads(result.stdout)['category'],'runtime-not-installed')
        self.assertEqual(entries.read_text(),'entered')
        adapter=target/'kai-dev-environment/resources/istore-runtime/exec.sh'
        adapter.write_text(adapter.read_text()+'\n# modified\n')
        result=subprocess.run(['bash',str(helper),'probe','node','22.14.0'],env=env,text=True,capture_output=True)
        self.assertEqual(result.returncode,11,result.stdout+result.stderr)
        self.assertEqual(json.loads(result.stdout)['category'],'integrity-failed')
        self.assertEqual(entries.read_text(),'entered')

    def test_canonical_layers_keep_common_once_and_exclude_third_party_transports(self):
        for component in ['common','istoreos','ubuntu','debian','windows','macos']:
            output=self.work/component
            result=subprocess.run(['python3',str(ROOT/'tools/compose.py'),'layer','--platform',component,'--output',str(output)],
                                  text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            active={path.parent.name for path in (output/'skills').glob('*/SKILL.md')}
            if component=='common':self.assertEqual(active,COMMON)
            else:self.assertFalse(COMMON&active)
            self.assertFalse(set(ALIASES)&active)
            self.assertFalse(any(name.startswith('target-') for name in active))

    def test_actual_consumer_layouts_routing_and_legacy_aliases(self):
        output=self.work/'platforms';subprocess.run(['sh',str(ROOT/'tools/generate-platforms.sh'),str(output)],check=True,capture_output=True)
        result=subprocess.run(['python3',str(ROOT/'tools/test-distribution-consumers.py'),'--presets',str(output)],
                              text=True,capture_output=True,timeout=100)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)


if __name__=='__main__':unittest.main()
